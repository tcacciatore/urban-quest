import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/api_constants.dart';
import '../../../domain/entities/quarter.dart';

class QuarterRemoteDatasource {
  final Dio _dio;

  QuarterRemoteDatasource(this._dio);

  // ─── API publique ────────────────────────────────────────────────────────────

  /// Charge TOUS les quartiers de la ville contenant [center].
  ///
  /// Stratégie (strictement limitée à la ville, jamais aux communes voisines) :
  ///   1. Trouve la ville (admin_level 8 → 7 → 6) via is_in.
  ///   2. Tente de charger les sous-quartiers (admin_level 10 → 9) dans cette ville.
  ///   3. Si aucun sous-quartier trouvé dans OSM, utilise le polygone de la ville
  ///      elle-même comme zone unique à révéler.
  ///   4. Si aucune ville OSM trouvée → retourne [] (aucun brouillard affiché).
  ///
  /// Pas de fallback "radius" : on ne déborde jamais sur les communes voisines.
  Future<({List<Quarter> quarters, String? cityId})> fetchCityQuarters(
    LatLng center,
  ) async {
    final city = await _fetchCityRelation(center);
    if (city == null) {
      debugPrint('[FogOfWar] aucune ville OSM trouvée pour ${center.latitude},${center.longitude}');
      return (quarters: <Quarter>[], cityId: null);
    }

    final (areaId, relId) = city;
    debugPrint('[FogOfWar] ville trouvée: relId=$relId');

    // Sous-quartiers dans la ville
    var quarters = await _fetchQuartersInCity(areaId);
    debugPrint('[FogOfWar] _fetchQuartersInCity → ${quarters.length} quartiers');

    // Fallback : polygone de la ville elle-même — nécessite 5 chasses pour révéler
    if (quarters.isEmpty) {
      debugPrint('[FogOfWar] fallback → polygone de la ville entière');
      final cityAsQuarter = await _fetchRelationAsQuarter(relId);
      if (cityAsQuarter != null) {
        quarters = [cityAsQuarter.copyWith(requiredHunts: 5, cityId: relId)];
      }
    } else {
      // Associer chaque sous-quartier à sa ville
      quarters = quarters.map((q) => q.copyWith(cityId: relId)).toList();
    }

    return (quarters: quarters, cityId: relId);
  }

