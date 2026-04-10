import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/remote/city_remote_datasource.dart';
import '../../data/repositories/city_repository.dart';
import '../../domain/entities/city.dart';
import 'location_providers.dart';
import 'quest_providers.dart'; // pour dioProvider

// ─── Infrastructure ───────────────────────────────────────────────────────────

final cityRemoteDatasourceProvider = Provider<CityRemoteDatasource>(
  (ref) => CityRemoteDatasource(ref.read(dioProvider)),
);

final cityRepositoryProvider = Provider<CityRepository>(
  (ref) => CityRepository(ref.read(cityRemoteDatasourceProvider)),
);

// ─── State ────────────────────────────────────────────────────────────────────

class CityFogState {
  final Map<String, City> cities;
  final String? currentCityId;

  const CityFogState({this.cities = const {}, this.currentCityId});

  City? get currentCity =>
      currentCityId != null ? cities[currentCityId] : null;

  CityFogState copyWith({
    Map<String, City>? cities,
    String? currentCityId,
  }) =>
      CityFogState(
        cities: cities ?? this.cities,
        currentCityId: currentCityId ?? this.currentCityId,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class CityFogNotifier extends Notifier<CityFogState> {
  bool _busy = false;
  /// Grille de points d'échantillonnage par ville (calculée une fois en mémoire).
  final Map<String, List<LatLng>> _gridCache = {};

  @override
  CityFogState build() {
    final cached = ref.read(cityRepositoryProvider).loadAll();

    ref.listen<AsyncValue<LatLng>>(positionStreamProvider, (_, next) {
      next.whenData(_onPositionUpdate);
    });
    ref.listen<AsyncValue<LatLng>>(initialPositionProvider, (_, next) {
      next.whenData(_onPositionUpdate);
    });

    Future.microtask(() {
      final pos = ref.read(positionStreamProvider).valueOrNull ??
          ref.read(initialPositionProvider).valueOrNull;
      if (pos != null) _onPositionUpdate(pos);
    });

    return CityFogState(
      cities: {for (final c in cached) c.id: c},
    );
  }

  CityRepository get _repo => ref.read(cityRepositoryProvider);

  // ─── Position ─────────────────────────────────────────────────────────────

  Future<void> _onPositionUpdate(LatLng position) async {
    final currentId = _cityContaining(position);
    if (currentId != state.currentCityId) {
      state = state.copyWith(currentCityId: currentId);
    }

    // Enregistre le point de marche dans la ville courante
    _addWalkedPoint(position);

    // Si la ville + ses voisines sont déjà chargées → pas d'appel Overpass
    if (currentId != null && state.cities.length > 1) return;

    if (_busy) return;
    _busy = true;
    try {
      final result = await _repo.ensureCitiesLoaded(position);
      if (result.newCities.isNotEmpty) {
        final updated = Map<String, City>.from(state.cities);
        for (final c in result.newCities) {
          updated[c.id] = c;
        }
        final newCurrentId =
            result.currentCityId ?? _cityContaining(position, updated);
        state = state.copyWith(cities: updated, currentCityId: newCurrentId);
        debugPrint('[CityFog] ${result.newCities.length} villes chargées, '
            'courante: ${state.currentCity?.name}');
      } else if (result.currentCityId != null &&
          result.currentCityId != state.currentCityId) {
        state = state.copyWith(currentCityId: result.currentCityId);
      }
    } finally {
      _busy = false;
    }
  }

  // ─── Marche ───────────────────────────────────────────────────────────────

  static const _sampleDistanceMeters = 30.0;
  static const _revealRadiusMeters   = 50.0;
  static const _gridTargetCount      = 200;

  void _addWalkedPoint(LatLng position) {
    final cityId = state.currentCityId;
    if (cityId == null) return;
    final city = state.cities[cityId];
    if (city == null || city.isUnlocked) return;

    // Vérifier la distance minimale par rapport au dernier point
    if (city.walkedPoints.isNotEmpty) {
      final dist = _approxMeters(city.walkedPoints.last, position);
      if (dist < _sampleDistanceMeters) return;
    }

    final newPoints = [...city.walkedPoints, position];
    final grid = _getOrCreateGrid(cityId, city.polygon);
    final ratio = _computeRatio(grid, newPoints);

    final updated = city.copyWith(walkedPoints: newPoints, revealedRatio: ratio);
    _repo.save(updated);
    state = state.copyWith(
      cities: Map<String, City>.from(state.cities)..[cityId] = updated,
    );

    debugPrint('[CityFog] ${city.name}: ${newPoints.length} pts, '
        '${(ratio * 100).toStringAsFixed(1)}% révélé');

    if (updated.isUnlocked) {
      debugPrint('[CityFog] 🎉 ${city.name} déverrouillée !');
    }
  }

  List<LatLng> _getOrCreateGrid(String cityId, List<LatLng> polygon) =>
      _gridCache.putIfAbsent(cityId, () => _generateGrid(polygon));

  /// Grille uniforme de ~200 points à l'intérieur du polygone.
  List<LatLng> _generateGrid(List<LatLng> polygon) {
    double minLat = polygon.first.latitude, maxLat = polygon.first.latitude;
    double minLon = polygon.first.longitude, maxLon = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final steps = math.sqrt(_gridTargetCount).ceil();
    final latStep = (maxLat - minLat) / steps;
    final lonStep = (maxLon - minLon) / steps;

    final grid = <LatLng>[];
    for (int i = 0; i <= steps; i++) {
      for (int j = 0; j <= steps; j++) {
        final p = LatLng(minLat + latStep * i, minLon + lonStep * j);
        if (_pip(p, polygon)) grid.add(p);
      }
    }
    return grid;
  }

  /// Fraction des points de grille couverts par au moins un cercle de 50 m.
  double _computeRatio(List<LatLng> grid, List<LatLng> walkedPoints) {
    if (grid.isEmpty) return 0.0;
    const rSq = _revealRadiusMeters * _revealRadiusMeters;
    int covered = 0;
    for (final gp in grid) {
      for (final wp in walkedPoints) {
        if (_approxMetersSq(gp, wp) <= rSq) {
          covered++;
          break;
        }
      }
    }
    return covered / grid.length;
  }

  // ─── API publique ─────────────────────────────────────────────────────────

  Future<void> reset() async {
    _busy = false;
    _gridCache.clear();
    await _repo.clearAll();
    state = const CityFogState();
    final pos = ref.read(positionStreamProvider).valueOrNull ??
        ref.read(initialPositionProvider).valueOrNull;
    if (pos != null) _onPositionUpdate(pos);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String? _cityContaining(LatLng pos, [Map<String, City>? cities]) {
    final map = cities ?? state.cities;
    for (final city in map.values) {
      if (_pip(pos, city.polygon)) return city.id;
    }
    return null;
  }

  bool _pip(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    int crossings = 0;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }

  /// Distance approximative en mètres (équirectangulaire, précis < 10 km).
  double _approxMeters(LatLng a, LatLng b) =>
      math.sqrt(_approxMetersSq(a, b));

  double _approxMetersSq(LatLng a, LatLng b) {
    const k = 111320.0;
    final cosLat =
        math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final dx = (b.longitude - a.longitude) * cosLat * k;
    final dy = (b.latitude - a.latitude) * k;
    return dx * dx + dy * dy;
  }
}

final cityFogProvider =
    NotifierProvider<CityFogNotifier, CityFogState>(CityFogNotifier.new);
