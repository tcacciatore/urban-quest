class Wallet {
  final int credits;
  final int questsUsedToday;
  final DateTime lastResetDate;

  const Wallet({
    required this.credits,
    required this.questsUsedToday,
    required this.lastResetDate,
  });

  bool get canAfford => credits >= 0;
  bool hasEnoughCredits(int cost) => credits >= cost;

  int get questsRemainingToday => 3 - questsUsedToday;
  bool get hasQuestsRemaining => questsUsedToday < 3;

  Wallet copyWith({
    int? credits,
    int? questsUsedToday,
    DateTime? lastResetDate,
  }) =>
      Wallet(
        credits: credits ?? this.credits,
        questsUsedToday: questsUsedToday ?? this.questsUsedToday,
        lastResetDate: lastResetDate ?? this.lastResetDate,
      );
}
