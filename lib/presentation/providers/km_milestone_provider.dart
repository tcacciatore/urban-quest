import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'walker_profile_provider.dart';

/// Paliers km à célébrer
const List<double> kKmMilestones = [1, 5, 10, 25, 50, 100, 200, 300];

/// Messages de flaveur par palier (clés = km entiers)
const Map<int, String> kMilestoneMessages = {
  1:   'Premier kilomètre dans les pattes !',
  5:   'La ville commence à se dévoiler.',
  10:  'Tu connais déjà des rues que peu voient.',
  25:  'Un quart de siècle de km — pas mal.',
  50:  'La moitié de cent. Tu es inarrêtable.',
  100: 'Cent kilomètres. La légende commence.',
  200: 'Deux cents km de bitume dompté.',
  300: 'Trois cents km. Es-tu même réel ?',
};

// ─── Persistance du dernier palier affiché ────────────────────────────────────

class LastShownMilestoneNotifier extends Notifier<double> {
  static const _key = 'km_milestone_last_shown';

  @override
  double build() {
    _load();
    return 0.0;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getDouble(_key) ?? 0.0;
    if (val != state) state = val;
  }

  Future<void> acknowledge(double milestone) async {
    state = milestone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, milestone);
  }
}

final lastShownMilestoneProvider =
    NotifierProvider<LastShownMilestoneNotifier, double>(
  LastShownMilestoneNotifier.new,
);

// ─── Palier en attente d'affichage ───────────────────────────────────────────

/// Retourne le plus haut palier km franchi mais pas encore montré, ou null.
final pendingKmMilestoneProvider = Provider<double?>((ref) {
  final totalKm  = ref.watch(walkerProfileProvider).totalKm;
  final lastShown = ref.watch(lastShownMilestoneProvider);

  for (final m in kKmMilestones.reversed) {
    if (totalKm >= m && m > lastShown) return m;
  }
  return null;
});
