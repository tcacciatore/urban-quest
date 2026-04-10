import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../data/datasources/remote/quarter_remote_datasource.dart';
import '../../data/repositories/quarter_repository.dart';
import '../../domain/entities/quarter.dart';
import 'quest_providers.dart';
import 'location_providers.dart';

// ─── Infrastructure ───────────────────────────────────────────────────────────

final quarterDatasourceProvider = Provider<QuarterRemoteDatasource>(
  (ref) => QuarterRemoteDatasource(ref.read(dioProvider)),
);

final quarterRepositoryProvider = Provider<QuarterRepository>(
  (ref) => QuarterRepository(ref.read(quarterDatasourceProvider)),
);

// ─── State ────────────────────────────────────────────────────────────────────

class FogOfWarState {
  final Map<String, Quarter> quarters;
  final Set<String> newlyRevealedIds;
  /// ID OSM de la ville où se trouve actuellement l'utilisateur.
  final String? currentCityId;

  const FogOfWarState({
    this.quarters = const {},
    this.newlyRevealedIds = const {},
    this.currentCityId,
  });

  /// Quartiers appartenant à la ville courante uniquement.
  List<Quarter> get currentCityQuarters => currentCityId == null
      ? []
      : quarters.values.where((q) => q.cityId == currentCityId).toList();

  FogOfWarState copyWith({
    Map<String, Quarter>? quarters,
    Set<String>? newlyRevealedIds,
    String? currentCityId,
  }) =>
      FogOfWarState(
        quarters: quarters ?? this.quarters,
        newlyRevealedIds: newlyRevealedIds ?? this.newlyRevealedIds,
        currentCityId: currentCityId ?? this.currentCityId,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class FogOfWarNotifier extends Notifier<FogOfWarState> {
  bool _busy = false;

  @override
  FogOfWarState build() {
    // 1. Chargement synchrone depuis le cache Hive
    final repo = ref.read(quarterRepositoryProvider);
    final cached = repo.loadAll();

    // 2. Le notifier s'abonne LUI-MÊME aux mises à jour de position.
    //    Ceci évite de dépendre d'un ref.listen dans l'UI.
    ref.listen<AsyncValue<LatLng>>(positionStreamProvider, (_, next) {
      next.whenData(_onPositionUpdate);
    });
    ref.listen<AsyncValue<LatLng>>(initialPositionProvider, (_, next) {
      next.whenData(_onPositionUpdate);
    });

    // 3. Déclencher immédiatement avec la position déjà disponible.
    //    Utiliser Future.microtask pour que `state` soit initialisé avant.
    Future.microtask(() {
      final pos = ref.read(positionStreamProvider).valueOrNull ??
          ref.read(initialPositionProvider).valueOrNull;
      if (pos != null) _onPositionUpdate(pos);
    });

    return FogOfWarState(
      quarters: {for (final q in cached) q.id: q},
    );
  }

  QuarterRepository get _repo => ref.read(quarterRepositoryProvider);

  // ─── Mise à jour de position (déclenchée automatiquement) ────────────────

  Future<void> _onPositionUpdate(LatLng position) async {
    if (_busy) return;
    _busy = true;
    try {
      // Charger toute la ville si pas encore fait
      debugPrint('[FogOfWar] position update: ${position.latitude}, ${position.longitude}');
      final result = await _repo.ensureCityLoaded(position);
      final newQuarters = result.newQuarters;
      final cityId = result.cityId;
      debugPrint('[FogOfWar] ${newQuarters.length} nouveaux quartiers, cityId=$cityId');

      if (newQuarters.isNotEmpty) {
        final updated = Map<String, Quarter>.from(state.quarters);
        for (final q in newQuarters) {
          if (!updated.containsKey(q.id)) updated[q.id] = q;
        }
        state = state.copyWith(quarters: updated, currentCityId: cityId);
      } else if (cityId != null && cityId != state.currentCityId) {
        state = state.copyWith(currentCityId: cityId);
      }

      // La révélation se fait uniquement à la fin d'une chasse (revealQuarterAtPoint)
    } finally {
      _busy = false;
    }
  }

  // ─── API publique ─────────────────────────────────────────────────────────

  /// Appelé à la fin d'une chasse réussie.
  Future<void> revealQuarterAtPoint(LatLng point) async {
    for (final q in state.quarters.values) {
      if (!q.isRevealed && _pip(point, q.polygon)) {
        await _reveal(q);
        return;
      }
    }
    // Fallback : cherche en Hive / Overpass ponctuel
    final quarter = await _repo.getQuarterForPoint(point);
    if (quarter == null) return;
    final existing = state.quarters[quarter.id];
    if (existing != null) {
      if (!existing.isRevealed) await _reveal(existing);
    } else {
      final updated = Map<String, Quarter>.from(state.quarters)
        ..[quarter.id] = quarter;
      state = state.copyWith(quarters: updated);
      await _reveal(quarter);
    }
  }

  /// Tap sur la carte (test mode).
  Future<void> revealOnTap(LatLng point) => revealQuarterAtPoint(point);

  void clearAnimating(String id) {
    state = state.copyWith(
      newlyRevealedIds: Set.from(state.newlyRevealedIds)..remove(id),
    );
  }

  Future<void> reset() async {
    _busy = false;
    await _repo.clearAll();
    state = const FogOfWarState();
    // Re-déclencher le chargement depuis la position déjà connue
    final pos = ref.read(positionStreamProvider).valueOrNull ??
        ref.read(initialPositionProvider).valueOrNull;
    if (pos != null) _onPositionUpdate(pos);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _reveal(Quarter quarter) async {
    final newCount = quarter.huntCount + 1;
    final nowRevealed = quarter.isRevealed || newCount >= quarter.requiredHunts;
    final updated = quarter.copyWith(
      isRevealed: nowRevealed,
      huntCount: newCount,
    );
    await _repo.save(updated);
    state = state.copyWith(
      quarters: Map<String, Quarter>.from(state.quarters)..[updated.id] = updated,
      newlyRevealedIds: nowRevealed && !quarter.isRevealed
          ? {...state.newlyRevealedIds, updated.id}
          : state.newlyRevealedIds,
    );
  }

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

final fogOfWarProvider =
    NotifierProvider<FogOfWarNotifier, FogOfWarState>(FogOfWarNotifier.new);
