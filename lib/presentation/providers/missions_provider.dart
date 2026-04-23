import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'city_fog_provider.dart';
import 'poi_providers.dart';
import 'wallet_providers.dart';
import '../../utils/shape_detection.dart' as shapes;

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

/// Longueur max (en mètres) du dernier segment continu parmi toutes les villes.
int _longestContinuousSegmentMeters(CityFogState fog) {
  int best = 0;
  for (final city in fog.cities.values) {
    final seg = shapes.lastContinuousSegment(city.walkedPoints);
    final m   = shapes.segmentLengthM(seg).round();
    if (m > best) best = m;
  }
  return best;
}

/// Retourne vrai si au moins une ville a un segment continu validant [detector].
bool _anyShape(CityFogState fog, bool Function(List<LatLng>) detector) {
  return fog.cities.values.any((city) {
    final seg = shapes.lastContinuousSegment(city.walkedPoints);
    return seg.length >= 2 && detector(seg);
  });
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
  final rainbowDone     = _longestContinuousSegmentMeters(fog) >= 1000 ? 1 : 0;

  // Formes géométriques
  final hasLoop         = _anyShape(fog, shapes.detectLoop)         ? 1 : 0;
  final hasAllerRetour  = _anyShape(fog, shapes.detectAllerRetour)  ? 1 : 0;
  final hasTriangle     = _anyShape(fog, shapes.detectTriangle)     ? 1 : 0;
  final hasSquare       = _anyShape(fog, shapes.detectSquare)       ? 1 : 0;

  return [
    Mission(
      id: 'daily_steps',
      emoji: '👟',
      title: 'Marche du jour',
      subtitle: 'Atteins 10 000 pas aujourd\'hui.',
      current: steps.clamp(0, 10000),
      target: 10000,
      rewardCoins: 500,
    ),
    Mission(
      id: 'daily_first_poi',
      emoji: '⭐',
      title: 'Lieu du jour',
      subtitle: 'Approche-toi d\'un lieu d\'intérêt pour le découvrir.',
      current: poisDiscoveredToday.clamp(0, 1),
      target: 1,
      rewardCoins: 200,
    ),
    Mission(
      id: 'daily_cities',
      emoji: '🏙️',
      title: 'Explorateur urbain',
      subtitle: 'Marche dans 3 quartiers différents aujourd\'hui.',
      current: citiesWalkedToday.clamp(0, 3),
      target: 3,
      rewardCoins: 300,
    ),
    Mission(
      id: 'daily_rainbow',
      emoji: '🌈',
      title: 'Arc-en-ciel',
      subtitle: 'Marche 1 000 m sans interruption GPS.',
      current: rainbowDone,
      target: 1,
      rewardCoins: 400,
    ),
    Mission(
      id: 'daily_loop',
      emoji: '⭕',
      title: 'Boucle',
      subtitle: 'Reviens à ton point de départ après 500 m.',
      current: hasLoop,
      target: 1,
      rewardCoins: 300,
    ),
    Mission(
      id: 'daily_back_and_forth',
      emoji: '↩️',
      title: 'Aller-retour',
      subtitle: 'Pars, fais demi-tour et reviens à ton point de départ (400 m min.).',
      current: hasAllerRetour,
      target: 1,
      rewardCoins: 250,
    ),
    Mission(
      id: 'daily_triangle',
      emoji: '🔺',
      title: 'Triangle',
      subtitle: 'Trace un triangle fermé sur la carte (≥ 300 m).',
      current: hasTriangle,
      target: 1,
      rewardCoins: 500,
    ),
    Mission(
      id: 'daily_square',
      emoji: '🔲',
      title: 'Carré',
      subtitle: 'Trace un carré ou rectangle fermé sur la carte (≥ 300 m).',
      current: hasSquare,
      target: 1,
      rewardCoins: 600,
    ),
  ];
});
