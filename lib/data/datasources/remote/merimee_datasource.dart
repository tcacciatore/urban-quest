import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../domain/entities/city.dart';
import '../../../domain/entities/city_poi.dart';

/// Datasource pour la base Mérimée (Monuments Historiques).
/// Source : data.culture.gouv.fr — Plateforme Ouverte du Patrimoine.
class MerimeeDatasource {
  final Dio _dio;

  MerimeeDatasource(this._dio);

  static const _baseUrl =
      'https://data.culture.gouv.fr/api/explore/v2.1/catalog/datasets'
      '/liste-des-immeubles-proteges-au-titre-des-monuments-historiques/records';

  static const _selectCity =
      'reference,'
      'titre_editorial_de_la_notice,'
      'denomination_de_l_edifice,'
      'datation_de_l_edifice,'
      'date_et_typologie_de_la_protection,'
      'historique,'
      'description_de_l_edifice,'
      'precision_de_la_protection,'
      'observations,'
      'commune_forme_index,'
      'coordonnees_au_format_wgs84';

  static const _selectNear =
      'denomination_de_l_edifice,'
      'precision_de_la_protection,'
      'date_et_typologie_de_la_protection,'
      'historique,'
      'description_de_l_edifice,'
      'observations,'
      'commune_forme_index,'
      'coordonnees_au_format_wgs84';

  // ─── Mapping dénomination → emoji ─────────────────────────────────────────

  static const Map<String, String> _emoji = {
    'église':          '⛪',
    'chapelle':        '⛪',
    'cathédrale':      '⛪',
    'basilique':       '⛪',
    'abbaye':          '⛪',
    'prieuré':         '⛪',
    'couvent':         '⛪',
    'oratoire':        '⛪',
    'temple':          '🛕',
    'synagogue':       '🕍',
    'mosquée':         '🕌',
    'château':         '🏰',
    'manoir':          '🏰',
    'fort':            '🏰',
    'citadelle':       '🏰',
    'donjon':          '🏰',
    'remparts':        '🏰',
    'tour':            '🗼',
    'phare':           '🗼',
    'monument':        '🗿',
    'statue':          '🗿',
    'colonne':         '🗿',
    'stèle':           '🗿',
    'fontaine':        '⛲',
    'lavoir':          '⛲',
    'théâtre':         '🎭',
    'opéra':           '🎭',
    'musée':           '🎨',
    'hôtel particulier': '🏛️',
    'hôtel de ville':  '🏛️',
    'palais':          '🏛️',
    'mairie':          '🏛️',
    'préfecture':      '🏛️',
    'tribunal':        '🏛️',
    'pont':            '🌉',
    'viaduc':          '🌉',
    'moulin':          '⚙️',
    'villa':           '🏠',
    'maison':          '🏠',
    'ferme':           '🏚️',
    'grange':          '🏚️',
    'gare':            '🚉',
    'école':           '🏫',
    'cimetière':       '🕯️',
    'croix':           '✝️',
    'calvaire':        '✝️',
    'dolmen':          '⚱️',
    'menhir':          '⚱️',
    'tumulus':         '⚱️',
    'grotte':          '🕳️',
    'jardin':          '🌸',
    'parc':            '🌸',
    'rendez-vous de chasse': '🏰',
  };

  // ─── Chargement par ville ──────────────────────────────────────────────────

  /// Récupère tous les monuments historiques dans le polygone de la ville.
  /// Utilise une recherche géographique par centroïde + rayon englobant.
  Future<List<CityPoi>> fetchForCity(City city) async {
    final center = _centroid(city.polygon);
    final radius = _maxRadius(city.polygon, center);

    final lon = center.longitude.toStringAsFixed(6);
    final lat = center.latitude.toStringAsFixed(6);
    final where =
        "distance(coordonnees_au_format_wgs84, geom'POINT($lon $lat)', ${radius.round()}m)";

    final allRecords = <Map<String, dynamic>>[];
    int offset = 0;
    const pageSize = 100;

    try {
      while (true) {
        final resp = await _dio.get(
          _baseUrl,
          queryParameters: {
            'limit': pageSize,
            'offset': offset,
            'where': where,
            'select': _selectCity,
          },
          options: Options(receiveTimeout: const Duration(seconds: 15)),
        );

        final results = resp.data['results'] as List<dynamic>? ?? [];
        allRecords.addAll(results.cast<Map<String, dynamic>>());
        if (results.length < pageSize) break;
        offset += pageSize;
      }
    } catch (e) {
      debugPrint('[Mérimée] fetchForCity erreur pour ${city.name}: $e');
    }

    debugPrint('[Mérimée] ${allRecords.length} records bruts pour ${city.name}');

    final pois = <CityPoi>[];
    for (final r in allRecords) {
      final poi = _recordToPoi(r, city);
      if (poi != null) pois.add(poi);
    }

    debugPrint('[Mérimée] ${pois.length} POIs dans le polygone de ${city.name}');
    return pois;
  }

