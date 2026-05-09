import 'dart:convert';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../domain/entities/personal_pin.dart';

class PersonalPinRepository {
  static const _boxName = 'personal_pins';
  static const _key = 'pins';

  static Future<void> initHive() async {
    await Hive.openBox<String>(_boxName);
  }

  Box<String> get _box => Hive.box<String>(_boxName);

  List<PersonalPin> loadAll() {
    final raw = _box.get(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PersonalPin.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAll(List<PersonalPin> pins) async {
    final json = jsonEncode(pins.map((p) => p.toJson()).toList());
    await _box.put(_key, json);
  }
}
