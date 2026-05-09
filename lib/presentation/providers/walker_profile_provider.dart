import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'city_fog_provider.dart';
import 'personal_pin_provider.dart';
import 'quest_history_providers.dart';
import 'trophy_providers.dart';

// ─── Rareté ───────────────────────────────────────────────────────────────────

enum ProfileRarity { commun, rare, epique, legendaire, mythique }

extension ProfileRarityX on ProfileRarity {
  String get label {
    switch (this) {
      case ProfileRarity.commun:     return 'COMMUN';
      case ProfileRarity.rare:       return 'RARE';
      case ProfileRarity.epique:     return 'ÉPIQUE';
      case ProfileRarity.legendaire: return 'LÉGENDAIRE';
      case ProfileRarity.mythique:   return 'MYTHIQUE';
    }
  }

  int get stars {
    switch (this) {
      case ProfileRarity.commun:     return 1;
      case ProfileRarity.rare:       return 2;
      case ProfileRarity.epique:     return 3;
      case ProfileRarity.legendaire: return 4;
      case ProfileRarity.mythique:   return 5;
    }
  }

  Color get color {
    switch (this) {
      case ProfileRarity.commun:     return const Color(0xFF9CA3AF);
      case ProfileRarity.rare:       return const Color(0xFF3B82F6);
      case ProfileRarity.epique:     return const Color(0xFF7C3AED);
      case ProfileRarity.legendaire: return const Color(0xFFF59E0B);
      case ProfileRarity.mythique:   return const Color(0xFFDC2626);
    }
  }
}

// ─── Modèle animal ────────────────────────────────────────────────────────────

class WalkerAnimal {
  final String emoji;
  final String name;
  final String title;
  final String description;
  final Color color;
  final ProfileRarity rarity;

  /// Vecteur idéal pour les animaux commun/rare/épique.
  final List<double>? ideal;

  const WalkerAnimal({
    required this.emoji,
    required this.name,
    required this.title,
    required this.description,
    required this.color,
    required this.rarity,
    this.ideal,
  });
}

// ─── Condition de progression ─────────────────────────────────────────────────

class EvolutionCondition {
  final String emoji;
  final String label;
  final double current;
  final double target;
  final String unit;

  const EvolutionCondition({
    required this.emoji,
    required this.label,
    required this.current,
    required this.target,
    required this.unit,
  });

  double get progress  => (current / target).clamp(0.0, 1.0);
  bool   get isMet     => current >= target;
  double get remaining => max(0, target - current);
}

// ─── Prochaine évolution ──────────────────────────────────────────────────────

class ProfileEvolution {
  final WalkerAnimal animal;
  final List<EvolutionCondition> conditions;

  const ProfileEvolution({required this.animal, required this.conditions});

  /// Progression globale = min des conditions (la plus contraignante)
  double get overallProgress =>
      conditions.isEmpty ? 0.0 : conditions.map((c) => c.progress).reduce(min);

  /// True si toutes les conditions sont remplies
  bool get isUnlocked => conditions.every((c) => c.isMet);
}

// ─── Stats brutes ─────────────────────────────────────────────────────────────

class RawStats {
  final double totalKm;
  final int citiesVisited;
  final int questsCompleted;
  final int pinsCount;
  final int trophiesCount;

  const RawStats({
    required this.totalKm,
    required this.citiesVisited,
    required this.questsCompleted,
    required this.pinsCount,
    required this.trophiesCount,
  });
}

// ─── Catalogue ────────────────────────────────────────────────────────────────

// Commun / Rare / Épique — matching euclidien
const WalkerAnimal pierreAnimal = WalkerAnimal(
  emoji: '🪨', name: 'Pierre', rarity: ProfileRarity.commun,
  title: 'La Pierre Immobile',
  description: 'Tout commence ici. Lance ta première chasse et la ville s\'ouvre à toi.',
  color: Color(0xFF9E9E9E),
  ideal: null,
);

