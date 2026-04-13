import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/remote/poi_remote_datasource.dart';
import '../../data/repositories/poi_repository.dart';
import '../../domain/entities/city_poi.dart';
import 'city_fog_provider.dart';
import 'location_providers.dart';
import 'quest_providers.dart';

// ─── Infrastructure ───────────────────────────────────────────────────────────

final poiRemoteDatasourceProvider = Provider<PoiRemoteDatasource>(
  (ref) => PoiRemoteDatasource(ref.read(dioProvider)),
);

final poiRepositoryProvider = Provider<PoiRepository>(
  (ref) => PoiRepository(),
);

// ─── State ────────────────────────────────────────────────────────────────────

class PoiState {
  final Map<String, List<CityPoi>> poisByCity;

  const PoiState({this.poisByCity = const {}});

  List<CityPoi> forCity(String cityId) => poisByCity[cityId] ?? [];

  List<CityPoi> get allPois =>
      poisByCity.values.expand((list) => list).toList();

  PoiState copyWith({Map<String, List<CityPoi>>? poisByCity}) =>
      PoiState(poisByCity: poisByCity ?? this.poisByCity);
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class PoiNotifier extends Notifier<PoiState> {
  static const _discoveryRadiusMeters = 30.0;
  static const _poiRevealRadiusMeters = 300.0;

  final Set<String> _fetching = {};

  @override
  PoiState build() {
    // Charge les POIs déjà en cache Hive pour toutes les villes connues
    final repo = ref.read(poiRepositoryProvider);
    final cityFog = ref.read(cityFogProvider);
    final initial = <String, List<CityPoi>>{};
    for (final cityId in cityFog.cities.keys) {
      if (repo.hasPoisForCity(cityId)) {
        initial[cityId] = repo.loadForCity(cityId);
      }
    }

    // Écoute les nouvelles villes pour charger leurs POIs
    ref.listen<CityFogState>(cityFogProvider, (_, next) {
      for (final city in next.cities.values) {
        if (!state.poisByCity.containsKey(city.id)) {
          _ensurePoisLoaded(city.id);
        }
      }
    });

    // Détecte les découvertes lors des mises à jour de position
    ref.listen<AsyncValue<LatLng>>(positionStreamProvider, (_, next) {
      next.whenData(_checkDiscovery);
    });

    return PoiState(poisByCity: initial);
  }

  PoiRepository get _repo => ref.read(poiRepositoryProvider);
  PoiRemoteDatasource get _remote => ref.read(poiRemoteDatasourceProvider);

  Future<void> _ensurePoisLoaded(String cityId) async {
    if (state.poisByCity.containsKey(cityId)) return;
    if (_fetching.contains(cityId)) return;
    _fetching.add(cityId);

    try {
      final repo = _repo;
      if (repo.hasPoisForCity(cityId)) {
        final pois = repo.loadForCity(cityId);
        state = state.copyWith(
          poisByCity: Map.from(state.poisByCity)..[cityId] = pois,
        );
        return;
      }

      final city = ref.read(cityFogProvider).cities[cityId];
      if (city == null) return;

      debugPrint('[POI] fetch Overpass pour ${city.name}...');
      final pois = await _remote.fetchPoisForCity(city);
      await repo.savePoisForCity(cityId, pois);

      state = state.copyWith(
        poisByCity: Map.from(state.poisByCity)..[cityId] = pois,
      );
      debugPrint('[POI] ${pois.length} POIs sauvegardés pour ${city.name}');
    } finally {
      _fetching.remove(cityId);
    }
  }

  void _checkDiscovery(LatLng position) {
    final currentCityId = ref.read(cityFogProvider).currentCityId;
    if (currentCityId == null) return;

    final pois = state.poisByCity[currentCityId] ?? [];
    for (final poi in pois) {
      if (poi.isDiscovered) continue;
      if (_distMeters(position, poi.position) <= _discoveryRadiusMeters) {
        _discoverPoi(poi);
      }
    }
  }

  Future<void> _discoverPoi(CityPoi poi) async {
    debugPrint('[POI] 🎉 découverte : ${poi.emoji} ${poi.name}');

    // Mise à jour de l'état local
    final cityPois = List<CityPoi>.from(state.poisByCity[poi.cityId] ?? []);
    final idx = cityPois.indexWhere((p) => p.id == poi.id);
    if (idx == -1) return;
    cityPois[idx] = poi.copyWith(isDiscovered: true);

    state = state.copyWith(
      poisByCity: Map.from(state.poisByCity)..[poi.cityId] = cityPois,
    );

    // Persiste
    await _repo.markDiscovered(poi);

    // Retour haptique
    HapticFeedback.heavyImpact();

    // Révèle une grande zone de brouillard autour du POI
    ref
        .read(cityFogProvider.notifier)
        .revealAroundPoint(poi.cityId, poi.position, _poiRevealRadiusMeters);
  }

  double _distMeters(LatLng a, LatLng b) {
    const k = 111320.0;
    final cosLat = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final dx = (b.longitude - a.longitude) * cosLat * k;
    final dy = (b.latitude - a.latitude) * k;
    return math.sqrt(dx * dx + dy * dy);
  }
}

final poiProvider = NotifierProvider<PoiNotifier, PoiState>(PoiNotifier.new);
