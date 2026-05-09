import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuestHistoryEntry {
  final String placeName;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int radiusMeters;
  final bool wasCompleted;
  final double? latitude;
  final double? longitude;
  final String? emotionEmoji;
  final String? emotionLabel;
  final String? photoPath;
  final double? startLatitude;
  final double? startLongitude;
  // Chemin réellement parcouru (persisté pour le retracé)
  final List<LatLng>? walkedPath;

  const QuestHistoryEntry({
    required this.placeName,
    required this.startedAt,
    this.completedAt,
    required this.radiusMeters,
    required this.wasCompleted,
    this.latitude,
    this.longitude,
    this.emotionEmoji,
    this.emotionLabel,
    this.photoPath,
    this.startLatitude,
    this.startLongitude,
    this.walkedPath,
  });

  Duration? get duration => completedAt?.difference(startedAt);

  bool get hasCoordinates => latitude != null && longitude != null;
  bool get hasStartCoordinates => startLatitude != null && startLongitude != null;
  bool get hasWalkedPath => walkedPath != null && walkedPath!.length >= 2;

  /// Extrait le nom de fichier simple depuis un chemin absolu éventuel.
  /// Robuste aux anciens enregistrements qui stockaient le chemin complet.
  static String? _toBasename(String? path) {
    if (path == null) return null;
    if (!path.contains('/')) return path;
    return path.split('/').last;
  }

  Map<String, dynamic> toJson() => {
        'placeName': placeName,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'radiusMeters': radiusMeters,
        'wasCompleted': wasCompleted,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (emotionEmoji != null) 'emotionEmoji': emotionEmoji,
        if (emotionLabel != null) 'emotionLabel': emotionLabel,
        if (photoPath != null) 'photoPath': _toBasename(photoPath),
        if (startLatitude != null) 'startLatitude': startLatitude,
        if (startLongitude != null) 'startLongitude': startLongitude,
        if (walkedPath != null)
          'walkedPath': walkedPath!
              .map((p) => [p.latitude, p.longitude])
              .toList(),
      };

  factory QuestHistoryEntry.fromJson(Map<String, dynamic> map) {
    List<LatLng>? walkedPath;
    final rawPath = map['walkedPath'] as List<dynamic>?;
    if (rawPath != null) {
      walkedPath = rawPath
          .map((p) => LatLng(
                (p[0] as num).toDouble(),
                (p[1] as num).toDouble(),
              ))
          .toList();
    }

    return QuestHistoryEntry(
      placeName: map['placeName'] as String,
      startedAt: DateTime.parse(map['startedAt'] as String),
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      radiusMeters: map['radiusMeters'] as int,
      wasCompleted: map['wasCompleted'] as bool,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      emotionEmoji: map['emotionEmoji'] as String?,
      emotionLabel: map['emotionLabel'] as String?,
      photoPath: map['photoPath'] as String?,
      startLatitude: (map['startLatitude'] as num?)?.toDouble(),
      startLongitude: (map['startLongitude'] as num?)?.toDouble(),
      walkedPath: walkedPath,
    );
  }
}

class QuestHistoryNotifier extends AsyncNotifier<List<QuestHistoryEntry>> {
  static const _key = 'quest_history';
  static const _maxEntries = 20;

  @override
  Future<List<QuestHistoryEntry>> build() => _load();

  Future<List<QuestHistoryEntry>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) => QuestHistoryEntry.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    state = const AsyncData([]);
  }

  Future<void> add(QuestHistoryEntry entry) async {
    final current = await _load();
    final updated = [entry, ...current].take(_maxEntries).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
    state = AsyncData(updated);
  }
}

final questHistoryProvider =
    AsyncNotifierProvider<QuestHistoryNotifier, List<QuestHistoryEntry>>(
        QuestHistoryNotifier.new);
