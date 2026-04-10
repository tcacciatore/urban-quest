enum ClueType { text, direction, distance }

class Clue {
  final int index;
  final String text;
  final ClueType type;
  final bool isRevealed;

  const Clue({
    required this.index,
    required this.text,
    required this.type,
    this.isRevealed = false,
  });

  Clue copyWith({bool? isRevealed}) => Clue(
        index: index,
        text: text,
        type: type,
        isRevealed: isRevealed ?? this.isRevealed,
      );
}
