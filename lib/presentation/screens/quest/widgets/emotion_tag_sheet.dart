import 'package:flutter/material.dart';
import '../../../../core/constants/emotion_tags.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_text.dart';

class EmotionTagSheet extends StatefulWidget {
  final EmotionTag? suggestedTag;

  const EmotionTagSheet({super.key, this.suggestedTag});

  @override
  State<EmotionTagSheet> createState() => _EmotionTagSheetState();
}

class _EmotionTagSheetState extends State<EmotionTagSheet> {
  EmotionTag? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.suggestedTag;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 20, 24,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.sandLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Cet endroit, c\'est quoi pour toi ?',
            textAlign: TextAlign.center,
            style: AppText.sectionTitle,
          ),

          if (widget.suggestedTag != null) ...[
            const SizedBox(height: 6),
            Text(
              'Suggestion basée sur le lieu : ${widget.suggestedTag!.emoji}',
              style: AppText.label.copyWith(letterSpacing: 0),
            ),
          ],

          const SizedBox(height: 24),

          // Grille 3 colonnes
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
            ),
            itemCount: emotionTags.length,
            itemBuilder: (_, i) {
              final tag = emotionTags[i];
              final isSelected = _selected?.label == tag.label;
              final isSuggested = widget.suggestedTag?.label == tag.label;
              return _EmotionPill(
                tag: tag,
                isSelected: isSelected,
                isSuggested: isSuggested && !isSelected,
                onTap: () => setState(() => _selected = tag),
              );
            },
          ),

          const SizedBox(height: 20),

          // Bouton valider (apparaît après sélection)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, child: child),
            ),
            child: _selected != null
                ? SizedBox(
                    key: const ValueKey('btn'),
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: Text(
                        '${_selected!.emoji}  ${_selected!.label} — Valider',
                        style: AppText.metric.copyWith(
                          color: AppColors.parchment,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(key: ValueKey('empty')),
          ),
        ],
      ),
    );
  }
}

class _EmotionPill extends StatelessWidget {
  final EmotionTag tag;
  final bool isSelected;
  final bool isSuggested;
  final VoidCallback onTap;

  const _EmotionPill({
    required this.tag,
    required this.isSelected,
    required this.isSuggested,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isSelected ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.terraLight
                : isSuggested
                    ? AppColors.forestLight
                    : AppColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.terra
                  : isSuggested
                      ? AppColors.forest.withValues(alpha: 0.4)
                      : AppColors.sandLight,
              width: isSelected ? 1.8 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '${tag.emoji} ${tag.label}',
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(
                letterSpacing: 0,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.terra : AppColors.ink.withValues(alpha: 0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
