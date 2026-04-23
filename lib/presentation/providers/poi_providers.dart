import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/remote/poi_remote_datasource.dart';
import '../../data/repositories/poi_repository.dart';
import '../../domain/entities/city.dart';
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
  static const _discoveryRadiusMeters = 50.0;
  static const _poiRevealRadiusMeters = 150.0;

  final Set<String> _fetching = {};
  final List<String> _queue = [];
  bool _queueRunning = false;
  final Set<String> _revisitedThisSession = {};
  LatLng? _lastKnownPosition;

  @override
  PoiState build() {
    final repo = ref.read(poiRepositoryProvider);
    final cityFog = ref.read(cityFogProvider);
    final initial = <String, List<CityPoi>>{};

    // Charge le cache et planifie les fetches UNIQUEMENT pour les villes visitées
    // ou la ville courante (évite de fetcher tous les arrondissements voisins).
    for (final city in cityFog.cities.values) {
      if (!_shouldFetch(city, cityFog.currentCityId)) continue;
      if (repo.hasPoisForCity(city.id)) {
        initial[city.id] = repo.loadForCity(city.id);
      } else {
        _queue.add(city.id);
      }
    }
    if (_queue.isNotEmpty) Future.microtask(_drainQueue);

    // Écoute les mises à jour : fetch uniquement si la ville est visitée/courante
    ref.listen<CityFogState>(cityFogProvider, (_, next) {
      for (final city in next.cities.values) {
        if (!_shouldFetch(city, next.currentCityId)) continue;
        if (!state.poisByCity.containsKey(city.id) &&
            !_fetching.contains(city.id) &&
            !_queue.contains(city.id)) {
          _queue.add(city.id);
        }
      }
      _drainQueue();
    });

    // Détecte les découvertes lors des mises à jour de position
    ref.listen<AsyncValue<LatLng>>(positionStreamProvider, (_, next) {
      next.whenData((pos) {
        _lastKnownPosition = pos;
        _checkDiscovery(pos);
      });
    });

    // Vérification périodique : couvre le cas où l'user s'arrête sur un POI
    // sans que le GPS émette un nouvel événement (distanceFilter)
    final timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkDiscoveryWithLastPosition();
    });
    ref.onDispose(timer.cancel);

    return PoiState(poisByCity: initial);
  }

  PoiRepository get _repo => ref.read(poiRepositoryProvider);
  PoiRemoteDatasource get _remote => ref.read(poiRemoteDatasourceProvider);

  /// Vide la file séquentiellement : un seul fetch Overpass à la fois.
  Future<void> _drainQueue() async {
    if (_queueRunning) return;
    _queueRunning = true;
    while (_queue.isNotEmpty) {
      final cityId = _queue.removeAt(0);
      await _ensurePoisLoaded(cityId);

      // Si Mérimée a échoué (liste toujours vide) → réessai dans 30 s
      final pois = state.poisByCity[cityId];
      if (pois == null || pois.isEmpty) {
        debugPrint('[POI] échec Mérimée pour $cityId — nouvelle tentative dans 30 s');
        await Future.delayed(const Duration(seconds: 30));
        if (!_queue.contains(cityId)) _queue.add(cityId);
        continue;
      }

      // Petit délai entre villes pour ne pas surcharger Mérimée
      if (_queue.isNotEmpty) await Future.delayed(const Duration(seconds: 2));
    }
    _queueRunning = false;
  }

  Future<void> _ensurePoisLoaded(String cityId) async {
    final existing = state.poisByCity[cityId];
    if (existing != null && existing.isNotEmpty) return;
    if (_fetching.contains(cityId)) return;
    _fetching.add(cityId);

    try {
      final repo = _repo;

      // Cache Hive disponible → chargement instantané
      if (repo.hasPoisForCity(cityId)) {
        final pois = repo.loadForCity(cityId);
        state = state.copyWith(
          poisByCity: Map.from(state.poisByCity)..[cityId] = pois,
        );
        _checkDiscoveryWithLastPosition();
        return;
      }

      final city = ref.read(cityFogProvider).cities[cityId];
      if (city == null) return;

      // ── Phase 1 : Mérimée (prioritaire, rapide, fiable) ────────────────
      debugPrint('[POI] Phase 1 — Mérimée pour ${city.name}…');
      final merimeePois = await _remote.fetchMerimeePoisForCity(city);

      if (merimeePois.isEmpty) {
        debugPrint('[POI] Mérimée vide pour ${city.name} — réessai possible');
        return; // retry depuis _drainQueue
      }

      // Sauvegarde et affichage immédiat des POIs Mérimée
      await repo.savePoisForCity(cityId, merimeePois);
      state = state.copyWith(
        poisByCity: Map.from(state.poisByCity)..[cityId] = merimeePois,
      );
      _checkDiscoveryWithLastPosition();
      debugPrint('[POI] ${merimeePois.length} POIs Mérimée pour ${city.name}');

      // ── Phase 2 : OSM/Overpass en parallèle (ne bloque pas la file) ────
      _enrichWithOverpass(cityId, city, merimeePois);
    } finally {
      _fetching.remove(cityId);
    }
  }

  /// Charge les POIs OSM en arrière-plan et les fusionne avec Mérimée.
  Future<void> _enrichWithOverpass(
    String cityId,
    City city,
    List<CityPoi> merimeePois,
  ) async {
    try {
      debugPrint('[POI] OSM bg — ${city.name}…');
      final existingPositions = merimeePois.map((p) => p.position).toList();
      final overpassPois = await _remote.fetchOverpassPoisForCity(
        city,
        existingPositions: existingPositions,
      );

      if (overpassPois.isEmpty) {
        debugPrint('[POI] OSM: rien à ajouter pour ${city.name}');
        return;
      }

      // Fusionne avec l'état courant (peut inclure des découvertes faites entre-temps)
      final currentPois = List<CityPoi>.from(
        state.poisByCity[cityId] ?? merimeePois,
      );
      final merged = [...currentPois, ...overpassPois];

      await _repo.savePoisForCity(cityId, merged);
      state = state.copyWith(
        poisByCity: Map.from(state.poisByCity)..[cityId] = merged,
      );
      debugPrint('[POI] +${overpassPois.length} OSM → ${merged.length} total pour ${city.name}');
    } catch (e) {
      debugPrint('[POI] OSM bg erreur pour ${city.name}: $e');
    }
  }

  void _checkDiscovery(LatLng position) {
    // Scan tous les POIs chargés — pas de dépendance à currentCityId
    // (la dérive GPS peut placer l'user hors du polygone ville)
    for (final pois in state.poisByCity.values) {
      for (final poi in pois) {
        if (_distMeters(position, poi.position) > _discoveryRadiusMeters) continue;

        if (!poi.isDiscovered) {
          _discoverPoi(poi);
        } else if (!_revisitedThisSession.contains(poi.id)) {
          // Re-visite : incrémente le compteur une seule fois par session
          _revisitedThisSession.add(poi.id);
          _incrementVisit(poi);
        }
      }
    }
  }

  /// Test uniquement : simule une position GPS à cet endroit.
  void simulatePosition(LatLng position) {
    _lastKnownPosition = position;
    _checkDiscovery(position);
  }

  /// Marque tous les POIs d'une ville comme découverts (achat avec crédits).
  Future<void> discoverAllForCity(String cityId) async {
    final pois = List<CityPoi>.from(state.poisByCity[cityId] ?? []);
    if (pois.isEmpty) return;

    final now = DateTime.now();
    final updated = pois.map((p) => p.isDiscovered
        ? p
        : CityPoi(
            id: p.id,
            cityId: p.cityId,
            name: p.name,
            emoji: p.emoji,
            position: p.position,
            description: p.description,
            isDiscovered: true,
            firstVisitDate: now,
            visitCount: 1,
          )).toList();

    await _repo.savePoisForCity(cityId, updated);
    state = state.copyWith(
      poisByCity: Map.from(state.poisByCity)..[cityId] = updated,
    );
    debugPrint('[POI] 🔓 ${updated.length} POIs découverts pour $cityId');
  }

  Future<void> reset() async {
    await _repo.clearDiscoveries();
    // Recharge les POIs (toujours en cache, mais sans découvertes)
    final updated = <String, List<CityPoi>>{};
    for (final cityId in state.poisByCity.keys) {
      updated[cityId] = _repo.loadForCity(cityId);
    }
    state = PoiState(poisByCity: updated);
    _revisitedThisSession.clear();
  }

  void _checkDiscoveryWithLastPosition() {
    final pos = _lastKnownPosition ??
        ref.read(positionStreamProvider).valueOrNull ??
        ref.read(initialPositionProvider).valueOrNull;
    if (pos != null) _checkDiscovery(pos);
  }

  Future<void> _discoverPoi(CityPoi poi) async {
    debugPrint('[POI] 🎉 découverte : ${poi.emoji} ${poi.name}');

    final now = DateTime.now();
    final cityPois = List<CityPoi>.from(state.poisByCity[poi.cityId] ?? []);
    final idx = cityPois.indexWhere((p) => p.id == poi.id);
    if (idx == -1) return;
    cityPois[idx] = poi.copyWith(
      isDiscovered: true,
      firstVisitDate: now,
      visitCount: 1,
    );

    state = state.copyWith(
      poisByCity: Map.from(state.poisByCity)..[poi.cityId] = cityPois,
    );

    await _repo.savePoisForCity(poi.cityId, cityPois);

    HapticFeedback.heavyImpact();

    ref
        .read(cityFogProvider.notifier)
        .revealAroundPoint(poi.cityId, poi.position, _poiRevealRadiusMeters);
  }

  Future<void> _incrementVisit(CityPoi poi) async {
    debugPrint('[POI] 🔁 re-visite : ${poi.emoji} ${poi.name} (${poi.visitCount + 1}×)');

    final cityPois = List<CityPoi>.from(state.poisByCity[poi.cityId] ?? []);
    final idx = cityPois.indexWhere((p) => p.id == poi.id);
    if (idx == -1) return;
    cityPois[idx] = poi.copyWith(visitCount: poi.visitCount + 1);

    state = state.copyWith(
      poisByCity: Map.from(state.poisByCity)..[poi.cityId] = cityPois,
    );

    await _repo.savePoisForCity(poi.cityId, cityPois);
    HapticFeedback.mediumImpact();
  }

  bool _shouldFetch(City city, String? currentCityId) =>
      city.id == currentCityId || city.lastVisitDate != null;

  double _distMeters(LatLng a, LatLng b) {
    const k = 111320.0;
    final cosLat = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final dx = (b.longitude - a.longitude) * cosLat * k;
    final dy = (b.latitude - a.latitude) * k;
    return math.sqrt(dx * dx + dy * dy);
  }
}

final poiProvider = NotifierProvider<PoiNotifier, PoiState>(PoiNotifier.new);