  CityPoi? _recordToPoi(Map<String, dynamic> r, City city) {
    final coords = r['coordonnees_au_format_wgs84'] as Map<String, dynamic>?;
    if (coords == null) return null;
    final lat = (coords['lat'] as num?)?.toDouble();
    final lon = (coords['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    final position = LatLng(lat, lon);
    if (!_pip(position, city.polygon)) return null;

    final ref = (r['reference'] as String?) ?? '';
    final denomination = (r['denomination_de_l_edifice'] as String?) ?? '';
    final titreEditorial = r['titre_editorial_de_la_notice'] as String?;

    final emoji = _resolveEmoji(denomination);
    final name = _resolveName(titreEditorial, denomination, city.name);
    final info = _parseRecord(r);

    return CityPoi(
      id: 'mh_${city.id}_$ref',
      cityId: city.id,
      name: name,
      emoji: emoji,
      position: position,
      description: info?.fullDescription,
    );
  }

  String _resolveEmoji(String denomination) {
    final d = denomination.toLowerCase().trim();
    for (final entry in _emoji.entries) {
      if (d.contains(entry.key)) return entry.value;
    }
    return '🏛️'; // défaut : bâtiment patrimonial
  }

  String _resolveName(String? titreEditorial, String denomination, String cityName) {
    // Priorité : titre éditorial (nom propre complet)
    if (titreEditorial != null && titreEditorial.trim().isNotEmpty) {
      return _capitalize(titreEditorial.trim());
    }
    // Sinon : dénomination générique
    final den = _capitalize(denomination.trim());
    if (den.isEmpty) return cityName;
    return den;
  }

  // ─── Recherche ponctuelle (enrichissement d'un POI Overpass) ─────────────

  /// Cherche un monument historique proche des coordonnées du POI.
  Future<MerimeeInfo?> fetchNearPoi(
    LatLng position, {
    int radiusMeters = 150,
  }) async {
    final lon = position.longitude.toStringAsFixed(6);
    final lat = position.latitude.toStringAsFixed(6);
    final where =
        "distance(coordonnees_au_format_wgs84, geom'POINT($lon $lat)', ${radiusMeters}m)";

    try {
      final resp = await _dio.get(
        _baseUrl,
        queryParameters: {
          'limit': 5,
          'where': where,
          'select': _selectNear,
        },
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final results = resp.data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final sorted = results
          .map((r) => r as Map<String, dynamic>)
          .where((r) => r['coordonnees_au_format_wgs84'] != null)
          .toList()
        ..sort((a, b) {
          final da = _distTo(position, a['coordonnees_au_format_wgs84']);
          final db = _distTo(position, b['coordonnees_au_format_wgs84']);
          return da.compareTo(db);
        });

      if (sorted.isEmpty) return null;
      return _parseRecord(sorted.first);
    } catch (e) {
      debugPrint('[Mérimée] fetchNearPoi erreur: $e');
      return null;
    }
  }

  // ─── Parsing commun ───────────────────────────────────────────────────────

  MerimeeInfo? _parseRecord(Map<String, dynamic> r) {
    final denomination = r['denomination_de_l_edifice'] as String?;
    final protection = r['date_et_typologie_de_la_protection'] as String?;
    final datation = r['datation_de_l_edifice'] as String?;
    final historique = r['historique'] as String?;
    final description = r['description_de_l_edifice'] as String?;
    final precisionProtection = r['precision_de_la_protection'] as String?;
    final observations = r['observations'] as String?;

    String? badge;
    if (protection != null) {
      final lower = protection.toLowerCase();
      final type = lower.contains('class') ? 'Classé MH' : 'Inscrit MH';
      final yearMatch = RegExp(r'\b(\d{4})\b').firstMatch(protection);
      badge = yearMatch != null ? '$type · ${yearMatch.group(1)}' : type;
    }

    // Ajoute la date de construction si disponible
    if (datation != null && datation.trim().isNotEmpty) {
      final d = datation.trim();
      badge = badge != null ? '$badge · $d' : d;
    }

    final body = _firstNonEmpty(
        [historique, description, precisionProtection, observations]);

    if (badge == null && body == null) return null;

    return MerimeeInfo(
      denomination: denomination,
      badge: badge,
      body: body != null && body.length > 600
          ? '${body.substring(0, 600).trimRight()}…'
          : body,
    );
  }

  // ─── Helpers géométriques ─────────────────────────────────────────────────

  LatLng _centroid(List<LatLng> polygon) {
    final lat =
        polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final lon =
        polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
    return LatLng(lat, lon);
  }

  double _maxRadius(List<LatLng> polygon, LatLng center) {
    double max = 0;
    for (final p in polygon) {
      final d = _distMeters(center, p);
      if (d > max) max = d;
    }
    // +20% de marge pour couvrir les bords du polygone
    return max * 1.2;
  }

  double _distMeters(LatLng a, LatLng b) {
    const k = 111320.0;
    final cosLat = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final dx = (b.longitude - a.longitude) * cosLat * k;
    final dy = (b.latitude - a.latitude) * k;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _distTo(LatLng pos, dynamic wgs84) {
    if (wgs84 == null) return double.infinity;
    final lon = (wgs84['lon'] as num?)?.toDouble() ?? 0;
    final lat = (wgs84['lat'] as num?)?.toDouble() ?? 0;
    return _distMeters(pos, LatLng(lat, lon));
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

  String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Informations Mérimée pour un POI.
class MerimeeInfo {
  final String? denomination;
  final String? badge;
  final String? body;

  const MerimeeInfo({this.denomination, this.badge, this.body});

  String? get fullDescription {
    final parts = <String>[];
    if (badge != null) parts.add(badge!);
    if (body != null) parts.add(body!);
    return parts.isEmpty ? null : parts.join('\n\n');
  }
}
