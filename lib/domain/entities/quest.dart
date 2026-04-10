import 'place.dart';
import 'clue.dart';

enum QuestStatus { active, completed, abandoned }

class Quest {
  final String id;
  final Place targetPlace;
  final List<Clue> clues;
  final DateTime date;
  final int radiusMeters;
  final int creditsCost;
  final QuestStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? userTag;

  const Quest({
    required this.id,
    required this.targetPlace,
    required this.clues,
    required this.date,
    required this.radiusMeters,
    required this.creditsCost,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.userTag,
  });

  Quest copyWith({
    List<Clue>? clues,
    QuestStatus? status,
    DateTime? completedAt,
    String? userTag,
  }) =>
      Quest(
        id: id,
        targetPlace: targetPlace,
        clues: clues ?? this.clues,
        date: date,
        radiusMeters: radiusMeters,
        creditsCost: creditsCost,
        status: status ?? this.status,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
        userTag: userTag ?? this.userTag,
      );
}