const List<WalkerAnimal> euclideanAnimals = [
  WalkerAnimal(
    emoji: '🐌', name: 'Escargot', rarity: ProfileRarity.commun,
    title: 'Le Flâneur',
    description: 'Chaque sortie compte, même la plus courte. Les grandes aventures commencent par un seul pas.',
    color: Color(0xFF8B9E6B),
    ideal: [0.1, 0.1, 0.1, 0.1, 0.1],
  ),
  WalkerAnimal(
    emoji: '🐢', name: 'Tortue', rarity: ProfileRarity.commun,
    title: 'Le Marcheur Patient',
    description: 'Méthodique et constant, tu avances à ton propre rythme. Ta persévérance finit toujours par payer.',
    color: Color(0xFF4A7C59),
    ideal: [0.2, 0.4, 0.2, 0.3, 0.4],
  ),
  WalkerAnimal(
    emoji: '🦋', name: 'Papillon', rarity: ProfileRarity.rare,
    title: 'L\'Âme Curieuse',
    description: 'Tu poses des épingles, tu remarques les détails que les autres ignorent. La ville est ton jardin secret.',
    color: Color(0xFF7C3AED),
    ideal: [0.4, 0.4, 0.5, 0.9, 0.5],
  ),
  WalkerAnimal(
    emoji: '🐕', name: 'Chien', rarity: ProfileRarity.rare,
    title: 'Le Fidèle du Quartier',
    description: 'Tu connais tes rues par cœur. Régulier, loyal, tu reviens toujours sur tes territoires de prédilection.',
    color: Color(0xFFD97706),
    ideal: [0.5, 0.6, 0.2, 0.4, 0.7],
  ),
  WalkerAnimal(
    emoji: '🐇', name: 'Lapin', rarity: ProfileRarity.rare,
    title: 'Le Sprinter Bondissant',
    description: 'Vif et énergique, tu enchaînes les chasses à toute allure. Quand tu pars, difficile de te suivre.',
    color: Color(0xFFEC4899),
    ideal: [0.8, 0.4, 0.5, 0.5, 0.7],
  ),
  WalkerAnimal(
    emoji: '🦊', name: 'Renard', rarity: ProfileRarity.epique,
    title: 'L\'Explorateur Malin',
    description: 'Curieux et futé, tu flaires les quartiers inédits avec instinct. Rien ne t\'échappe dans la ville.',
    color: Color(0xFFEA580C),
    ideal: [0.6, 0.6, 0.8, 0.7, 0.7],
  ),
  WalkerAnimal(
    emoji: '🐺', name: 'Loup', rarity: ProfileRarity.epique,
    title: 'Le Solitaire Endurant',
    description: 'Déterminé, tu avances vite et loin sans jamais fléchir. Ta ténacité force le respect de la ville entière.',
    color: Color(0xFF1E40AF),
    ideal: [0.7, 0.8, 0.6, 0.4, 0.8],
  ),
  WalkerAnimal(
    emoji: '🐆', name: 'Guépard', rarity: ProfileRarity.epique,
    title: 'Le Sprinter Urbain',
    description: 'Ultra-rapide sur tes chasses, tu boucles tes quêtes à une vitesse record. La ville tremble sur ton passage.',
    color: Color(0xFFF59E0B),
    ideal: [0.95, 0.6, 0.5, 0.3, 0.8],
  ),
];

// Légendaire & Mythique — conditions brutes
class ThresholdAnimal {
  final WalkerAnimal animal;
  final List<EvolutionCondition> Function(RawStats) buildConditions;

  const ThresholdAnimal({required this.animal, required this.buildConditions});

  bool isUnlocked(RawStats s) => buildConditions(s).every((c) => c.isMet);

  ProfileEvolution toEvolution(RawStats s) =>
      ProfileEvolution(animal: animal, conditions: buildConditions(s));
}

