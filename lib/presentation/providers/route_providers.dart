import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'quest_providers.dart' show dioProvider;

class RouteState {
  final List<LatLng> polyline;
  final LatLng destination;
  final String destinationName;
  final String? photoPath;
  final String? emotionEmoji;

  const RouteState({
    required this.polyline,
    required this.destination,
    required this.destinationName,
    this.photoPath,
    this.emotionEmoji,
  });
}

class RouteNotifier extends Notifier<AsyncValue<RouteState?>> {
  @override
  AsyncValue<RouteState?> build() => const AsyncValue.data(null);

  Future<void> loadRoute({
    required LatLng from,
    required LatLng to,
    required String destinationName,
    String? photoPath,
    String? emotionEmoji,
  }) async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(dioProvider);
      // OSRM routing (libre, pas de clé API) — profil à pied
      final url =
          'https://router.project-osrm.org/route/v1/foot/${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
      final response = await dio.get(url, queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
      });

      final coords = response.data['routes'][0]['geometry']['coordinates'] as List;
      final polyline = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();

      state = AsyncValue.data(RouteState(
        polyline: polyline,
        destination: to,
        destinationName: destinationName,
        photoPath: photoPath,
        emotionEmoji: emotionEmoji,
      ));
    } catch (_) {
      // Fallback : ligne droite si OSRM échoue
      state = AsyncValue.data(RouteState(
        polyline: [from, to],
        destination: to,
        destinationName: destinationName,
        photoPath: photoPath,
        emotionEmoji: emotionEmoji,
      ));
    }
  }

  void setWalkedPath({
    required List<LatLng> path,
    required LatLng destination,
    required String destinationName,
    String? photoPath,
    String? emotionEmoji,
  }) {
    if (path.isEmpty) return;
    state = AsyncValue.data(RouteState(
      polyline: path,
      destination: destination,
      destinationName: destinationName,
      photoPath: photoPath,
      emotionEmoji: emotionEmoji,
    ));
  }

  void clear() => state = const AsyncValue.data(null);
}

final routeProvider =
    NotifierProvider<RouteNotifier, AsyncValue<RouteState?>>(RouteNotifier.new);
