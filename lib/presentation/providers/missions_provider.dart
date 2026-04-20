import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'city_fog_provider.dart';
import 'poi_providers.dart';
import 'wallet_providers.dart';

class Mission {
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final int current;
  final int target;
  final int rewardCoins;

  const Mission({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.current,
    required this.target,
    required this.rewardCoins,
  });

  bool get isCompleted => current >= target;
  double get progress => (current / target).clamp(0.0, 1.0);
}

/// Retourne la longueur (en mètres) du dernier segment continu parmi toutes les villes.
/// Un écart > 24 m entre deux points consécutifs = rupture de continuité.
int _longestContinuousSegmentMeters(CityFogState fog) {
  const maxGap    = 24.0; // ≈ 3× l'intervalle d'échantillonnage (8 m)
  const sampleM   = 8.0;
  const distCalc  = Distance();
  int best = 0;

  for (final city in fog.cities.values) {
    final pts = city.walkedPoints;
    if (pts.length < 2) continue;

    // Remonte depuis le dernier point jusqu'à la première rupture
    int startIdx = pts.length - 1;
    while (startIdx > 0) {
      if (distCalc(pts[startIdx - 1], pts[startIdx]) > maxGap) break;
      startIdx--;
    }
    final meters = ((pts.length - startIdx) * sampleM).round();
    if (meters > best) best = meters;
  }
  return best;
}

final missionsProvider = Provider<List<Mission>>((ref) {
  final steps    = ref.watch(stepCountProvider);
  final fog      = ref.watch(cityFogProvider);
  final poiState = ref.watch(poiProvider);
  final now      = DateTime.now();

  bool isToday(DateTime? d) =>
      d != null && d.year == now.year && d.month == now.month && d.day == now.day;

  // Lieux découverts aujourd'hui
  final poisDiscoveredToday = poiState.allPois
      .where((p) => isToday(p.firstVisitDate))
      .length;

  // Villes/arrondissements marchés aujourd'hui
  final citiesWalkedToday = fog.cities.values
      .where((c) => isToday(c.lastVisitDate))
      .length;

  // Arc-en-ciel accompli si ≥ 1 000 m continus
  final rainbowDone = _longestContinuousSegmentMeters(fog) >= 1000 ? 1 : 0;

  return [
    Mission(
      id: 'daily_steps',
      emoji: '👟',
      title: 'Marche du jour',
      subtitle: 'Faire 10 000 pas aujourd\'hui',
      current: steps.clamp(0, 10000),
      target: 10000,
      rewardCoins: 500,
    ),
    Mission(
      id: 'daily_first_poi',
      emoji: '⭐',
      title: 'Lieu du jour',
      subtitle: 'Découvrir un lieu aujourd\'hui',
      current: poisDiscoveredToday.clamp(0, 1),
      target: 1,
      rewardCoins: 200,
    ),
    Mission(
      id: 'daily_cities',
      emoji: '🏙️',
      title: 'Explorateur urbain',
      subtitle: 'Marcher dans 3 villes aujourd\'hui',
      current: citiesWalkedToday.clamp(0, 3),
      target: 3,
      rewardCoins: 300,
    ),
    Mission(
      id: 'daily_rainbow',
      emoji: '🌈',
      title: 'Arc-en-ciel',
      subtitle: 'Marcher 1 000 m sans interruption GPS',
      current: rainbowDone,
      target: 1,
      rewardCoins: 400,
    ),
  ];
});
