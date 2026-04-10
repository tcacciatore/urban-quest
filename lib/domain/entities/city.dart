import 'package:latlong2/latlong.dart';

class City {
  final String id;
  final String name;
  final List<LatLng> polygon;
  /// Points GPS parcourus dans cette ville (échantillonnés tous les ~30 m).
  final List<LatLng> walkedPoints;
  /// Fraction du territoire révélé (0.0 → 1.0), pré-calculée à chaque ajout.
  final double revealedRatio;

  /// Fraction requise pour déverrouiller la ville.
  static const double requiredRatio = 0.30;

  const City({
    required this.id,
    required this.name,
    required this.polygon,
    this.walkedPoints = const [],
    this.revealedRatio = 0.0,
  });

  bool get isUnlocked => revealedRatio >= requiredRatio;

  City copyWith({List<LatLng>? walkedPoints, double? revealedRatio}) => City(
        id: id,
        name: name,
        polygon: polygon,
        walkedPoints: walkedPoints ?? this.walkedPoints,
        revealedRatio: revealedRatio ?? this.revealedRatio,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'polygon': polygon.map((p) => [p.latitude, p.longitude]).toList(),
        'walkedPoints':
            walkedPoints.map((p) => [p.latitude, p.longitude]).toList(),
        'revealedRatio': revealedRatio,
      };

  factory City.fromJson(Map<String, dynamic> json) => City(
        id: json['id'] as String,
        name: json['name'] as String,
        polygon: (json['polygon'] as List)
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList(),
        walkedPoints: ((json['walkedPoints'] as List?) ?? [])
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList(),
        revealedRatio: (json['revealedRatio'] as num? ?? 0.0).toDouble(),
      );
}
