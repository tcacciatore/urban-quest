import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'missions_provider.dart';
import 'wallet_providers.dart';

/// Stocke les missions déjà réclamées.
/// Clé : missionId. Valeur : {"date": "YYYY-MM-DD", "target": N}
/// - Missions quotidiennes (daily_*) : expiration si date != aujourd'hui
/// - Missions de progression : re-claimable si target a augmenté
class ClaimedMissionsNotifier extends Notifier<Map<String, _ClaimRecord>> {
  static const _prefsKey = 'claimed_missions_v1';

  @override
  Map<String, _ClaimRecord> build() {
    _load();
    return {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    state = map.map((k, v) => MapEntry(k, _ClaimRecord.fromJson(v as Map<String, dynamic>)));
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(state.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Retourne true si la mission a déjà été réclamée (et n'est pas réinitialisée).
  bool isClaimed(Mission mission) {
    final record = state[mission.id];
    if (record == null) return false;
    if (mission.id.startsWith('daily_')) {
      return record.date == _today();
    }
    // Mission de progression : claimed si le target réclamé >= target actuel
    return record.target >= mission.target;
  }

  /// Réclame la mission et crédite le wallet.
  Future<void> claim(Mission mission, WidgetRef ref) async {
    if (!mission.isCompleted || isClaimed(mission)) return;

    // Crédite le wallet
    ref.read(walletProvider.notifier).addCredits(mission.rewardCoins);

    // Marque comme réclamée
    state = {
      ...state,
      mission.id: _ClaimRecord(date: _today(), target: mission.target),
    };
    await _save();
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

class _ClaimRecord {
  final String date;
  final int target;
  const _ClaimRecord({required this.date, required this.target});

  factory _ClaimRecord.fromJson(Map<String, dynamic> j) =>
      _ClaimRecord(date: j['date'] as String, target: j['target'] as int);

  Map<String, dynamic> toJson() => {'date': date, 'target': target};
}

final claimedMissionsProvider =
    NotifierProvider<ClaimedMissionsNotifier, Map<String, _ClaimRecord>>(
  ClaimedMissionsNotifier.new,
);
