import 'dart:convert';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../domain/entities/city_poi.dart';

class PoiRepository {
  static const _boxName = 'city_pois';
  static const _schemaKey = '__schema_version__';
  static const _schemaVersion = 14; // dédup Mérimée/OSM 30m, minDist 80m

  static Future<void> initHive() async {
    final box = await Hive.openBox<String>(_boxName);
    final stored = int.tryParse(box.get(_schemaKey) ?? '');
    if (stored != _schemaVersion) {
      await box.clear();
      await box.put(_schemaKey, '$_schemaVersion');
    }
  }

  Box<String> get _box => Hive.box<String>(_boxName);

  String _cityKey(String cityId) => 'pois_$cityId';

  /// Retourne true uniquement si la liste stockée est non vide.
  bool hasPoisForCity(String cityId) {
    if (!_box.containsKey(_cityKey(cityId))) return false;
    final pois = loadForCity(cityId);
    return pois.isNotEmpty;
  }

  List<CityPoi> loadForCity(String cityId) {
    final raw = _box.get(_cityKey(cityId));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CityPoi.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Ne sauvegarde que si la liste est non vide (évite de cacher un échec réseau).
  Future<void> savePoisForCity(String cityId, List<CityPoi> pois) async {
    if (pois.isEmpty) return;
    await _box.put(
      _cityKey(cityId),
      jsonEncode(pois.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> markDiscovered(CityPoi poi) async {
    final pois = loadForCity(poi.cityId);
    final updated = pois
        .map((p) => p.id == poi.id ? p.copyWith(isDiscovered: true) : p)
        .toList();
    await savePoisForCity(poi.cityId, updated);
  }

  /// Réinitialise les découvertes sur tous les POIs (isDiscovered, firstVisitDate, visitCount)
  /// sans supprimer la liste des lieux (évite un re-fetch réseau).
  Future<void> clearDiscoveries() async {
    for (final key in _box.keys.toList()) {
      if (key == _schemaKey) continue;
      final cityId = (key as String).replaceFirst('pois_', '');
      final pois = loadForCity(cityId);
      if (pois.isEmpty) continue;
      final cleared = pois
          .map((p) => CityPoi(
                id: p.id,
                cityId: p.cityId,
                name: p.name,
                emoji: p.emoji,
                position: p.position,
                description: p.description,
                isDiscovered: false,
                firstVisitDate: null,
                visitCount: 0,
              ))
          .toList();
      await _box.put(key, jsonEncode(cleared.map((p) => p.toJson()).toList()));
    }
  }
}