final List<ThresholdAnimal> thresholdAnimals = [

  // ── MYTHIQUE (du plus difficile au plus facile) ──────────────────────────

  ThresholdAnimal(
    animal: const WalkerAnimal(
      emoji: '🐉', name: 'Dragon des Rues', rarity: ProfileRarity.mythique,
      title: 'La Légende Vivante',
      description: 'Tu transcendes toutes les catégories. Des centaines de kilomètres, des dizaines de quartiers conquis, presque tous les trophées. La ville s\'incline devant toi.',
      color: Color(0xFFDC2626),
    ),
    buildConditions: (s) => [
      EvolutionCondition(emoji: '🗺️', label: 'Kilomètres',  current: s.totalKm,        target: 300, unit: 'km'),
      EvolutionCondition(emoji: '🏙️', label: 'Quartiers',   current: s.citiesVisited.toDouble(), target: 30, unit: 'villes'),
      EvolutionCondition(emoji: '🏆', label: 'Trophées',    current: s.trophiesCount.toDouble(), target: 9, unit: '/ 10'),
    ],
  ),

  ThresholdAnimal(
    animal: const WalkerAnimal(
      emoji: '🌟', name: 'Phénix', rarity: ProfileRarity.mythique,
      title: 'L\'Indestructible',
      description: 'Tous les trophées. 150 km parcourus. Tu es renaît des cendres de chaque abandon. On ne t\'arrête plus.',
      color: Color(0xFFFF6B35),
    ),
    buildConditions: (s) => [
      EvolutionCondition(emoji: '🏆', label: 'Tous les trophées', current: s.trophiesCount.toDouble(), target: 10, unit: '/ 10'),
      EvolutionCondition(emoji: '🗺️', label: 'Kilomètres',        current: s.totalKm,                  target: 150, unit: 'km'),
    ],
  ),

  ThresholdAnimal(
    animal: const WalkerAnimal(
      emoji: '🦄', name: 'Licorne', rarity: ProfileRarity.mythique,
      title: 'L\'Être Unique',
      description: 'Ni rapide ni lent — singulier. Tu as marqué la ville de dizaines de souvenirs et exploré des contrées que personne d\'autre n\'a jamais foulées.',
      color: Color(0xFFBE185D),
    ),
    buildConditions: (s) => [
      EvolutionCondition(emoji: '📍', label: 'Souvenirs posés', current: s.pinsCount.toDouble(),        target: 35, unit: 'pins'),
      EvolutionCondition(emoji: '🏙️', label: 'Quartiers',       current: s.citiesVisited.toDouble(),    target: 20, unit: 'villes'),
      EvolutionCondition(emoji: '🏆', label: 'Trophées',         current: s.trophiesCount.toDouble(),    target: 6, unit: '/ 10'),
    ],
  ),

  // ── LÉGENDAIRE ───────────────────────────────────────────────────────────

  ThresholdAnimal(
    animal: const WalkerAnimal(
      emoji: '🦁', name: 'Lion', rarity: ProfileRarity.legendaire,
      title: 'Le Roi de la Ville',
      description: 'Champion absolu des chasses. Nombreux trophées au compteur et une activité soutenue qui te place au sommet.',
      color: Color(0xFFB45309),
    ),
    buildConditions: (s) => [
      EvolutionCondition(emoji: '🏆', label: 'Trophées',  current: s.trophiesCount.toDouble(), target: 7, unit: '/ 10'),
      EvolutionCondition(emoji: '🏁', label: 'Chasses',   current: s.questsCompleted.toDouble(), target: 15, unit: 'réussies'),
    ],
  ),

  ThresholdAnimal(
    animal: const WalkerAnimal(
      emoji: '🦅', name: 'Aigle', rarity: ProfileRarity.legendaire,
      title: 'Le Grand Voyageur',
      description: 'Tu vois la ville d\'en haut. Des dizaines de quartiers conquis, des kilomètres infinis. L\'horizon est ta maison.',
      color: Color(0xFF0284C7),
    ),
    buildConditions: (s) => [
      EvolutionCondition(emoji: '🗺️', label: 'Kilomètres', current: s.totalKm,                       target: 80, unit: 'km'),
      EvolutionCondition(emoji: '🏙️', label: 'Quartiers',  current: s.citiesVisited.toDouble(), target: 12, unit: 'villes'),
    ],
  ),

  ThresholdAnimal(
    animal: const WalkerAnimal(
      emoji: '🐘', name: 'Éléphant', rarity: ProfileRarity.legendaire,
      title: 'Le Marcheur Inébranlable',
      description: 'Puissant et régulier, tu accumules les kilomètres sans jamais t\'arrêter. Rien ne résiste à ton endurance légendaire.',
      color: Color(0xFF6B7280),
    ),
    buildConditions: (s) => [
      EvolutionCondition(emoji: '🗺️', label: 'Kilomètres', current: s.totalKm, target: 100, unit: 'km'),
    ],
  ),
];

