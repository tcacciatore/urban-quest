import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/api_constants.dart';
import '../../../domain/entities/city.dart';

class CityRemoteDatasource {
  final Dio _dio;
  CityRemoteDatasource(this._dio);

  /// Retourne la ville courante, ou ses arrondissements si elle en possède
  /// (Paris, Lyon, Marseille…).
  Future<({List<City> cities, String? currentCityId})> fetchCityAndNeighbors(
    LatLng position,
  ) async {
    // Nominatim avec polygon_geojson=1 : relation ID + polygone en un seul appel,
    // sans passer par Overpass.
    final city = await _fetchCityFromNominatim(position);
    if (city == null) {
      debugPrint('[CityFog] aucune commune trouvée à ${position.latitude},${position.longitude}');
      return (cities: <City>[], currentCityId: null);
    }
    debugPrint('[CityFog] commune: ${city.name} (${city.id})');

    // Seules Paris, Lyon et Marseille ont des arrondissements en France
    const citiesWithArrondissements = {'Paris', 'Lyon', 'Marseille'};
    if (!citiesWithArrondissements.contains(city.name)) {
      return (cities: [city], currentCityId: city.id);
    }

    // Tente de récupérer les arrondissements via Overpass
    final subdivisions = await _fetchSubdivisions(city.id);
    if (subdivisions.length >= 2) {
      final current = subdivisions.firstWhere(
        (c) => _pip(position, c.polygon),
        orElse: () => subdivisions.first,
      );
      debugPrint('[CityFog] ${subdivisions.length} arrondissements — courant: ${current.name}');
      return (cities: subdivisions, currentCityId: current.id);
    }

    // Ville normale (pas de subdivision)
    return (cities: [city], currentCityId: city.id);
  }

  // ─── Nominatim ────────────────────────────────────────────────────────────

  /// Récupère la commune et son polygone en un seul appel Nominatim.
  /// polygon_geojson=1 évite un second appel Overpass.
  Future<City?> _fetchCityFromNominatim(LatLng pos) async {
    try {
      final resp = await _dio.get(
        ApiConstants.nominatimUrl,
        queryParameters: {
          'lat': pos.latitude,
          'lon': pos.longitude,
          'format': 'json',
          'zoom': 10,
          'addressdetails': 0,
          'namedetails': 1,
          'polygon_geojson': 1,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          headers: {'User-Agent': 'UrbanQuest/1.0 (flutter app)'},
        ),
      );
      final data = resp.data as Map<String, dynamic>;
      final osmType = data['osm_type'] as String?;
      final osmId   = data['osm_id'];
      if (osmType != 'relation' || osmId == null) {
        debugPrint('[CityFog] Nominatim: osm_type=$osmType (attendu: relation)');
        return null;
      }

      final id = osmId.toString();

      final nameDetails = data['namedetails'] as Map<String, dynamic>?;
      final name = (nameDetails?['name'] as String?) ??
          (nameDetails?['name:fr'] as String?) ??
          ((data['display_name'] as String?)?.split(',').first.trim()) ??
          'Commune';

      final geojson = data['geojson'] as Map<String, dynamic>?;
      if (geojson == null) {
        debugPrint('[CityFog] Nominatim: pas de geojson pour $name');
        return null;
      }
      final polygon = _parseGeoJson(geojson);
      if (polygon.length < 3) {
        debugPrint('[CityFog] Nominatim: polygone insuffisant pour $name');
        return null;
      }

      debugPrint('[CityFog] Nominatim: $name — ${polygon.length} points');
      return City(id: id, name: name, polygon: _simplify(polygon, 400));
    } catch (e) {
      debugPrint('[CityFog] _fetchCityFromNominatim erreur: $e');
      return null;
    }
  }

  /// Parse un GeoJSON Polygon ou MultiPolygon → liste de LatLng.
  List<LatLng> _parseGeoJson(Map<String, dynamic> geojson) {
    final type   = geojson['type'] as String?;
    final coords = geojson['coordinates'];
    if (coords == null) return [];

    List<dynamic> ring;
    if (type == 'Polygon') {
      ring = (coords as List).first as List;
    } else if (type == 'MultiPolygon') {
      final polys = coords as List;
      // Prend la plus grande outer ring
      ring = polys
          .map((p) => (p as List).first as List)
          .reduce((a, b) => a.length >= b.length ? a : b);
    } else {
      return [];
    }

    return ring.map((p) {
      final pair = p as List;
      // GeoJSON: [longitude, latitude]
      return LatLng(
        (pair[1] as num).toDouble(),
        (pair[0] as num).toDouble(),
      );
    }).toList();
  }

  // ─── Overpass ─────────────────────────────────────────────────────────────

  /// Récupère les sous-divisions admin_level=9 (arrondissements) d'une commune.
  /// Retourne une liste vide si la commune n'en a pas ou si tous les mirrors échouent.
  Future<List<City>> _fetchSubdivisions(String communeRelId) async {
    final query =
        '[out:json][timeout:30];\n'
        'relation($communeRelId);\n'
        'rel(r)["admin_level"="9"]["name"];\n'
        'out geom;';
    final raw = await _overpassQuery(query, label: 'subdivisions($communeRelId)');
    if (raw == null) return [];
    final cities = raw
        .map((e) => _parseCity(e as Map<String, dynamic>))
        .whereType<City>()
        .toList();
    debugPrint('[CityFog] ${cities.length} arrondissements pour $communeRelId');
    return cities;
  }

  /// Lance la requête Overpass sur tous les mirrors jusqu'au premier succès.
  Future<List<dynamic>?> _overpassQuery(String query, {required String label}) async {
    for (int i = 0; i < ApiConstants.overpassMirrors.length; i++) {
      final mirror = ApiConstants.overpassMirrors[i];
      try {
        final resp = await _dio.get(
          mirror,
          queryParameters: {'data': query},
          options: Options(receiveTimeout: const Duration(seconds: 35)),
        );
        final elements = resp.data['elements'] as List<dynamic>?;
        debugPrint('[CityFog] $label → succès ($mirror)');
        return elements ?? [];
      } catch (e) {
        debugPrint('[CityFog] $label → échec $mirror (${_shortErr(e)})');
        if (i < ApiConstants.overpassMirrors.length - 1) {
          await Future.delayed(Duration(seconds: 3 * (i + 1)));
        }
      }
    }
    debugPrint('[CityFog] $label → tous les mirrors ont échoué');
    return null;
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

  // ─── Helpers ──────────────────────────────────────────────────────────────

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

  String _shortErr(Object e) {
    final s = e.toString();
    final idx = s.indexOf('status code of');
    return idx >= 0
        ? s.substring(idx, (idx + 20).clamp(0, s.length))
        : s.substring(0, s.length.clamp(0, 80));
  }

  /// Point-in-polygon (ray casting) pour identifier l'arrondissement courant.
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
