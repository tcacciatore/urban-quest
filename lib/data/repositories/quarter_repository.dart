import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/quarter.dart';
import '../datasources/remote/quarter_remote_datasource.dart';

class QuarterRepository {
  static const _boxName = 'quarter_polygons';
  static const _qPrefix = 'q_';     // polygone d'un quartier
  static const _cityKey = 'city_';  // marqueur "ville déjà téléchargée"

  final QuarterRemoteDatasource _remote;

  QuarterRepository(this._remote);

  static Future<void> initHive() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_boxName);
  }

  Box<String> get _box => Hive.box<String>(_boxName);

  // ─── Lecture ───────────────────────────────────────────────────────────────

  List<Quarter> loadAll() {
    return _box.keys
        .where((k) => (k as String).startsWith(_qPrefix))
        .map((k) => Quarter.fromJson(
            jsonDecode(_box.get(k as String)!) as Map<String, dynamic>))
        .toList();
  }

  // ─── Chargement ville entière (fetch-once par ville) ─────────────────────

  /// Télécharge tous les quartiers de la ville contenant [position].
  /// Ne refait l'appel Overpass que si la ville n'est pas encore en cache.
  /// Retourne uniquement les quartiers nouvellement ajoutés.
  Future<({List<Quarter> newQuarters, String? cityId})> ensureCityLoaded(LatLng position) async {
    final result = await _remote.fetchCityQuarters(position);
    debugPrint('[FogOfWar] cityId=${result.cityId}, quarters=${result.quarters.length}');
    final cityId = result.cityId ?? _fallbackCityKey(position);
    final cacheKey = '$_cityKey$cityId';

    // Ville déjà téléchargée → retourne juste le cityId
    if (_box.containsKey(cacheKey)) {
      debugPrint('[FogOfWar] ville déjà en cache ($cacheKey)');
      return (newQuarters: <Quarter>[], cityId: cityId);
    }

    // Ne marquer "done" que si Overpass a renvoyé des données
    if (result.quarters.isEmpty) {
      debugPrint('[FogOfWar] Overpass a renvoyé 0 quartiers pour cityId=$cityId');
      return (newQuarters: <Quarter>[], cityId: cityId);
    }
    await _box.put(cacheKey, 'done');

    final newOnes = <Quarter>[];
    for (final q in result.quarters) {
      final key = '$_qPrefix${q.id}';
      if (!_box.containsKey(key)) {
        await _box.put(key, jsonEncode(q.toJson()));
        newOnes.add(q);
      }
    }
    return (newQuarters: newOnes, cityId: cityId);
  }

  // ─── Résolution ponctuelle (fin de chasse) ────────────────────────────────

  Future<Quarter?> getQuarterForPoint(LatLng point) async {
    for (final k in _box.keys) {
      if (!(k as String).startsWith(_qPrefix)) continue;
      final q = Quarter.fromJson(
          jsonDecode(_box.get(k)!) as Map<String, dynamic>);
      if (_pip(point, q.polygon)) return q;
    }
    final fetched = await _remote.fetchQuarterForPoint(point);
    if (fetched != null) await save(fetched);
    return fetched;
  }

  // ─── Écriture ──────────────────────────────────────────────────────────────

  Future<void> save(Quarter quarter) async {
    await _box.put('$_qPrefix${quarter.id}', jsonEncode(quarter.toJson()));
  }

  Future<void> clearAll() async {
    await _box.clear();
  }

  // ─── Clé de fallback (pas de ville OSM trouvée) ────────────────────────────

  /// Grille 0,1° (~10 km) quand aucune relation OSM de ville n'est trouvée.
  String _fallbackCityKey(LatLng pos) {
    final lat = (pos.latitude * 10).round();
    final lon = (pos.longitude * 10).round();
    return 'fb_${lat}_$lon';
  }

  // ─── Point-in-polygon ─────────────────────────────────────────────────────

  bool _pip(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    int crossings = 0;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }
}
