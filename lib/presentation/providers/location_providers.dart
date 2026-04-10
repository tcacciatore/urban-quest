import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

/// Position actuelle en stream (mise à jour toutes les 10m)
final positionStreamProvider = StreamProvider<LatLng>((ref) {
  final service = ref.watch(locationServiceProvider);
  return service.positionStream();
});

/// Position initiale (future, pour le centrage de la carte)
final initialPositionProvider = FutureProvider<LatLng>((ref) {
  final service = ref.watch(locationServiceProvider);
  return service.getCurrentPosition();
});

/// Cap de déplacement en degrés (0 = Nord, sens horaire)
final headingStreamProvider = StreamProvider<double>((ref) {
  return ref.watch(locationServiceProvider).headingStream();
});
