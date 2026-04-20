import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/api_constants.dart';
import '../../../domain/entities/city.dart';
import '../../../domain/entities/city_poi.dart';
import 'merimee_datasource.dart';

class PoiRemoteDatasource {
  final Dio _dio;
  late final MerimeeDatasource _merimee;

  PoiRemoteDatasource(this._dio) {
    _merimee = MerimeeDatasource(_dio);
  }

  static const _minDistanceMeters = 80.0;

  /// Nombre de POIs adapté à la taille de la ville (diagonale du bbox).
  int _poiCountForCity(List<LatLng> polygon) {
    final bbox = _cityBbox(polygon);
    final diagonal = _distMeters(
      LatLng(bbox.south, bbox.west),
      LatLng(bbox.north, bbox.east),
    );
    if (diagonal < 2000)  return 3;
    if (diagonal < 5000)  return 5;
    if (diagonal < 10000) return 8;
    return 12;
  }

  static const Map<String, String> _historicEmoji = {
    'monument':            '🗿',
    'memorial':            '🕯️',
    'castle':              '🏰',
    'ruins':               '⛩️',
    'archaeological_site': '⚱️',
    'wayside_cross':       '✝️',
    'fort':                '🏰',
    'city_gate':           '⛩️',
  };

  static const Map<String, String> _tourismEmoji = {
    'artwork':    '🎨',
    'viewpoint':  '🔭',
    'attraction': '⭐',
  };

  static const Map<String, String> _amenityEmoji = {
    'fountain': '⛲',
    'theatre':  '🎭',
    'cinema':   '🎬',
    'library':  '📚',
    'clock':    '🕰️',
  };

  static const Map<String, String> _naturalEmoji = {
    'peak':          '⛰️',
    'tree':          '🌳',
    'spring':        '💧',
    'cave_entrance': '🕳️',
  };

  static const Map<String, String> _leisureEmoji = {
    'garden':         '🌸',
    'nature_reserve': '🌿',
  };

  static const Map<String, String> _religionEmoji = {
    'christian': '⛪',
    'muslim':    '🕌',
    'jewish':    '🕍',
    'buddhist':  '🛕',
    'hindu':     '🛕',
  };

  /// Phase 1 (prioritaire) : POIs depuis la base Mérimée — rapide et fiable.
  Future<List<CityPoi>> fetchMerimeePoisForCity(City city) =>
      _merimee.fetchForCity(city);

  /// Phase 2 : POIs depuis Overpass — plus variés mais plus lents.
  /// [existingPositions] : coordonnées des POIs Mérimée déjà chargés,
  /// pour éviter les doublons stricts (rayon de 30 m).
  Future<List<CityPoi>> fetchOverpassPoisForCity(
    City city, {
    List<LatLng> existingPositions = const [],
  }) async {
    final pois = await _fetchOverpassRaw(city);
    if (existingPositions.isEmpty) return pois;
    // Filtre les POIs au même emplacement qu'un POI Mérimée
    return pois.where((poi) {
      return !existingPositions
          .any((ep) => _distMeters(poi.position, ep) < 30);
    }).toList();
  }

  Future<List<CityPoi>> _fetchOverpassRaw(City city) async {
    final bbox  = _cityBbox(city.polygon);
    final query = _buildQuery(bbox);

    // Essaie chaque mirror jusqu'à succès
    List<dynamic>? elements;
    for (int i = 0; i < ApiConstants.overpassMirrors.length; i++) {
      final mirror = ApiConstants.overpassMirrors[i];
      try {
        debugPrint('[POI] tentative Overpass ($mirror) pour ${city.name}…');
        final resp = await _dio.get(
          mirror,
          queryParameters: {'data': query},
          options: Options(receiveTimeout: const Duration(seconds: 45)),
        );
        elements = resp.data['elements'] as List<dynamic>? ?? [];
        debugPrint('[POI] succès ($mirror) — ${elements.length} éléments bruts');
        break; // succès
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        debugPrint('[POI] mirror $mirror → ${code ?? e.type} pour ${city.name}');
        if (i == ApiConstants.overpassMirrors.length - 1) {
          debugPrint('[POI] tous les mirrors ont échoué pour ${city.name}');
          return [];
        }
        // Délai croissant entre tentatives : 5s, 10s, 15s...
        final delaySeconds = 5 * (i + 1);
        debugPrint('[POI] attente $delaySeconds s avant prochain mirror…');
        await Future.delayed(Duration(seconds: delaySeconds));
      } catch (e) {
        debugPrint('[POI] erreur inattendue ($mirror) pour ${city.name}: $e');
        return [];
      }
    }

    if (elements == null) return [];

    // ── 1. Parse les candidats bruts ──────────────────────────────────────────
    // Stocke (poi, tags) pour la recherche Wikipedia multi-méthodes.
    final rawCandidates = <(CityPoi, Map<String, dynamic>)>[];
    for (final el in elements) {
      final parsed = _parsePoi(el as Map<String, dynamic>, city.id, city.polygon);
      if (parsed != null) rawCandidates.add(parsed);
    }
    debugPrint('[POI] ${rawCandidates.length} candidats bruts pour ${city.name}');

    // ── 2. Enrichissement Wikipedia optionnel (par lots de 6) ────────────────
    final enriched = <CityPoi>[];
    const batchSize = 6;
    for (int i = 0; i < rawCandidates.length; i += batchSize) {
      final batch = rawCandidates.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((r) async {
          final (poi, tags) = r;
          final desc = await _fetchWikipediaInfo(tags, poi.name);
          return desc != null && desc.isNotEmpty
              ? poi.copyWith(description: desc)
              : poi;
        }),
      );
      enriched.addAll(results);
    }