  /// Retourne le quartier contenant exactement [point] (fallback ponctuel).
  Future<Quarter?> fetchQuarterForPoint(LatLng point) async {
    final lat = point.latitude;
    final lon = point.longitude;
    final query = '''
[out:json][timeout:20];
is_in($lat,$lon)->.a;
relation(pivot.a)[boundary=administrative][admin_level~"^(10|9|8)\$"];
out geom;
''';
    try {
      final response = await _dio.get(
        ApiConstants.overpassUrl,
        queryParameters: {'data': query},
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final elements = response.data['elements'] as List<dynamic>?;
      if (elements == null || elements.isEmpty) return null;
      elements.sort((a, b) {
        final la = int.tryParse(a['tags']?['admin_level'] as String? ?? '0') ?? 0;
        final lb = int.tryParse(b['tags']?['admin_level'] as String? ?? '0') ?? 0;
        return lb.compareTo(la);
      });
      for (final e in elements) {
        final q = _parseRelation(e as Map<String, dynamic>);
        if (q != null) return q;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Privé ───────────────────────────────────────────────────────────────────

  /// Retourne (areaId, relationId) de la ville, ou null.
  Future<(String, String)?> _fetchCityRelation(LatLng center) async {
    final lat = center.latitude;
    final lon = center.longitude;

    // Level 8 = commune en France. Pas de fallback sur 7/6 (canton/département)
    // car cela contaminerait les communes voisines.
    for (final level in ['8']) {
      final query = '''
[out:json][timeout:15];
is_in($lat,$lon)->.a;
relation(pivot.a)[boundary=administrative][admin_level="$level"];
out ids;
''';
      try {
        final resp = await _dio.get(
          ApiConstants.overpassUrl,
          queryParameters: {'data': query},
          options: Options(receiveTimeout: const Duration(seconds: 20)),
        );
        final elements = resp.data['elements'] as List<dynamic>?;
        if (elements != null && elements.isNotEmpty) {
          final id = elements.first['id'].toString();
          return (id, id); // areaId = relationId pour Overpass (area id = rel id + 3600000000)
        }
      } catch (_) {}
    }
    return null;
  }

  /// Requête tous les quartiers qui sont géographiquement dans la relation [cityRelationId].
  ///
  /// Stratégie :
  ///   1. Limites administratives OSM (admin_level 10 → 9)
  ///   2. Si rien : polygones place=suburb / place=neighbourhood / place=quarter
  Future<List<Quarter>> _fetchQuartersInCity(String cityRelationId) async {
    // En Overpass, l'area d'une relation = relation_id + 3600000000
    final areaId = int.parse(cityRelationId) + 3600000000;

    // ── 1. Limites administratives (admin_level 10 → 9) ──────────────────────
    for (final level in ['10', '9']) {
      final query = '''
[out:json][timeout:30];
area($areaId)->.city;
relation["boundary"="administrative"]["admin_level"="$level"](area.city);
out geom;
''';
      try {
        final resp = await _dio.get(
          ApiConstants.overpassUrl,
          queryParameters: {'data': query},
          options: Options(receiveTimeout: const Duration(seconds: 35)),
        );
        final elements = resp.data['elements'] as List<dynamic>?;
        if (elements != null && elements.isNotEmpty) {
          return elements
              .map((e) => _parseRelation(e as Map<String, dynamic>))
              .whereType<Quarter>()
              .toList();
        }
      } catch (_) {}
    }

    // ── 2. Polygones place=suburb/neighbourhood/quarter (comme Nominatim) ────
    final placeQuery = '''
[out:json][timeout:30];
area($areaId)->.city;
(
  relation["place"~"^(suburb|neighbourhood|quarter)\$"](area.city);
  way["place"~"^(suburb|neighbourhood|quarter)\$"](area.city);
);
out geom;
''';
    try {
      final resp = await _dio.get(
        ApiConstants.overpassUrl,
        queryParameters: {'data': placeQuery},
        options: Options(receiveTimeout: const Duration(seconds: 35)),
      );
      final elements = resp.data['elements'] as List<dynamic>?;
      if (elements != null && elements.isNotEmpty) {
        return elements
            .map((e) => _parsePlaceElement(e as Map<String, dynamic>))
            .whereType<Quarter>()
            .toList();
      }
    } catch (_) {}

    return [];
  }

  /// Parse un élément place=suburb/neighbourhood (relation ou way).
  Quarter? _parsePlaceElement(Map<String, dynamic> element) {
    final type = element['type'] as String?;
    if (type == 'relation') return _parseRelation(element);
    if (type == 'way') {
      final id = element['id']?.toString();
      if (id == null) return null;
      final tags = element['tags'] as Map<String, dynamic>? ?? {};
      final name =
          (tags['name'] ?? tags['name:fr'] ?? tags['short_name'] ?? 'Quartier')
              as String;
      final geom = element['geometry'] as List<dynamic>?;
      if (geom == null || geom.isEmpty) return null;
      final polygon = geom
          .map((g) => LatLng(
                (g['lat'] as num).toDouble(),
                (g['lon'] as num).toDouble(),
              ))
          .toList();
      if (polygon.length < 3) return null;
      return Quarter(id: 'w$id', name: name, polygon: _simplify(polygon, 400));
    }
    return null;
  }

  /// Récupère le polygone d'une relation OSM par son ID (ville entière comme zone unique).
  Future<Quarter?> _fetchRelationAsQuarter(String relId) async {
    final query = '''
[out:json][timeout:20];
relation($relId);
out geom;
''';
    try {
      final resp = await _dio.get(
        ApiConstants.overpassUrl,
        queryParameters: {'data': query},
        options: Options(receiveTimeout: const Duration(seconds: 25)),
      );
      final elements = resp.data['elements'] as List<dynamic>?;
      debugPrint('[FogOfWar] _fetchRelationAsQuarter: ${elements?.length ?? 0} éléments');
      if (elements == null || elements.isEmpty) return null;
      final el = elements.first as Map<String, dynamic>;
      final members = el['members'] as List<dynamic>? ?? [];
      debugPrint('[FogOfWar] membres: ${members.length}, '
          'outer ways: ${members.where((m) => m['type'] == 'way' && (m['role'] == 'outer' || m['role'] == '')).length}');
      final result = _parseRelation(el);
      debugPrint('[FogOfWar] _parseRelation → ${result == null ? 'null' : '"${result.name}" ${result.polygon.length} pts'}');
      return result;
    } catch (e) {
      debugPrint('[FogOfWar] _fetchRelationAsQuarter erreur: $e');
      return null;
    }
  }

  Quarter? _parseRelation(Map<String, dynamic> element) {
    final id = element['id']?.toString();
    if (id == null) return null;
    final tags = element['tags'] as Map<String, dynamic>? ?? {};
    final name =
        (tags['name'] ?? tags['name:fr'] ?? tags['short_name'] ?? 'Quartier')
            as String;
    final members = element['members'] as List<dynamic>? ?? [];
    final outerWays = members
        .where((m) =>
            m['type'] == 'way' &&
            (m['role'] == 'outer' || m['role'] == '') &&
            m['geometry'] != null)
        .map((m) {
          final geom = m['geometry'] as List<dynamic>;
          return geom
              .map((g) => LatLng(
                    (g['lat'] as num).toDouble(),
                    (g['lon'] as num).toDouble(),
                  ))
              .toList();
        })
        .toList();
    if (outerWays.isEmpty) return null;
    final polygon = _stitchWays(outerWays);
    if (polygon.length < 3) return null;
    return Quarter(id: id, name: name, polygon: _simplify(polygon, 400));
  }

  List<LatLng> _stitchWays(List<List<LatLng>> ways) {
    if (ways.length == 1) return ways.first;
    final result = List<LatLng>.from(ways.first);
    final remaining = ways.sublist(1);
    while (remaining.isNotEmpty) {
      final last = result.last;
      int idx = -1;
      bool reversed = false;
      for (int i = 0; i < remaining.length; i++) {
        if (_close(remaining[i].first, last)) {
          idx = i;
          break;
        } else if (_close(remaining[i].last, last)) {
          idx = i;
          reversed = true;
          break;
        }
      }
      if (idx == -1) {
        for (final w in remaining) {
          result.addAll(w);
        }
        break;
      }
      final way = remaining.removeAt(idx);
      result.addAll(reversed ? way.reversed : way.skip(1));
    }
    return result;
  }

  bool _close(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-5 &&
      (a.longitude - b.longitude).abs() < 1e-5;

  List<LatLng> _simplify(List<LatLng> points, int maxPoints) {
    if (points.length <= maxPoints) return points;
    final stride = (points.length / maxPoints).ceil();
    final result = <LatLng>[];
    for (int i = 0; i < points.length; i += stride) {
      result.add(points[i]);
    }
    if (result.first != result.last) result.add(result.first);
    return result;
  }
}
