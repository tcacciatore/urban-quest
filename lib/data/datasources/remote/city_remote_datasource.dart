import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/api_constants.dart';
import '../../../domain/entities/city.dart';

class CityRemoteDatasource {
  final Dio _dio;
  CityRemoteDatasource(this._dio);

  /// Retourne la ville courante + ses voisines directes (communes partageant une frontière).
  Future<({List<City> cities, String? currentCityId})> fetchCityAndNeighbors(
    LatLng position,
  ) async {
    final currentRelId = await _fetchCityRelId(position);
    if (currentRelId == null) {
      debugPrint('[CityFog] aucune commune trouvée à ${position.latitude},${position.longitude}');
      return (cities: <City>[], currentCityId: null);
    }
    debugPrint('[CityFog] commune courante: $currentRelId');
    final cities = await _fetchCityWithNeighbors(currentRelId);
    return (cities: cities, currentCityId: currentRelId);
  }

  // ─── Privé ────────────────────────────────────────────────────────────────

  /// Utilise Nominatim reverse geocoding (zoom=10 = niveau commune).
  /// Beaucoup plus rapide et fiable que `is_in` Overpass.
  Future<String?> _fetchCityRelId(LatLng pos) async {
    try {
      final resp = await _dio.get(
        ApiConstants.nominatimUrl,
        queryParameters: {
          'lat': pos.latitude,
          'lon': pos.longitude,
          'format': 'json',
          'zoom': 10,
          'addressdetails': 0,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          headers: {'User-Agent': 'UrbanQuest/1.0 (flutter app)'},
        ),
      );
      final data = resp.data as Map<String, dynamic>;
      final osmType = data['osm_type'] as String?;
      final osmId   = data['osm_id'];
      if (osmType == 'relation' && osmId != null) {
        return osmId.toString();
      }
      debugPrint('[CityFog] Nominatim: osm_type=$osmType (attendu: relation)');
      return null;
    } catch (e) {
      debugPrint('[CityFog] _fetchCityRelId erreur: $e');
      return null;
    }
  }

  /// Commune courante + voisines via bounding box (2 requêtes légères).
  Future<List<City>> _fetchCityWithNeighbors(String cityRelId) async {
    // Étape 1 : géométrie de la ville courante seule
    final currentCity = await _fetchSingleCity(cityRelId);
    if (currentCity == null) return [];

    // Étape 2 : voisines dans la bbox de la ville courante
    final bbox = _bbox(currentCity.polygon);
    final neighbors = await _fetchCitiesInBbox(bbox, excludeId: cityRelId);

    return [currentCity, ...neighbors];
  }

  Future<City?> _fetchSingleCity(String relId) async {
    final query = '[out:json][timeout:30];\nrel($relId);\nout geom;';
    try {
      final resp = await _dio.get(
        ApiConstants.overpassUrl,
        queryParameters: {'data': query},
        options: Options(receiveTimeout: const Duration(seconds: 35)),
      );
      final elements = resp.data['elements'] as List<dynamic>?;
      if (elements == null || elements.isEmpty) return null;
      return _parseCity(elements.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[CityFog] erreur _fetchSingleCity($relId): $e');
      return null;
    }
  }

  Future<List<City>> _fetchCitiesInBbox(
    ({double s, double w, double n, double e}) bbox, {
    required String excludeId,
  }) async {
    final query = '''
[out:json][timeout:30];
rel["boundary"="administrative"]["admin_level"="8"](${bbox.s},${bbox.w},${bbox.n},${bbox.e});
out geom;
''';
    try {
      final resp = await _dio.get(
        ApiConstants.overpassUrl,
        queryParameters: {'data': query},
        options: Options(receiveTimeout: const Duration(seconds: 35)),
      );
      final elements = resp.data['elements'] as List<dynamic>?;
      if (elements == null || elements.isEmpty) return [];
      final cities = elements
          .map((e) => _parseCity(e as Map<String, dynamic>))
          .whereType<City>()
          .where((c) => c.id != excludeId)
          .toList();
      debugPrint('[CityFog] ${cities.length} voisines trouvées dans la bbox');
      return cities;
    } catch (e) {
      debugPrint('[CityFog] erreur _fetchCitiesInBbox: $e');
      return [];
    }
  }

  ({double s, double w, double n, double e}) _bbox(List<LatLng> polygon) {
    var s = polygon.first.latitude;
    var n = polygon.first.latitude;
    var w = polygon.first.longitude;
    var e = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude  < s) s = p.latitude;
      if (p.latitude  > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    return (s: s, w: w, n: n, e: e);
  }

  City? _parseCity(Map<String, dynamic> element) {
    final id = element['id']?.toString();
    if (id == null) return null;
    final tags = element['tags'] as Map<String, dynamic>? ?? {};
    final name =
        (tags['name'] ?? tags['name:fr'] ?? tags['short_name'] ?? 'Commune')
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
    return City(id: id, name: name, polygon: _simplify(polygon, 400));
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
        for (final w in remaining) { result.addAll(w); }
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
