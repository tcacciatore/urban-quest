import 'dart:convert';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/city.dart';
import '../datasources/remote/city_remote_datasource.dart';

class CityRepository {
  static const _boxName      = 'city_fog';
  static const _cPrefix      = 'c_';       // données d'une ville
  static const _loadedPrefix = 'loaded_';  // marqueur fetch-once
  static const _schemaKey    = '__schema_version__';
  static const _schemaVersion = 5; // +ratioRadiusMeters 25m (recalcul revealedRatio)

  final CityRemoteDatasource _remote;
  CityRepository(this._remote);

  static Future<void> initHive() async {
    final box = await Hive.openBox<String>(_boxName);
    // Migration : si version absente ou périmée → on vide le cache
    final stored = int.tryParse(box.get(_schemaKey) ?? '');
    if (stored != _schemaVersion) {
      await box.clear();
      await box.put(_schemaKey, '$_schemaVersion');
    }
  }

  Box<String> get _box => Hive.box<String>(_boxName);

  // ─── Lecture ──────────────────────────────────────────────────────────────

  List<City> loadAll() {
    return _box.keys
        .where((k) => (k as String).startsWith(_cPrefix))
        .map((k) => City.fromJson(
            jsonDecode(_box.get(k as String)!) as Map<String, dynamic>))
        .toList();
  }

  // ─── Fetch-once depuis Overpass ───────────────────────────────────────────

  /// Vrai si les voisines de cette ville ont déjà été chargées.
  bool isCityLoaded(String cityId) =>
      _box.containsKey('$_loadedPrefix$cityId');

  /// Charge la ville courante + voisines si pas encore en cache.
  /// Retourne les nouvelles villes ajoutées + l'ID de la ville courante.
  Future<({List<City> newCities, String? currentCityId})> ensureCitiesLoaded(
    LatLng position,
  ) async {
    final result = await _remote.fetchCityAndNeighbors(position);
    final currentCityId = result.currentCityId;
    if (currentCityId == null) return (newCities: <City>[], currentCityId: null);

    final loadedKey = '$_loadedPrefix$currentCityId';
    if (_box.containsKey(loadedKey)) {
      return (newCities: <City>[], currentCityId: currentCityId);
    }

    if (result.cities.isEmpty) return (newCities: <City>[], currentCityId: currentCityId);

    await _box.put(loadedKey, 'done');
    // Marque aussi chaque ville du groupe comme chargée (arrondissements) :
    // évite de re-fetcher quand l'utilisateur entre dans un autre arrondissement.
    for (final city in result.cities) {
      final cityLoadedKey = '$_loadedPrefix${city.id}';
      if (!_box.containsKey(cityLoadedKey)) {
        await _box.put(cityLoadedKey, 'done');
      }
    }
    final newOnes = <City>[];
    for (final city in result.cities) {
      final key = '$_cPrefix${city.id}';
      if (!_box.containsKey(key)) {
        await _box.put(key, jsonEncode(city.toJson()));
        newOnes.add(city);
      }
    }
    return (newCities: newOnes, currentCityId: currentCityId);
  }

  // ─── Écriture ─────────────────────────────────────────────────────────────

  Future<void> save(City city) async {
    await _box.put('$_cPrefix${city.id}', jsonEncode(city.toJson()));
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
