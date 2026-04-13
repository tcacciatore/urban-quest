import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PedometerService {
  static const _keyDailyBaseline = 'pedometer_daily_baseline';
  static const _keyBaselineDate   = 'pedometer_baseline_date';

  /// Stream partagé (broadcast) — un seul abonnement au capteur, plusieurs écouteurs.
  Stream<int>? _sharedStream;

  Future<void> requestPermissions() async {}

  /// Stream des pas du jour (réinitialise à minuit).
  /// Un seul abonnement actif quelle que soit le nombre d'écouteurs.
  Stream<int> stepCountStream() {
    _sharedStream ??= Pedometer.stepCountStream
        .asyncMap(_toDailySteps)
        .distinct()
        .asBroadcastStream();
    return _sharedStream!;
  }

  Future<int> _toDailySteps(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final savedDate = prefs.getString(_keyBaselineDate);

    // Nouveau jour ou premier lancement → nouvelle baseline
    if (savedDate != today) {
      await prefs.setInt(_keyDailyBaseline, event.steps);
      await prefs.setString(_keyBaselineDate, today);
      return 0;
    }

    final baseline = prefs.getInt(_keyDailyBaseline) ?? event.steps;

    // Reboot détecté (compteur remis à zéro par l'OS)
    if (event.steps < baseline) {
      await prefs.setInt(_keyDailyBaseline, event.steps);
      await prefs.setString(_keyBaselineDate, today);
      return 0;
    }

    return event.steps - baseline;
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
