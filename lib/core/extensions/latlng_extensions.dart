import 'dart:math';
import 'package:latlong2/latlong.dart';

extension LatLngExtensions on LatLng {
  /// Distance en mètres vers [other]
  double distanceTo(LatLng other) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, this, other);
  }

  /// Bearing en degrés (0 = Nord) vers [other]
  double bearingTo(LatLng other) {
    final lat1 = latitude * pi / 180;
    final lat2 = other.latitude * pi / 180;
    final dLon = (other.longitude - longitude) * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// Direction cardinale vers [other]
  String cardinalDirectionTo(LatLng other) {
    final bearing = bearingTo(other);
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return directions[((bearing + 22.5) / 45).floor() % 8];
  }
}
