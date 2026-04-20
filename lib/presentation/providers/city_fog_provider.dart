import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  final bool isLoading;

  const CityFogState({
    this.cities = const {},
    this.currentCityId,
    this.isLoading = false,
  });

  City? get currentCity =>
      currentCityId != null ? cities[currentCityId] : null;

  CityFogState copyWith({
    Map<String, City>? cities,
    String? currentCityId,
    bool? isLoading,
  }) =>
      CityFogState(
        cities: cities ?? this.cities,
        currentCityId: currentCityId ?? this.currentCityId,
        isLoading: isLoading ?? this.isLoading,
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

    // Les voisines de cette ville ont déjà été chargées → pas d'appel Overpass
    if (currentId != null && _repo.isCityLoaded(currentId)) return;

    if (_busy) return;
    _busy = true;
    state = state.copyWith(isLoading: true);
    try {
      final result = await _repo.ensureCitiesLoaded(position);
      if (result.newCities.isNotEmpty) {
        final updated = Map<String, City>.from(state.cities);
        for (final c in result.newCities) {
          updated[c.id] = c;
        }
        final newCurrentId =
            result.currentCityId ?? _cityContaining(position, updated);
        state = state.copyWith(
          cities: updated,
          currentCityId: newCurrentId,
          isLoading: false,
        );
        debugPrint('[CityFog] ${result.newCities.length} villes chargées, '
            'courante: ${state.currentCity?.name}');
      } else if (result.currentCityId != null &&
          result.currentCityId != state.currentCityId) {
        state = state.copyWith(
          currentCityId: result.currentCityId,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } finally {
      _busy = false;
      if (state.isLoading) state = state.copyWith(isLoading: false);
    }
  }

  // ─── Marche ───────────────────────────────────────────────────────────────

  static const _sampleDistanceMeters = 8.0;
  static const _revealRadiusMeters   = 2.0;
  static const _gridTargetCount      = 200;
  static const _milestones           = [0.25, 0.50, 0.75, 1.0];

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

    final oldRatio  = city.revealedRatio;
    final newPoints = [...city.walkedPoints, position];
    final grid      = _getOrCreateGrid(cityId, city.polygon);
    final ratio     = _computeRatio(grid, newPoints);

    final updated = city.copyWith(walkedPoints: newPoints, revealedRatio: ratio, lastVisitDate: DateTime.now());
    _repo.save(updated);
    state = state.copyWith(
      cities: Map<String, City>.from(state.cities)..[cityId] = updated,
    );

    debugPrint('[CityFog] ${city.name}: ${newPoints.length} pts, '
        '${(ratio * 100).toStringAsFixed(1)}% révélé');

    _triggerMilestoneHaptic(oldRatio, ratio);

    if (updated.isUnlocked) {
      debugPrint('[CityFog] 🎉 ${city.name} déverrouillée !');
    }
  }

  void _triggerMilestoneHaptic(double oldRatio, double newRatio) {
    for (final milestone in _milestones) {
      if (oldRatio < milestone && newRatio >= milestone) {
        if (milestone >= 1.0) {
          // 100% — vibration forte
          HapticFeedback.heavyImpact();
        } else {
          // 25 / 50 / 75% — vibration moyenne
          HapticFeedback.mediumImpact();
        }
        debugPrint('[CityFog] 🎯 palier ${(milestone * 100).round()}% atteint');
        return; // un seul palier par point
      }
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

  /// Révèle une grande zone de brouillard autour d'un point (découverte POI).
  void revealAroundPoint(String cityId, LatLng center, double revealRadius) {
    final city = state.cities[cityId];
    if (city == null) return;

    const k = 111320.0;
    final cosLat = math.cos(center.latitude * math.pi / 180);
    // Espacement entre les points synthétiques (légèrement inférieur au rayon de révélation)
    final step = _revealRadiusMeters * 1.6;
    final stepDeg = step / k;
    final stepDegLon = step / (cosLat * k);

    final newPoints = <LatLng>[center];
    final rings = (revealRadius / step).ceil();
    for (int ring = 1; ring <= rings; ring++) {
      final angleCount = (6 * ring).clamp(6, 24);
      for (int i = 0; i < angleCount; i++) {
        final angle = 2 * math.pi * i / angleCount;
        final dlat = math.cos(angle) * ring * stepDeg;
        final dlon = math.sin(angle) * ring * stepDegLon;
        final p = LatLng(center.latitude + dlat, center.longitude + dlon);
        if (_approxMeters(center, p) <= revealRadius + _revealRadiusMeters) {
          newPoints.add(p);
        }
      }
    }

    final merged = [...city.walkedPoints, ...newPoints];
    final grid = _getOrCreateGrid(cityId, city.polygon);
    final ratio = _computeRatio(grid, merged);
    final oldRatio = city.revealedRatio;

    final updated = city.copyWith(walkedPoints: merged, revealedRatio: ratio);
    _repo.save(updated);
    state = state.copyWith(
      cities: Map<String, City>.from(state.cities)..[cityId] = updated,
    );

    _triggerMilestoneHaptic(oldRatio, ratio);
    debugPrint('[CityFog] POI reveal: ${(ratio * 100).toStringAsFixed(1)}% pour $cityId');
  }

  /// Test uniquement : simule une position GPS à cet endroit.
  void simulatePosition(LatLng position) => _onPositionUpdate(position);

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
