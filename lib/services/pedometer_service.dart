import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PedometerService {
  static const _keyDailyBaseline = 'pedometer_daily_baseline';
  static const _keyBaselineDate = 'pedometer_baseline_date';

  Future<void> requestPermissions() async {
    // La permission est demandée automatiquement au premier accès au stream
  }

  /// Stream des pas du jour (réinitialise à minuit).
  Stream<int> stepCountStream() {
    return Pedometer.stepCountStream.asyncMap((event) async {
      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      final savedDate = prefs.getString(_keyBaselineDate);

      // Nouveau jour ou premier lancement → réinitialise la baseline
      if (savedDate != today) {
        await prefs.setInt(_keyDailyBaseline, event.steps);
        await prefs.setString(_keyBaselineDate, today);
        return 0;
      }

      final baseline = prefs.getInt(_keyDailyBaseline) ?? event.steps;

      // Reboot détecté (steps < baseline) → réinitialise
      if (event.steps < baseline) {
        await prefs.setInt(_keyDailyBaseline, 0);
        return event.steps;
      }

      return event.steps - baseline;
    }).distinct();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}
