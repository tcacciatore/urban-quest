import 'dart:async';
import 'dart:math' as math;
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

  /// Cap en degrés (0 = Nord, sens horaire), calculé en temps réel
  /// via accéléromètre + magnétomètre avec compensation d'inclinaison.
  Stream<double> headingStream() {
    late StreamController<double> controller;
    double ax = 0, ay = 0, az = 9.8;
    StreamSubscription<AccelerometerEvent>? accelSub;
    StreamSubscription<MagnetometerEvent>? magSub;

    void onMag(MagnetometerEvent mag) {
      final norm = math.sqrt(ax * ax + ay * ay + az * az);
      if (norm < 0.01) return;
      final gx = ax / norm, gy = ay / norm;

      // Compensation d'inclinaison (pitch + roll)
      final pitch = math.asin(gx.clamp(-1.0, 1.0));
      final cosP = math.cos(pitch);
      final roll = cosP.abs() < 0.01
          ? 0.0
          : math.asin((-gy / cosP).clamp(-1.0, 1.0));

      final xh = mag.x * math.cos(pitch) + mag.z * math.sin(pitch);
      final yh = mag.x * math.sin(roll) * math.sin(pitch) +
          mag.y * math.cos(roll) -
          mag.z * math.sin(roll) * math.cos(pitch);

      var heading = math.atan2(xh, yh) * 180 / math.pi;
      if (heading < 0) heading += 360;

      if (!controller.isClosed) controller.add(heading);
    }

    controller = StreamController<double>(
      onListen: () {
        accelSub = accelerometerEventStream(
          samplingPeriod: SensorInterval.normalInterval,
        ).listen((e) {
          ax = e.x;
          ay = e.y;
          az = e.z;
        });
        magSub = magnetometerEventStream(
          samplingPeriod: SensorInterval.normalInterval,
        ).listen(onMag);
      },
      onCancel: () {
        accelSub?.cancel();
        magSub?.cancel();
        controller.close();
      },
    );

    return controller.stream;
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
