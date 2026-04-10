import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/quest.dart';
import '../../domain/entities/trophy.dart';

class TrophyNotifier extends AsyncNotifier<List<EarnedTrophy>> {
  static const _keyEarned = 'earned_trophies';
  static const _keyTotalCompleted = 'total_quests_completed';
  static const _keyTodayCompleted = 'today_quests_completed';
  static const _keyTodayDate = 'today_quests_date';

  @override
  Future<List<EarnedTrophy>> build() => _loadEarned();

  Future<List<EarnedTrophy>> _loadEarned() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_keyEarned) ?? [];
    return raw
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .map((map) {
          final def = TrophyDefinition.all
              .where((d) => d.id == map['id'] as String)
              .firstOrNull;
          if (def == null) return null;
          return EarnedTrophy(
            definition: def,
            earnedAt: DateTime.parse(map['earnedAt'] as String),
          );
        })
        .whereType<EarnedTrophy>()
        .toList();
  }

  /// Évalue les trophées gagnés après une chasse réussie.
  /// Retourne uniquement les nouveaux trophées débloqués.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEarned);
    await prefs.remove(_keyTotalCompleted);
    await prefs.remove(_keyTodayCompleted);
    await prefs.remove(_keyTodayDate);
    state = const AsyncData([]);
  }

  Future<List<EarnedTrophy>> evaluateQuest(Quest quest) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // Compteur total
    final total = (prefs.getInt(_keyTotalCompleted) ?? 0) + 1;
    await prefs.setInt(_keyTotalCompleted, total);

    // Compteur du jour
    final today = '${now.year}-${now.month}-${now.day}';
    final savedDate = prefs.getString(_keyTodayDate);
    final todayCount = savedDate == today
        ? (prefs.getInt(_keyTodayCompleted) ?? 0) + 1
        : 1;
    await prefs.setInt(_keyTodayCompleted, todayCount);
    await prefs.setString(_keyTodayDate, today);

    final alreadyEarned = await _loadEarned();
    final alreadyIds = alreadyEarned.map((t) => t.definition.id).toSet();

    final duration = quest.completedAt != null
        ? quest.completedAt!.difference(quest.startedAt)
        : const Duration(hours: 99);

    final newTrophies = <EarnedTrophy>[];

    void check(String id, bool condition) {
      if (condition && !alreadyIds.contains(id)) {
        final def = TrophyDefinition.all.firstWhere((d) => d.id == id);
        newTrophies.add(EarnedTrophy(definition: def, earnedAt: now));
      }
    }

    check('first_quest', total == 1);
    check('sprint_15', duration.inMinutes < 15);
    check('sprint_30', duration.inMinutes < 30);
    check('explorer_5', total >= 5);
    check('legend_10', total >= 10);
    check('big_radius', quest.radiusMeters >= 2000);
    check('early_bird', now.hour < 8);
    check('night_owl', now.hour >= 21);
    check('weekend', now.weekday == DateTime.saturday || now.weekday == DateTime.sunday);
    check('hot_streak', todayCount >= 3);

    if (newTrophies.isNotEmpty) {
      final all = [...alreadyEarned, ...newTrophies];
      final raw = all
          .map((t) => jsonEncode({
                'id': t.definition.id,
                'earnedAt': t.earnedAt.toIso8601String(),
              }))
          .toList();
      await prefs.setStringList(_keyEarned, raw);
      state = AsyncData(all);
    }

    return newTrophies;
  }
}

final trophyProvider =
    AsyncNotifierProvider<TrophyNotifier, List<EarnedTrophy>>(TrophyNotifier.new);
