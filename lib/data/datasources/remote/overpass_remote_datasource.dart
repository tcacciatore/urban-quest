import 'dart:math';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/api_constants.dart';
import '../../../domain/entities/place.dart';

class RandomPlaceDatasource {
  final Dio _dio;
  final Random _random = Random();

  RandomPlaceDatasource(this._dio);

  Future<Place> fetchRandomPlace(LatLng userPosition, int radiusMeters, {String? direction}) async {
    final rawTarget = _randomPointInRadius(userPosition, radiusMeters, direction);
    // Accroche le point à la route la plus proche pour garantir l'accessibilité
    final target = await _snapToRoad(rawTarget);

    // Nominatim + Overpass en parallèle
    final results = await Future.wait([
      _fetchAddress(target),
      _fetchNearbyPoi(target),
    ]);

    final address = results[0] as Map<String, dynamic>;
    final poi = results[1] as _PoiData?;

    final road = address['road'] as String?;
    final houseNumber = address['house_number'] as String?;
    final suburb = address['suburb'] as String? ??
        address['neighbourhood'] as String? ??
        address['quarter'] as String?;
    final city = address['city'] as String? ??
        address['town'] as String? ??
        address['village'] as String?;
    final postcode = address['postcode'] as String?;

    return Place(
      id: '${target.latitude}_${target.longitude}',
      name: _buildName(road, houseNumber),
      category: 'adresse',
      latitude: target.latitude,
      longitude: target.longitude,
      tags: {
        if (road != null) 'road': road,
        if (houseNumber != null) 'house_number': houseNumber,
        if (suburb != null) 'suburb': suburb,
        if (city != null) 'city': city,
        if (postcode != null) 'postcode': postcode,
        if (poi?.name != null) 'nearby_poi': poi!.name!,
        if (poi?.osmKey != null) 'nearby_poi_osm_key': poi!.osmKey!,
        if (poi?.osmValue != null) 'nearby_poi_osm_value': poi!.osmValue!,
      },
    );
  }

  Future<Map<String, dynamic>> _fetchAddress(LatLng target) async {
    try {
      final response = await _dio.get(
        ApiConstants.nominatimUrl,
        queryParameters: {
          'lat': target.latitude,
          'lon': target.longitude,
          'format': 'json',
          'addressdetails': 1,
        },
        options: Options(
          headers: {'User-Agent': 'UrbanQuestApp/1.0'},
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      return response.data['address'] as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {};
    }
  }

  static const _osmRelevantKeys = [
    'tourism', 'leisure', 'amenity', 'landuse', 'man_made',
    'historic', 'natural', 'shop', 'tunnel', 'bridge', 'power', 'covered',
  ];

  Future<_PoiData?> _fetchNearbyPoi(LatLng target) async {
    final lat = target.latitude;
    final lon = target.longitude;
    final query = '''
[out:json][timeout:10];
(
  node(around:300,$lat,$lon)[name][amenity];
  node(around:300,$lat,$lon)[name][shop];
  node(around:300,$lat,$lon)[name][tourism];
  node(around:300,$lat,$lon)[name][leisure];
  node(around:300,$lat,$lon)[name][historic];
);
out 5;
''';

    try {
      final response = await _dio.get(
        ApiConstants.overpassUrl,
        queryParameters: {'data': query},
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final elements = response.data['elements'] as List<dynamic>?;
      if (elements == null || elements.isEmpty) return null;
      final tags = elements.first['tags'] as Map<String, dynamic>?;
      if (tags == null) return null;

      final name = tags['name'] as String?;

      // Cherche le premier tag OSM pertinent pour la suggestion d'émotion
      String? osmKey;
      String? osmValue;
      for (final key in _osmRelevantKeys) {
        if (tags.containsKey(key)) {
          osmKey = key;
          osmValue = tags[key] as String?;
          break;
        }
      }

      return _PoiData(name: name, osmKey: osmKey, osmValue: osmValue);
    } catch (_) {
      return null;
    }
  }

  /// Accroche un point GPS à la route piétonne la plus proche via OSRM.
  /// Retourne le point original en cas d'échec.
  Future<LatLng> _snapToRoad(LatLng point) async {
    try {
      final url =
          'https://router.project-osrm.org/nearest/v1/foot/${point.longitude},${point.latitude}';
      final response = await _dio.get(
        url,
        queryParameters: {'number': 1},
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final waypoints = response.data['waypoints'] as List<dynamic>?;
      if (waypoints == null || waypoints.isEmpty) return point;
      final location = waypoints.first['location'] as List<dynamic>;
      return LatLng(
        (location[1] as num).toDouble(),
        (location[0] as num).toDouble(),
      );
    } catch (_) {
      return point;
    }
  }

  // Angle de base (en radians) pour chaque direction cardinale.
  // Convention : angle 0 = Nord, sens horaire → cos(angle)=deltaLat, sin(angle)=deltaLon.
  static const _directionAngles = {
    'N':  0.0,
    'NE': pi / 4,
    'E':  pi / 2,
    'SE': 3 * pi / 4,
    'S':  pi,
    'SO': 5 * pi / 4,
    'O':  3 * pi / 2,
    'NO': 7 * pi / 4,
  };

  LatLng _randomPointInRadius(LatLng center, int radiusMeters, String? direction) {
    final minRadius = radiusMeters * 0.3;
    final r = minRadius + _random.nextDouble() * (radiusMeters - minRadius);

    double angle;
    if (direction != null && _directionAngles.containsKey(direction)) {
      // Secteur de ±45° autour de la direction choisie
      final centerAngle = _directionAngles[direction]!;
      angle = centerAngle - pi / 4 + _random.nextDouble() * (pi / 2);
    } else {
      angle = _random.nextDouble() * 2 * pi;
    }

    final deltaLat = (r * cos(angle)) / 111320;
    final deltaLon =
        (r * sin(angle)) / (111320 * cos(center.latitude * pi / 180));
    return LatLng(center.latitude + deltaLat, center.longitude + deltaLon);
  }

  String _buildName(String? road, String? houseNumber) {
    if (road != null && houseNumber != null) return '$houseNumber $road';
    if (road != null) return road;
    return 'Lieu mystère';
  }
}

class _PoiData {
  final String? name;
  final String? osmKey;
  final String? osmValue;
  const _PoiData({this.name, this.osmKey, this.osmValue});
}
