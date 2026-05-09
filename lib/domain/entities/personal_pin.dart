import 'package:latlong2/latlong.dart';

class PersonalPin {
  final String id;
  final double latitude;
  final double longitude;
  final String emoji;
  final String label;
  final String? photoPath;
  final DateTime createdAt;
  final String? cityId; // ville où le pin a été posé

  const PersonalPin({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.emoji,
    required this.label,
    this.photoPath,
    required this.createdAt,
    this.cityId,
  });

  LatLng get position => LatLng(latitude, longitude);

  /// Retourne uniquement le nom de fichier (sans répertoire).
  /// C'est ce qui est stocké dans Hive — le chemin complet est reconstruit
  /// à l'exécution via [appDocsDirProvider] pour éviter les problèmes
  /// liés aux changements d'UUID sandbox iOS.
  static String? _toFilename(String? path) {
    if (path == null) return null;
    // Si c'est déjà un nom de fichier simple, on le renvoie tel quel
    if (!path.contains('/')) return path;
    return path.split('/').last;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': latitude,
        'lon': longitude,
        'emoji': emoji,
        'label': label,
        'photoPath': _toFilename(photoPath), // stocke uniquement le nom de fichier
        'createdAt': createdAt.toIso8601String(),
        'cityId': cityId,
      };

  factory PersonalPin.fromJson(Map<String, dynamic> json) => PersonalPin(
        id: json['id'] as String,
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
        emoji: json['emoji'] as String,
        label: json['label'] as String,
        photoPath: json['photoPath'] as String?, // nom de fichier ou null
        createdAt: DateTime.parse(json['createdAt'] as String),
        cityId: json['cityId'] as String?,
      );
}
