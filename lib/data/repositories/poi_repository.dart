import 'dart:convert';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../domain/entities/city_poi.dart';

class PoiRepository {
  static const _boxName = 'city_pois';
  static const _schemaKey = '__schema_version__';
  static const _schemaVersion = 1;

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

  bool hasPoisForCity(String cityId) => _box.containsKey(_cityKey(cityId));

  List<CityPoi> loadForCity(String cityId) {
    final raw = _box.get(_cityKey(cityId));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CityPoi.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePoisForCity(String cityId, List<CityPoi> pois) async {
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
}
