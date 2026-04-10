import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/wallet.dart';
import '../../core/constants/app_constants.dart';
import '../../services/pedometer_service.dart';
import '../../services/notification_service.dart';

final pedometerServiceProvider = Provider<PedometerService>((ref) => PedometerService());

class WalletNotifier extends Notifier<Wallet> {
  static const _keyCredits = 'wallet_credits';
  static const _keyQuestsUsed = 'wallet_quests_used';
  static const _keyLastReset = 'wallet_last_reset';
  static const _keyNotifSent = 'wallet_notif_sent'; // évite de respammer

  @override
  Wallet build() {
    _init();
    _listenToPedometer();
    return Wallet(
      credits: AppConstants.initialCredits,
      questsUsedToday: 0,
      lastResetDate: DateTime.now(),
    );
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final credits = prefs.getInt(_keyCredits) ?? AppConstants.initialCredits;
    final questsUsed = prefs.getInt(_keyQuestsUsed) ?? 0;
    final lastResetStr = prefs.getString(_keyLastReset);
    final lastReset = lastResetStr != null ? DateTime.parse(lastResetStr) : DateTime.now();

    final now = DateTime.now();
    final isNewDay = now.year != lastReset.year ||
        now.month != lastReset.month ||
        now.day != lastReset.day;

    state = Wallet(
      credits: credits,
      questsUsedToday: isNewDay ? 0 : questsUsed,
      lastResetDate: isNewDay ? now : lastReset,
    );

    if (isNewDay) {
      await prefs.setInt(_keyQuestsUsed, 0);
      await prefs.setString(_keyLastReset, now.toIso8601String());
      // Réinitialise le flag de notification pour la nouvelle journée
      await prefs.setBool(_keyNotifSent, false);
    }
  }

  void _listenToPedometer() {
    final service = ref.read(pedometerServiceProvider);
    service.stepCountStream().listen((totalSteps) {
      _syncCreditsFromSteps(totalSteps);
    });
  }

  /// Crédits = total des pas natifs du téléphone
  Future<void> _syncCreditsFromSteps(int totalSteps) async {
    final prefs = await SharedPreferences.getInstance();
    final previousCredits = state.credits;

    state = state.copyWith(credits: totalSteps);
    await prefs.setInt(_keyCredits, totalSteps);

    // Notification quand on franchit les 5000 crédits pour la première fois
    final notifAlreadySent = prefs.getBool(_keyNotifSent) ?? false;
    if (!notifAlreadySent &&
        previousCredits < AppConstants.questCost &&
        state.credits >= AppConstants.questCost) {
      await prefs.setBool(_keyNotifSent, true);
      await NotificationService.showReadyToQuest();
    }
  }

  void addCredits(int amount) async {
    state = state.copyWith(credits: state.credits + amount);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCredits, state.credits);
  }

  Future<bool> spendCredits(int amount) async {
    if (AppConstants.testMode) return true; // pas de limite en mode test
    if (!state.hasQuestsRemaining) return false;
    if (!state.hasEnoughCredits(amount)) return false;

    state = state.copyWith(
      credits: state.credits - amount,
      questsUsedToday: state.questsUsedToday + 1,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCredits, state.credits);
    await prefs.setInt(_keyQuestsUsed, state.questsUsedToday);

    // Réinitialise le flag pour re-notifier quand les crédits remontent
    await prefs.setBool(_keyNotifSent, false);
    return true;
  }
}

final walletProvider = NotifierProvider<WalletNotifier, Wallet>(WalletNotifier.new);

/// Compteur de pas affiché dans le header (total natif du téléphone)
class StepCountNotifier extends Notifier<int> {
  @override
  int build() {
    final service = ref.read(pedometerServiceProvider);
    service.stepCountStream().listen((totalSteps) {
      state = totalSteps;
    });
    return 0;
  }
}

final stepCountProvider = NotifierProvider<StepCountNotifier, int>(StepCountNotifier.new);
