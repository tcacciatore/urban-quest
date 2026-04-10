class EmotionTag {
  final String emoji;
  final String label;
  const EmotionTag(this.emoji, this.label);
}

const emotionTags = [
  EmotionTag('✨', 'Inattendu'),
  EmotionTag('🌿', 'Paisible'),
  EmotionTag('🔥', 'Vivant'),
  EmotionTag('🌧️', 'Mélancolique'),
  EmotionTag('🌀', 'Étrange'),
  EmotionTag('☀️', 'Joyeux'),
  EmotionTag('🏚️', 'Oublié'),
  EmotionTag('💫', 'Magique'),
  EmotionTag('🤍', 'Intime'),
  EmotionTag('⚡', 'Intense'),
  EmotionTag('🌫️', 'Mystérieux'),
  EmotionTag('🍂', 'Nostalgique'),
];

/// Suggère un tag émotionnel selon les tags OSM du POI le plus proche.
EmotionTag? suggestFromOsm(String? osmKey, String? osmValue) {
  if (osmKey == null || osmValue == null) return null;

  const mapping = [
    ('tourism', 'artwork', 'Inattendu'),
    ('leisure', 'garden', 'Paisible'),
    ('amenity', 'bench', 'Paisible'),
    ('natural', 'tree', 'Paisible'),
    ('amenity', 'marketplace', 'Vivant'),
    ('leisure', 'pitch', 'Vivant'),
    ('landuse', 'cemetery', 'Mélancolique'),
    ('historic', 'memorial', 'Mélancolique'),
    ('historic', 'war_memorial', 'Mélancolique'),
    ('man_made', 'tower', 'Étrange'),
    ('tunnel', 'yes', 'Étrange'),
    ('leisure', 'park', 'Joyeux'),
    ('shop', 'bakery', 'Joyeux'),
    ('shop', 'florist', 'Joyeux'),
    ('landuse', 'brownfield', 'Oublié'),
    ('amenity', 'telephone', 'Oublié'),
    ('historic', 'station', 'Oublié'),
    ('tourism', 'viewpoint', 'Magique'),
    ('shop', 'books', 'Intime'),
    ('amenity', 'book_exchange', 'Intime'),
    ('bridge', 'yes', 'Intense'),
    ('power', 'plant', 'Intense'),
    ('covered', 'yes', 'Mystérieux'),
    ('historic', 'monument', 'Mystérieux'),
    ('historic', 'building', 'Nostalgique'),
    ('historic', 'fountain', 'Nostalgique'),
  ];

  for (final (key, value, label) in mapping) {
    if (osmKey == key && osmValue == value) {
      return emotionTags.firstWhere((t) => t.label == label);
    }
  }
  return null;
}
