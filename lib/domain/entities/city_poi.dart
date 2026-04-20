import 'package:latlong2/latlong.dart';

class CityPoi {
  final String id;
  final String cityId;
  final String name;
  final String emoji;
  final LatLng position;
  final bool isDiscovered;
  /// Extrait de description (Mérimée ou Wikipedia). Null si non disponible.
  final String? description;
  /// Date de la première visite. Null si jamais découvert.
  final DateTime? firstVisitDate;
  /// Nombre de fois visité (au moins 1 dès la première découverte).
  final int visitCount;

  const CityPoi({
    required this.id,
    required this.cityId,
    required this.name,
    required this.emoji,
    required this.position,
    this.isDiscovered = false,
    this.description,
    this.firstVisitDate,
    this.visitCount = 0,
  });

  CityPoi copyWith({
    bool? isDiscovered,
    String? description,
    DateTime? firstVisitDate,
    int? visitCount,
  }) =>
      CityPoi(
        id: id,
        cityId: cityId,
        name: name,
        emoji: emoji,
        position: position,
        isDiscovered: isDiscovered ?? this.isDiscovered,
        description: description ?? this.description,
        firstVisitDate: firstVisitDate ?? this.firstVisitDate,
        visitCount: visitCount ?? this.visitCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cityId': cityId,
        'name': name,
        'emoji': emoji,
        'lat': position.latitude,
        'lon': position.longitude,
        'isDiscovered': isDiscovered,
        'description': description,
        'firstVisitDate': firstVisitDate?.toIso8601String(),
        'visitCount': visitCount,
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
        description: json['description'] as String?,
        firstVisitDate: json['firstVisitDate'] != null
            ? DateTime.tryParse(json['firstVisitDate'] as String)
            : null,
        visitCount: json['visitCount'] as int? ?? 0,
      );
}