    final count = _poiCountForCity(city.polygon);
    final withDesc = enriched.where((p) => p.description != null).length;
    debugPrint('[POI] Overpass: ${enriched.length} POIs ($withDesc avec desc) → sélection de $count pour ${city.name}');

    return _selectDistributed(enriched, count, _minDistanceMeters);
  }

  // ─── Wikipedia ────────────────────────────────────────────────────────────────

  /// Recherche Wikipedia en 3 méthodes successives.
  Future<String?> _fetchWikipediaInfo(Map<String, dynamic> tags, String name) async {
    // Méthode 1 : tag OSM `wikipedia` (ex. "fr:Tour Eiffel")
    final wikiTag = tags['wikipedia'] as String?;
    if (wikiTag != null) {
      final desc = await _fetchFromWikipediaTag(wikiTag);
      if (desc != null) return desc;
    }

    // Méthode 2 : tag OSM `wikidata` (ex. "Q243") → sitelink fr/en → fetch
    final wikidata = tags['wikidata'] as String?;
    if (wikidata != null) {
      final desc = await _fetchFromWikidata(wikidata);
      if (desc != null) return desc;
    }

    // Méthode 3 : lookup par nom exact sur Wikipedia fr puis en
    return _fetchFromName(name);
  }

  /// Méthode 1 : tag `wikipedia` = "lang:Titre Article"
  Future<String?> _fetchFromWikipediaTag(String tag) async {
    try {
      final colonIdx = tag.indexOf(':');
      if (colonIdx == -1) return null;
      final lang  = tag.substring(0, colonIdx).trim();
      final title = tag.substring(colonIdx + 1).trim().replaceAll(' ', '_');
      if (lang.isEmpty || title.isEmpty) return null;
      return _fetchWikipediaSummary(lang, title);
    } catch (_) {
      return null;
    }
  }

  /// Méthode 2 : Wikidata QID → trouver le titre Wikipedia fr (ou en) → fetch
  Future<String?> _fetchFromWikidata(String qid) async {
    try {
      final resp = await _dio.get(
        'https://www.wikidata.org/w/api.php',
        queryParameters: {
          'action': 'wbgetentities',
          'ids': qid,
          'props': 'sitelinks',
          'sitefilter': 'frwiki|enwiki',
          'format': 'json',
          'formatversion': '2',
        },
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final entities = resp.data['entities'] as Map<String, dynamic>?;
      final entity   = entities?[qid] as Map<String, dynamic>?;
      final links    = entity?['sitelinks'] as Map<String, dynamic>?;
      if (links == null) return null;

      // Préférence : Wikipedia français
      for (final (site, lang) in [('frwiki', 'fr'), ('enwiki', 'en')]) {
        final link = links[site] as Map<String, dynamic>?;
        final title = link?['title'] as String?;
        if (title != null && title.isNotEmpty) {
          final desc = await _fetchWikipediaSummary(lang, title.replaceAll(' ', '_'));
          if (desc != null) return desc;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Méthode 3 : recherche Wikipedia par nom, avec validation de pertinence.
  /// L'article retourné doit contenir au moins un mot significatif du nom du POI
  /// pour éviter les faux positifs (ex. "Club Mgen-92" → "Rueil-Malmaison").
  Future<String?> _fetchFromName(String name) async {
    // Mots significatifs du nom (longueur > 3, hors articles/prépositions)
    final stopWords = {'les', 'des', 'aux', 'sur', 'sous', 'dans', 'par', 'pour'};
    final significantWords = _normalizeStr(name)
        .split(RegExp(r'[\s\-_]+'))
        .where((w) => w.length > 3 && !stopWords.contains(w))
        .toSet();

    // Sans mots significatifs → trop générique, on abandonne
    if (significantWords.isEmpty) return null;

    for (final lang in ['fr', 'en']) {
      try {
        final searchResp = await _dio.get(
          'https://$lang.wikipedia.org/w/api.php',
          queryParameters: {
            'action': 'query',
            'list': 'search',
            'srsearch': name,
            'srlimit': '3',
            'srprop': '',
            'format': 'json',
            'formatversion': '2',
          },
          options: Options(receiveTimeout: const Duration(seconds: 8)),
        );
        final results =
            searchResp.data['query']?['search'] as List<dynamic>?;
        if (results == null || results.isEmpty) continue;

        for (final result in results) {
          final title = result['title'] as String?;
          if (title == null || title.isEmpty) continue;

          // Vérifie que le titre contient au moins un mot significatif du POI
          final normalizedTitle = _normalizeStr(title);
          final isRelevant = significantWords
              .any((w) => normalizedTitle.contains(w));
          if (!isRelevant) continue;

          final desc = await _fetchWikipediaSummary(
              lang, title.replaceAll(' ', '_'));
          if (desc != null) return desc;
        }
      } catch (_) {}
    }
    return null;
  }

  String _normalizeStr(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll(RegExp(r'ç'), 'c')
      .replaceAll(RegExp(r'œ'), 'oe')
      .replaceAll(RegExp(r'æ'), 'ae');

  /// Appel REST Wikipedia et extrait le résumé (~300 chars).
  Future<String?> _fetchWikipediaSummary(String lang, String title) async {
    try {
      final resp = await _dio.get(
        'https://$lang.wikipedia.org/api/rest_v1/page/summary/$title',
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 5),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (resp.statusCode != 200) return null;
      final extract = resp.data['extract'] as String?;
      if (extract == null || extract.isEmpty) return null;
      return extract.length > 500 ? '${extract.substring(0, 500).trimRight()}…' : extract;
    } catch (_) {
      return null;
    }
  }

  // ─── Privé ────────────────────────────────────────────────────────────────────

  ({double south, double west, double north, double east}) _cityBbox(
      List<LatLng> polygon) {
    double south = polygon.first.latitude, north = polygon.first.latitude;
    double west = polygon.first.longitude, east = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return (south: south, west: west, north: north, east: east);
  }

  String _buildQuery(
      ({double south, double west, double north, double east}) bbox) {
    final b = '${bbox.south},${bbox.west},${bbox.north},${bbox.east}';
    return '''
[out:json][timeout:30];
(
  node["historic"~"monument|memorial|castle|ruins|archaeological_site|wayside_cross|fort|city_gate"]($b);
  node["tourism"~"artwork|viewpoint|attraction"]($b);
  node["amenity"~"fountain|theatre|cinema|library|clock"]($b);
  node["amenity"="place_of_worship"]($b);
  node["natural"~"peak|tree|spring|cave_entrance"]["name"]($b);
  node["leisure"~"garden|nature_reserve"]["name"]($b);
  way["historic"~"monument|memorial|castle|ruins|archaeological_site|fort|city_gate"]($b);
  way["tourism"~"artwork|viewpoint|attraction"]($b);
  way["amenity"="place_of_worship"]($b);
  way["leisure"~"garden|nature_reserve"]["name"]($b);
);
out center tags;
''';
  }

  /// Retourne `(CityPoi, wikiTag?)` ou null si le POI est invalide.
  (CityPoi, Map<String, dynamic>)? _parsePoi(
      Map<String, dynamic> el, String cityId, List<LatLng> cityPolygon) {
    final id = el['id']?.toString();
    if (id == null) return null;

    final tags = el['tags'] as Map<String, dynamic>? ?? {};
    final name =
        (tags['name'] ?? tags['name:fr'] ?? tags['short_name']) as String?;
    if (name == null || name.isEmpty) return null;

    double? lat, lon;
    if (el['type'] == 'node') {
      lat = (el['lat'] as num?)?.toDouble();
      lon = (el['lon'] as num?)?.toDouble();
    } else {
      final center = el['center'] as Map<String, dynamic>?;
      lat = (center?['lat'] as num?)?.toDouble();
      lon = (center?['lon'] as num?)?.toDouble();
    }
    if (lat == null || lon == null) return null;

    final position = LatLng(lat, lon);
    if (!_pip(position, cityPolygon)) return null;

    final emoji = _resolveEmoji(tags);
    if (emoji == null) return null;

    final poi = CityPoi(
      id: '${cityId}_$id',
      cityId: cityId,
      name: name,
      emoji: emoji,
      position: position,
    );

    return (poi, tags);
  }

  String? _resolveEmoji(Map<String, dynamic> tags) {
    final historic = tags['historic'] as String?;
    if (historic != null && _historicEmoji.containsKey(historic)) {
      return _historicEmoji[historic];
    }
    final tourism = tags['tourism'] as String?;
    if (tourism != null && _tourismEmoji.containsKey(tourism)) {
      return _tourismEmoji[tourism];
    }
    final amenity = tags['amenity'] as String?;
    if (amenity == 'place_of_worship') {
      final religion = tags['religion'] as String?;
      return _religionEmoji[religion] ?? '🛐';
    }
    if (amenity != null && _amenityEmoji.containsKey(amenity)) {
      return _amenityEmoji[amenity];
    }
    final natural = tags['natural'] as String?;
    if (natural != null && _naturalEmoji.containsKey(natural)) {
      return _naturalEmoji[natural];
    }
    final leisure = tags['leisure'] as String?;
    if (leisure != null && _leisureEmoji.containsKey(leisure)) {
      return _leisureEmoji[leisure];
    }
    return null;
  }

  /// Greedy max-min : sélectionne `count` POIs bien distribués dans la zone centrale.
  List<CityPoi> _selectDistributed(
      List<CityPoi> candidates, int count, double minDist) {
    if (candidates.isEmpty) return [];

    final deduped = _deduplicate(candidates, minDist / 2);
    if (deduped.isEmpty) return [];
    if (deduped.length <= count) return deduped;

    final centerLat = deduped.map((p) => p.position.latitude).reduce((a, b) => a + b) / deduped.length;
    final centerLon = deduped.map((p) => p.position.longitude).reduce((a, b) => a + b) / deduped.length;
    final center = LatLng(centerLat, centerLon);

    final maxDist = deduped
        .map((p) => _distMeters(p.position, center))
        .reduce((a, b) => a > b ? a : b);

    List<CityPoi> pool = [];
    for (final threshold in [0.60, 0.75, 0.90, 1.0]) {
      pool = deduped
          .where((p) => _distMeters(p.position, center) <= maxDist * threshold)
          .toList();
      if (pool.length >= count) break;
    }
    if (pool.isEmpty) pool = deduped;
    if (pool.length <= count) return pool;

    pool.sort((a, b) =>
        _distMeters(a.position, center).compareTo(_distMeters(b.position, center)));

    final selected = <CityPoi>[pool.first];
    final remaining = pool.sublist(1).toList();

    while (selected.length < count && remaining.isNotEmpty) {
      final usedEmojis = selected.map((p) => p.emoji).toSet();
      final preferredPool = remaining.where((p) => !usedEmojis.contains(p.emoji)).toList();
      final searchPool = preferredPool.isNotEmpty ? preferredPool : remaining;

      double bestScore = -1;
      int bestIdx = -1;

      for (int i = 0; i < searchPool.length; i++) {
        final candidate = searchPool[i];
        double minD = double.infinity;
        for (final sel in selected) {
          final d = _distMeters(candidate.position, sel.position);
          if (d < minD) minD = d;
        }
        if (minD > bestScore) {
          bestScore = minD;
          bestIdx = i;
        }
      }

      if (bestIdx == -1 || bestScore < minDist) break;
      final chosen = searchPool[bestIdx];
      remaining.remove(chosen);
      selected.add(chosen);
    }

    return selected;
  }

  List<CityPoi> _deduplicate(List<CityPoi> pois, double minDist) {
    final result = <CityPoi>[];
    for (final poi in pois) {
      final tooClose =
          result.any((r) => _distMeters(r.position, poi.position) < minDist);
      if (!tooClose) result.add(poi);
    }
    return result;
  }

  double _distMeters(LatLng a, LatLng b) {
    const k = 111320.0;
    final cosLat = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final dx = (b.longitude - a.longitude) * cosLat * k;
    final dy = (b.latitude - a.latitude) * k;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _pip(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    int crossings = 0;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }
}
