import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/constants/emotion_tags.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_text.dart';

/// Retourné par le sheet quand l'utilisateur valide.
typedef PinResult = ({String emoji, String label, String? photoPath});

class PersonalPinSheet extends StatefulWidget {
  const PersonalPinSheet({super.key});

  @override
  State<PersonalPinSheet> createState() => _PersonalPinSheetState();
}

class _PersonalPinSheetState extends State<PersonalPinSheet> {
  EmotionTag? _selected;
  String? _photoPath;
  bool _takingPhoto = false;

  Future<void> _takePhoto() async {
    setState(() => _takingPhoto = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (photo != null && mounted) {
        final docsDir = await getApplicationDocumentsDirectory();
        final fileName = 'pin_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final fullPath = '${docsDir.path}/$fileName';
        // readAsBytes() est plus fiable que File.copy() sur iOS pour les
        // fichiers temporaires retournés par image_picker.
        final bytes = await photo.readAsBytes();
        await File(fullPath).writeAsBytes(bytes);
        // On stocke le chemin complet pour l'aperçu dans le sheet ;
        // PersonalPin.toJson() extrait le basename via _toFilename().
        if (mounted) setState(() => _photoPath = fullPath);
      }
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.sandLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Qu\'est-ce que tu ressens ici ?',
            textAlign: TextAlign.center,
            style: AppText.sectionTitle,
          ),
          const SizedBox(height: 20),

          // ── Grille émotions ───────────────────────────────────────────────
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
              return GestureDetector(
                onTap: () => setState(() => _selected = tag),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.terraLight : AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.terra : AppColors.sandLight,
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
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Photo ─────────────────────────────────────────────────────────
          GestureDetector(
            onTap: _takingPhoto ? null : _takePhoto,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: _photoPath != null
                    ? AppColors.forestLight
                    : AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _photoPath != null
                      ? AppColors.forest.withValues(alpha: 0.4)
                      : AppColors.sandLight,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_photoPath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(_photoPath!),
                        width: 32, height: 32,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Photo prise ✓',
                      style: AppText.label.copyWith(
                        letterSpacing: 0,
                        color: AppColors.forest,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else ...[
                    Icon(
                      _takingPhoto ? Icons.hourglass_empty : Icons.camera_alt_outlined,
                      size: 18,
                      color: AppColors.sand,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _takingPhoto ? 'Ouverture...' : '📸 Ajouter une photo',
                      style: AppText.label.copyWith(
                        letterSpacing: 0,
                        color: AppColors.sand,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Bouton valider ────────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, child: child),
            ),
            child: _selected != null
                ? SizedBox(
                    key: const ValueKey('btn'),
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop<PinResult>((
                        emoji: _selected!.emoji,
                        label: _selected!.label,
                        photoPath: _photoPath,
                      )),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          '${_selected!.emoji}  Marquer cet endroit',
                          textAlign: TextAlign.center,
                          style: AppText.metric.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
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
