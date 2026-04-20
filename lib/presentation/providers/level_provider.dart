import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'wallet_providers.dart';

class LevelInfo {
  final int level;
  final int xp;
  final int xpNeeded;

  const LevelInfo({required this.level, required this.xp, required this.xpNeeded});

  double get progress => xpNeeded > 0 ? (xp / xpNeeded).clamp(0.0, 1.0) : 1.0;
}

// Seuil pour atteindre le niveau n : n*(n-1)*100 pas
int _threshold(int level) => level * (level - 1) * 100;

final levelProvider = Provider<LevelInfo>((ref) {
  final steps = ref.watch(stepCountProvider);
  int level = 1;
  while (_threshold(level + 1) <= steps) {
    level++;
  }
  return LevelInfo(
    level: level,
    xp: steps - _threshold(level),
    xpNeeded: _threshold(level + 1) - _threshold(level),
  );
});
