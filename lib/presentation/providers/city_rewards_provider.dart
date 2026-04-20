import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wallet_providers.dart';

/// Stocke les IDs de villes dont la récompense de déverrouillage a été réclamée.
class CityRewardsNotifier extends Notifier<Set<String>> {
  static const _prefsKey = 'city_unlock_rewards_v1';
  static const rewardAmount = 2000;

  @override
  Set<String> build() {
    _load();
    return {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final list = jsonDecode(raw) as List<dynamic>;
    state = list.cast<String>().toSet();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toList()));
  }

  bool isClaimed(String cityId) => state.contains(cityId);

  Future<void> claim(String cityId, WidgetRef ref) async {
    if (isClaimed(cityId)) return;
    ref.read(walletProvider.notifier).addCredits(rewardAmount);
    state = {...state, cityId};
    await _save();
    HapticFeedback.heavyImpact();
  }
}

final cityRewardsProvider =
    NotifierProvider<CityRewardsNotifier, Set<String>>(CityRewardsNotifier.new);
