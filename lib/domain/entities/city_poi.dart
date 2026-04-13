import 'package:latlong2/latlong.dart';

class CityPoi {
  final String id;
  final String cityId;
  final String name;
  final String emoji;
  final LatLng position;
  final bool isDiscovered;

  const CityPoi({
    required this.id,
    required this.cityId,
    required this.name,
    required this.emoji,
    required this.position,
    this.isDiscovered = false,
  });

  CityPoi copyWith({bool? isDiscovered}) => CityPoi(
        id: id,
        cityId: cityId,
        name: name,
        emoji: emoji,
        position: position,
        isDiscovered: isDiscovered ?? this.isDiscovered,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cityId': cityId,
        'name': name,
        'emoji': emoji,
        'lat': position.latitude,
        'lon': position.longitude,
        'isDiscovered': isDiscovered,
      };

  factory CityPoi.fromJson(Map<String, dynamic> json) => CityPoi(
        id: json['id'] as String,
        cityId: json['cityId'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lon'] as num).toDouble(),
        ),
        isDiscovered: json['isDiscovered'] as bool? ?? false,
      );
}
