class AppConstants {
  // Mode test — mettre à false en production
  static const bool testMode = true;

  // Chasse
  static const int maxQuestsPerDay = 3;
  static const double arrivalRadiusMeters = 10.0;

  // Crédits
  static const int creditsPerStep = 1;
  static const int initialCredits = 0;
  static const int questCost = 5000;
  static const Map<int, int> radiusCostMap = {
    500: 5000,
    1000: 5000,
    2000: 5000,
  };

  // Génération de lieux
  static const List<int> availableRadii = [500, 1000, 2000];
  static const int overpassTimeoutSeconds = 10;

  // Indices
  static const int totalClues = 3;
  static const double clue2UnlockDistanceRatio = 0.6;  // 60% du rayon restant
  static const double clue3UnlockDistanceMeters = 400.0; // distance fixe : 400m de la cible
}
