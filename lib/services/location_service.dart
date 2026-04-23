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
  /// via accéléromètre + magnétomètre avec compensation d'inclinaison et lissage.
  Stream<double> headingStream() {
    late StreamController<double> controller;
    StreamSubscription<AccelerometerEvent>? accelSub;
    StreamSubscription<MagnetometerEvent>? magSub;

    // Valeurs filtrées (passe-bas)
    double ax = 0, ay = 0, az = 9.8;
    double mx = 0, my = 0, mz = 0;
    double _smoothedHeading = 0;
    bool _hasMag = false;

    // Constantes de lissage
    const accelAlpha = 0.08; // filtre lent pour estimer la gravité
    const magAlpha   = 0.35; // filtre intermédiaire pour le magnétomètre
    const headAlpha  = 0.12; // lissage final du cap (plus petit = plus doux)

    void emitHeading() {
      if (!_hasMag) return;

      final norm = math.sqrt(ax * ax + ay * ay + az * az);
      if (norm < 0.01) return;

      // Angles d'inclinaison depuis le vecteur gravité normalisé
      final gx = ax / norm;
      final gy = ay / norm;
      final gz = az / norm;

      final pitch = math.asin((-gx).clamp(-1.0, 1.0));
      final roll  = math.atan2(gy, gz);

      final cosP = math.cos(pitch);
      final sinP = math.sin(pitch);
      final cosR = math.cos(roll);
      final sinR = math.sin(roll);

      // Composantes horizontales compensées en inclinaison
      final xh = mx * cosP + mz * sinP;
      final yh = mx * sinR * sinP + my * cosR - mz * sinR * cosP;

      // atan2(-yh, xh) : formule standard cap boussole (Nord=0, sens horaire)
      var raw = math.atan2(-yh, xh) * 180 / math.pi;
      if (raw < 0) raw += 360;

      // Lissage circulaire : interpole sur le chemin angulaire le plus court
      var diff = raw - _smoothedHeading;
      if (diff >  180) diff -= 360;
      if (diff < -180) diff += 360;
      _smoothedHeading = (_smoothedHeading + headAlpha * diff + 360) % 360;

      if (!controller.isClosed) controller.add(_smoothedHeading);
    }

    controller = StreamController<double>(
      onListen: () {
        accelSub = accelerometerEventStream(
          samplingPeriod: SensorInterval.normalInterval,
        ).listen((e) {
          ax = accelAlpha * e.x + (1 - accelAlpha) * ax;
          ay = accelAlpha * e.y + (1 - accelAlpha) * ay;
          az = accelAlpha * e.z + (1 - accelAlpha) * az;
        });
        magSub = magnetometerEventStream(
          samplingPeriod: SensorInterval.normalInterval,
        ).listen((e) {
          mx = magAlpha * e.x + (1 - magAlpha) * mx;
          my = magAlpha * e.y + (1 - magAlpha) * my;
          mz = magAlpha * e.z + (1 - magAlpha) * mz;
          _hasMag = true;
          emitHeading();
        });
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
