import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

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

  /// Stream du cap magnétomètre lissé en degrés (0 = Nord, sens horaire).
  Stream<double> headingStream() {
    double filtered = 0;
    bool first = true;
    return magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).map((event) {
      final raw = (atan2(-event.y, event.x) * 180 / pi + 360) % 360;
      if (first) { filtered = raw; first = false; return raw; }
      // Filtre passe-bas : lisse le bruit du capteur
      var diff = raw - filtered;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      filtered = (filtered + diff * 0.2 + 360) % 360;
      return filtered;
    });
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
