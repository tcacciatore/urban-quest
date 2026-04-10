class TrophyDefinition {
  final String id;
  final String emoji;
  final String name;
  final String description;

  const TrophyDefinition({
    required this.id,
    required this.emoji,
    required this.name,
    required this.description,
  });

  static const all = [
    TrophyDefinition(
      id: 'first_quest',
      emoji: '🥇',
      name: 'Première piste',
      description: 'Première chasse réussie',
    ),
    TrophyDefinition(
      id: 'sprint_15',
      emoji: '⚡',
      name: 'Éclair urbain',
      description: 'Chasse réussie en moins de 15 minutes',
    ),
    TrophyDefinition(
      id: 'sprint_30',
      emoji: '🏃',
      name: 'Sprint des rues',
      description: 'Chasse réussie en moins de 30 minutes',
    ),
    TrophyDefinition(
      id: 'explorer_5',
      emoji: '🗺️',
      name: 'Explorateur',
      description: '5 chasses réussies',
    ),
    TrophyDefinition(
      id: 'legend_10',
      emoji: '🏆',
      name: 'Légende du quartier',
      description: '10 chasses réussies',
    ),
    TrophyDefinition(
      id: 'big_radius',
      emoji: '🌍',
      name: 'Grande aventure',
      description: 'Chasse réussie avec le rayon 2 km',
    ),
    TrophyDefinition(
      id: 'early_bird',
      emoji: '🌅',
      name: 'Lève-tôt',
      description: 'Chasse réussie avant 8h du matin',
    ),
    TrophyDefinition(
      id: 'night_owl',
      emoji: '🦉',
      name: 'Chasseur nocturne',
      description: 'Chasse réussie après 21h',
    ),
    TrophyDefinition(
      id: 'weekend',
      emoji: '🎉',
      name: 'Guerrier du weekend',
      description: 'Chasse réussie un samedi ou un dimanche',
    ),
    TrophyDefinition(
      id: 'hot_streak',
      emoji: '🔥',
      name: 'En feu !',
      description: '3 chasses réussies en une seule journée',
    ),
  ];
}

class EarnedTrophy {
  final TrophyDefinition definition;
  final DateTime earnedAt;

  const EarnedTrophy({required this.definition, required this.earnedAt});
}
