import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/api_constants.dart';
import '../../../domain/entities/city.dart';
import '../../../domain/entities/city_poi.dart';

class PoiRemoteDatasource {
  final Dio _dio;
  PoiRemoteDatasource(this._dio);

  static const _minDistanceMeters = 200.0;

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

  Future<List<CityPoi>> fetchPoisForCity(City city) async {
    final bbox = _cityBbox(city.polygon);
    final query = _buildQuery(bbox);

    try {
      final resp = await _dio.get(
        ApiConstants.overpassUrl,
        queryParameters: {'data': query},
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );

      final elements = resp.data['elements'] as List<dynamic>? ?? [];
      final candidates = <CityPoi>[];

      for (final el in elements) {
        final poi = _parsePoi(el as Map<String, dynamic>, city.id, city.polygon);
        if (poi != null) candidates.add(poi);
      }

      final count = _poiCountForCity(city.polygon);
      debugPrint('[POI] ${candidates.length} candidats pour ${city.name} → $count POIs');
      return _selectDistributed(candidates, count, _minDistanceMeters);
    } catch (e) {
      debugPrint('[POI] erreur fetchPoisForCity(${city.name}): $e');
      return [];
    }
  }

  // ─── Privé ────────────────────────────────────────────────────────────────

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

  CityPoi? _parsePoi(
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

    return CityPoi(
      id: '${cityId}_$id',
      cityId: cityId,
      name: name,
      emoji: emoji,
      position: position,
    );
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

    // Déduplique les POIs trop proches
    final deduped = _deduplicate(candidates, minDist / 2);
    if (deduped.isEmpty) return [];
    if (deduped.length <= count) return deduped;

    // Centroïde de la ville (approximé depuis les candidats)
    final centerLat = deduped.map((p) => p.position.latitude).reduce((a, b) => a + b) / deduped.length;
    final centerLon = deduped.map((p) => p.position.longitude).reduce((a, b) => a + b) / deduped.length;
    final center = LatLng(centerLat, centerLon);

    // Rayon max (distance du candidat le plus éloigné du centroïde)
    final maxDist = deduped
        .map((p) => _distMeters(p.position, center))
        .reduce((a, b) => a > b ? a : b);

    // Ne retenir que les POIs dans la zone centrale (60 % du rayon).
    // Si trop peu survivent, on élargit progressivement jusqu'à 100 %.
    List<CityPoi> pool = [];
    for (final threshold in [0.60, 0.75, 0.90, 1.0]) {
      pool = deduped
          .where((p) => _distMeters(p.position, center) <= maxDist * threshold)
          .toList();
      if (pool.length >= count) break;
    }
    if (pool.isEmpty) pool = deduped;

    if (pool.length <= count) return pool;

    // Point de départ : le POI le plus proche du centroïde
    pool.sort((a, b) =>
        _distMeters(a.position, center).compareTo(_distMeters(b.position, center)));

    final selected = <CityPoi>[pool.first];
    final remaining = pool.sublist(1).toList();

    while (selected.length < count && remaining.isNotEmpty) {
      final usedEmojis = selected.map((p) => p.emoji).toSet();

      // Priorité aux candidats avec un emoji non encore utilisé
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

  double _distSq(LatLng a, LatLng b) {
    final dlat = a.latitude - b.latitude;
    final dlon = a.longitude - b.longitude;
    return dlat * dlat + dlon * dlon;
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
