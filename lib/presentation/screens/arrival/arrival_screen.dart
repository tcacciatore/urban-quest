import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/quest_providers.dart';
import '../../../domain/entities/place.dart';
import '../../../theme/app_colors.dart';

// Tags disponibles — à enrichir plus tard
const _availableTags = [
  '🌿 Nature', '🏛️ Histoire', '🎨 Art', '🛋️ Détente',
  '👀 Panorama', '🔇 Calme', '🎶 Animé', '💧 Eau',
  '🏘️ Quartier', '✨ Caché',
];

class ArrivalScreen extends ConsumerStatefulWidget {
  final Place place;

  const ArrivalScreen({super.key, required this.place});

  @override
  ConsumerState<ArrivalScreen> createState() => _ArrivalScreenState();
}

class _ArrivalScreenState extends ConsumerState<ArrivalScreen> {
  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // En-tête succès
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.terraLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.terra, width: 2),
                      ),
                      child: const Icon(Icons.check, color: AppColors.terra, size: 40),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Vous y êtes !',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.place.name,
                      style: const TextStyle(fontSize: 16, color: AppColors.sand),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              const Text(
                'Comment tu décrirais cet endroit ?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choisis un tag — il sera associé à ce lieu.',
                style: TextStyle(fontSize: 13, color: AppColors.sand),
              ),

              const SizedBox(height: 16),

              // Grille de tags
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableTags.map((tag) {
                  final isSelected = _selectedTag == tag;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTag = tag),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.terraLight : AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.terra : AppColors.sandLight,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: isSelected ? AppColors.terra : AppColors.sand,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const Spacer(),

              ElevatedButton(
                onPressed: _selectedTag != null ? () => _complete(context) : null,
                child: const Text('Terminer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _complete(BuildContext context) {
    ref.read(questProvider.notifier).completeQuest(_selectedTag!);
    // Retour à la carte
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
