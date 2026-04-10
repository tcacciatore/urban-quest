import 'package:latlong2/latlong.dart';

class Quarter {
  final String id;
  final String name;
  final List<LatLng> polygon;
  final bool isRevealed;
  final int huntCount;
  /// Nombre de chasses nécessaires pour révéler cette zone.
  /// 1 pour les sous-quartiers OSM, 5 pour le fallback ville entière.
  final int requiredHunts;
  /// ID OSM de la ville parente (relation ID).
  final String? cityId;

  const Quarter({
    required this.id,
    required this.name,
    required this.polygon,
    this.isRevealed = false,
    this.huntCount = 0,
    this.requiredHunts = 1,
    this.cityId,
  });

  Quarter copyWith({
    bool? isRevealed,
    int? huntCount,
    int? requiredHunts,
    String? cityId,
  }) =>
      Quarter(
        id: id,
        name: name,
        polygon: polygon,
        isRevealed: isRevealed ?? this.isRevealed,
        huntCount: huntCount ?? this.huntCount,
        requiredHunts: requiredHunts ?? this.requiredHunts,
        cityId: cityId ?? this.cityId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'polygon': polygon.map((p) => [p.latitude, p.longitude]).toList(),
        'isRevealed': isRevealed,
        'huntCount': huntCount,
        'requiredHunts': requiredHunts,
        if (cityId != null) 'cityId': cityId,
      };

  factory Quarter.fromJson(Map<String, dynamic> json) => Quarter(
        id: json['id'] as String,
        name: json['name'] as String,
        polygon: (json['polygon'] as List)
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList(),
        isRevealed: json['isRevealed'] as bool? ?? false,
        huntCount: json['huntCount'] as int? ?? 0,
        requiredHunts: json['requiredHunts'] as int? ?? 1,
        cityId: json['cityId'] as String?,
      );
}
