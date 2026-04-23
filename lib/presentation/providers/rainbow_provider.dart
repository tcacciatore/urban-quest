import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'city_fog_provider.dart';

/// Persiste le segment arc-en-ciel accompli pour la journée.
/// Se réinitialise chaque jour. Vide tant que 1 000 m continus n'ont pas été atteints.
class RainbowNotifier extends Notifier<List<LatLng>> {
  static const _prefsKey      = 'completed_rainbow_v1';
  static const _maxGapMeters  = 24.0;  // rupture de continuité
  static const _sampleMeters  = 8.0;   // distance entre deux points
  static const _targetMeters  = 1000.0;

  /// Date à laquelle l'arc-en-ciel a été accompli (en mémoire).
  String? _completedDate;

  @override
  List<LatLng> build() {
    ref.listen<CityFogState>(cityFogProvider, (_, fog) => _checkRainbow(fog));
    _load();
    return [];
  }

  // ── Persistence ──────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final map  = jsonDecode(raw) as Map<String, dynamic>;
      if ((map['date'] as String) != _today()) {
        await prefs.remove(_prefsKey);
        return;
      }
      final pts = (map['points'] as List).map((p) {
        final pair = p as List;
        return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList();
      _completedDate = map['date'] as String;
      state = pts;
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
  }

  Future<void> _save(List<LatLng> points) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({
      'date':   _today(),
      'points': points.map((p) => [p.latitude, p.longitude]).toList(),
    }));
  }

  // ── Détection ────────────────────────────────────────────────────────────────

  void _checkRainbow(CityFogState fog) {
    // Réinitialise si on a passé minuit sans redémarrer l'app
    if (state.isNotEmpty && _completedDate != _today()) {
      state = [];
      _completedDate = null;
    }
    if (state.isNotEmpty) return; // déjà accompli aujourd'hui

    const distCalc = Distance();
    List<LatLng> best = [];

    for (final city in fog.cities.values) {
      final pts = city.walkedPoints;
      if (pts.length < 2) continue;

      // Remonte depuis le dernier point jusqu'à la première rupture
      int startIdx = pts.length - 1;
      while (startIdx > 0) {
        if (distCalc(pts[startIdx - 1], pts[startIdx]) > _maxGapMeters) break;
        startIdx--;
      }

      final segment = pts.sublist(startIdx);
      if (segment.length * _sampleMeters >= _targetMeters &&
          segment.length > best.length) {
        best = segment;
      }
    }

    if (best.isNotEmpty) {
      _completedDate = _today();
      state = best;
      _save(best);
    }
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _completedDate = null;
    state = [];
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

final rainbowProvider =
    NotifierProvider<RainbowNotifier, List<LatLng>>(RainbowNotifier.new);