// ─── Profil calculé ───────────────────────────────────────────────────────────

class WalkerProfile {
  final WalkerAnimal animal;

  // Axes (0.0–1.0)
  final double speed;
  final double endurance;
  final double exploration;
  final double curiosity;
  final double activity;

  // Stats brutes
  final double totalKm;
  final int citiesVisited;
  final int questsCompleted;
  final int pinsCount;
  final int trophiesCount;

  /// Prochain palier à atteindre (null si mythique déjà obtenu)
  final ProfileEvolution? nextEvolution;

  const WalkerProfile({
    required this.animal,
    required this.speed,
    required this.endurance,
    required this.exploration,
    required this.curiosity,
    required this.activity,
    required this.totalKm,
    required this.citiesVisited,
    required this.questsCompleted,
    required this.pinsCount,
    required this.trophiesCount,
    this.nextEvolution,
  });

  RawStats get rawStats => RawStats(
    totalKm: totalKm, citiesVisited: citiesVisited,
    questsCompleted: questsCompleted, pinsCount: pinsCount,
    trophiesCount: trophiesCount,
  );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final walkerProfileProvider = Provider<WalkerProfile>((ref) {
  final cityFog     = ref.watch(cityFogProvider);
  final pins        = ref.watch(personalPinProvider);
  final histAsync   = ref.watch(questHistoryProvider);
  final trophyAsync = ref.watch(trophyProvider);

  final history  = histAsync.valueOrNull ?? [];
  final trophies = trophyAsync.valueOrNull ?? [];

  // ── Stats brutes ─────────────────────────────────────────────────────────
  final totalKm = cityFog.cities.values.fold<double>(
    0.0, (sum, c) => sum + c.walkedPoints.length * 8.0 / 1000.0,
  );
  final citiesVisited = cityFog.cities.values
      .where((c) => c.lastVisitDate != null || c.walkedPoints.isNotEmpty)
      .length;
  final questsCompleted = history.where((e) => e.wasCompleted).length;

  final raw = RawStats(
    totalKm: totalKm, citiesVisited: citiesVisited,
    questsCompleted: questsCompleted,
    pinsCount: pins.length, trophiesCount: trophies.length,
  );

  // ── Axes normalisés ───────────────────────────────────────────────────────
  double speed = 0.3;
  final completedWithDuration =
      history.where((e) => e.wasCompleted && e.completedAt != null).toList();
  if (completedWithDuration.isNotEmpty) {
    double totalPace = 0; int count = 0;
    for (final e in completedWithDuration) {
      final mins = e.duration!.inSeconds / 60.0;
      final km   = e.radiusMeters / 1000.0;
      if (km > 0 && mins > 0) { totalPace += mins / km; count++; }
    }
    if (count > 0) speed = ((40 - totalPace / count) / 35).clamp(0.0, 1.0);
  }

  final endurance   = (totalKm / 100.0).clamp(0.0, 1.0);
  final exploration = (citiesVisited / 15.0).clamp(0.0, 1.0);
  final curiosity   = (pins.length / 20.0).clamp(0.0, 1.0);
  final activity    = ((questsCompleted / 15.0) * 0.65 +
                       (trophies.length / 8.0) * 0.35).clamp(0.0, 1.0);

  // ── Matching : pierre d'abord, seuils ensuite, euclidien sinon ───────────
  WalkerAnimal? current;

  // Aucune activité → Pierre
  if (raw.questsCompleted == 0 && raw.totalKm < 0.1 && raw.pinsCount == 0) {
    current = pierreAnimal;
  }

  if (current == null) {
    for (final ta in thresholdAnimals) {
      if (ta.isUnlocked(raw)) { current = ta.animal; break; }
    }
  }

  if (current == null) {
    final scores = [speed, endurance, exploration, curiosity, activity];
    WalkerAnimal best = euclideanAnimals.first;
    double bestDist = double.infinity;
    for (final a in euclideanAnimals) {
      double dist = 0;
      for (int i = 0; i < 5; i++) {
        final d = scores[i] - a.ideal![i]; dist += d * d;
      }
      if (sqrt(dist) < bestDist) { bestDist = sqrt(dist); best = a; }
    }
    current = best;
  }

  // ── Prochaine évolution ───────────────────────────────────────────────────
  // Respecte la progression naturelle : pierre → commun → rare → épique → légendaire → mythique
  ProfileEvolution? nextEvolution;
  final currentRarity = current.rarity;

  if (current == pierreAnimal) {
    // Pierre → Escargot : lancer la première quête
    nextEvolution = ProfileEvolution(
      animal: euclideanAnimals.first, // Escargot
      conditions: [
        EvolutionCondition(
          emoji: '🏃', label: 'Première chasse complétée',
          current: raw.questsCompleted.toDouble(), target: 1, unit: 'chasse',
        ),
      ],
    );
  } else if (currentRarity == ProfileRarity.commun || currentRarity == ProfileRarity.rare) {
    // Euclidien : montrer le prochain palier de rareté
    final targetRarity = currentRarity == ProfileRarity.commun
        ? ProfileRarity.rare
        : ProfileRarity.epique;
    final candidates = euclideanAnimals.where((a) => a.rarity == targetRarity).toList();
    final scores = [speed, endurance, exploration, curiosity, activity];

    // Animal cible = le plus proche dans le palier supérieur
    WalkerAnimal target = candidates.first;
    double bestDist = double.infinity;
    for (final a in candidates) {
      double dist = 0;
      for (int i = 0; i < 5; i++) {
        final d = scores[i] - a.ideal![i]; dist += d * d;
      }
      if (sqrt(dist) < bestDist) { bestDist = sqrt(dist); target = a; }
    }

    // Conditions concrètes : axes mesurables avec un écart significatif
    final ideal = target.ideal!;
    final List<EvolutionCondition> conditions = [];

    // endurance [1] → km
    final kmTarget = (ideal[1] * 100).roundToDouble();
    if (raw.totalKm < kmTarget - 0.5) {
      conditions.add(EvolutionCondition(
        emoji: '🗺️', label: 'Kilomètres parcourus',
        current: double.parse(raw.totalKm.toStringAsFixed(1)),
        target: kmTarget, unit: 'km',
      ));
    }
    // exploration [2] → villes
    final villesTarget = (ideal[2] * 15).ceil().toDouble();
    if (raw.citiesVisited < villesTarget) {
      conditions.add(EvolutionCondition(
        emoji: '🏙️', label: 'Villes explorées',
        current: raw.citiesVisited.toDouble(), target: villesTarget, unit: 'ville(s)',
      ));
    }
    // curiosité [3] → tags
    final tagsTarget = (ideal[3] * 20).ceil().toDouble();
    if (raw.pinsCount < tagsTarget) {
      conditions.add(EvolutionCondition(
        emoji: '📍', label: 'Tags posés',
        current: raw.pinsCount.toDouble(), target: tagsTarget, unit: 'tag(s)',
      ));
    }
    // activité [4] → quêtes
    final quetesTarget = (ideal[4] * 15).ceil().toDouble();
    if (raw.questsCompleted < quetesTarget) {
      conditions.add(EvolutionCondition(
        emoji: '🏆', label: 'Chasses complétées',
        current: raw.questsCompleted.toDouble(), target: quetesTarget, unit: 'chasse(s)',
      ));
    }

    if (conditions.isNotEmpty) {
      nextEvolution = ProfileEvolution(animal: target, conditions: conditions);
    }
  } else {
    // Épique ou seuil : montrer le seuil légendaire/mythique le plus avancé
    double bestProgress = -1;
    for (final ta in thresholdAnimals.reversed) { // du plus facile au plus dur
      if (ta.isUnlocked(raw)) continue;
      final evo = ta.toEvolution(raw);
      if (evo.overallProgress > bestProgress) {
        bestProgress = evo.overallProgress;
        nextEvolution = evo;
      }
    }
  }

  return WalkerProfile(
    animal: current,
    speed: speed, endurance: endurance,
    exploration: exploration, curiosity: curiosity, activity: activity,
    totalKm: totalKm, citiesVisited: citiesVisited,
    questsCompleted: questsCompleted,
    pinsCount: pins.length, trophiesCount: trophies.length,
    nextEvolution: nextEvolution,
  );
});
