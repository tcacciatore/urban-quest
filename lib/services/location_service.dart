import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// Demande les permissions et retourne la position actuelle
  Future<LatLng> getCurrentPosition() async {
    await _ensurePermission();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  /// Stream de position mis à jour toutes les 5 secondes ou après 10m de déplacement
  Stream<LatLng> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // mètres
      ),
    ).map((pos) => LatLng(pos.latitude, pos.longitude));
  }

  /// Stream du cap de déplacement en degrés (0 = Nord, sens horaire)
  Stream<double> headingStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).map((pos) => pos.heading);
  }

  Future<void> _ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permission de localisation refusée définitivement.');
    }
  }
}
