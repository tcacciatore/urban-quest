import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/wallet_providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_text.dart';

class RadiusPickerSheet extends ConsumerStatefulWidget {
  const RadiusPickerSheet({super.key});

  @override
  ConsumerState<RadiusPickerSheet> createState() => _RadiusPickerSheetState();
}

class _RadiusPickerSheetState extends ConsumerState<RadiusPickerSheet> {
  int _selectedRadius = 1000;
  String? _selectedDirection; // null = aléatoire

  static const _labels = {
    500: ('500m', '~5 min'),
    1000: ('1 km', '~12 min'),
    2000: ('2 km', '~25 min'),
  };

  // Grille 3×3 : null = centre (aléatoire)
  static const _compassGrid = [
    ['NO', 'N', 'NE'],
    ['O', null, 'E'],
    ['SO', 'S', 'SE'],
  ];

  Widget _buildCompassButton(String? dir) {
    final isCenter = dir == null;
    final isSelected = isCenter ? _selectedDirection == null : _selectedDirection == dir;

    return GestureDetector(
      onTap: () => setState(() => _selectedDirection = dir),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 52,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.terra.withValues(alpha: 0.12) : AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.terra : AppColors.sandLight,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            isCenter ? '🎲' : dir,
            style: TextStyle(
              fontSize: isCenter ? 20 : 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppColors.terra : AppColors.sand,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final cost = AppConstants.radiusCostMap[_selectedRadius] ?? _selectedRadius;
    final canAfford = AppConstants.testMode || wallet.hasEnoughCredits(cost);
    final hasQuests = AppConstants.testMode || wallet.hasQuestsRemaining;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poignée
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

          // ── Rayon ──────────────────────────────────────────────────────────
          Text('Jusqu\'où veux-tu aller ?', style: AppText.sectionTitle),
          const SizedBox(height: 14),

          ...AppConstants.availableRadii.map((radius) {
            final (label, duration) = _labels[radius]!;
            final radiusCost = AppConstants.radiusCostMap[radius] ?? radius;
            final isSelected = _selectedRadius == radius;
            final affordable = AppConstants.testMode || wallet.hasEnoughCredits(radiusCost);

            return GestureDetector(
              onTap: affordable ? () => setState(() => _selectedRadius = radius) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.terraLight : AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppColors.terra : AppColors.sandLight,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? AppColors.terra : AppColors.sand,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: AppText.metric.copyWith(
                              fontWeight: FontWeight.w600,
                              color: affordable ? AppColors.ink : AppColors.sand,
                            ),
                          ),
                          Text(
                            duration,
                            style: AppText.label.copyWith(letterSpacing: 0),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: affordable ? AppColors.forestLight : AppColors.sandLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$radiusCost crédits',
                        style: AppText.label.copyWith(
                          letterSpacing: 0,
                          fontWeight: FontWeight.bold,
                          color: affordable ? AppColors.forest : AppColors.sand,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // ── Direction ──────────────────────────────────────────────────────
          Text('Dans quelle direction ?', style: AppText.sectionTitle),
          const SizedBox(height: 4),
          Text('🎲 = aléatoire', style: AppText.label.copyWith(letterSpacing: 0)),
          const SizedBox(height: 12),

          Center(
            child: Column(
              children: _compassGrid.map((row) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: row.map(_buildCompassButton).toList(),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),

          // ── Solde + bouton ─────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ton solde :', style: AppText.label.copyWith(letterSpacing: 0)),
              Text(
                '${wallet.credits} crédits',
                style: AppText.metric.copyWith(color: AppColors.forest, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (!hasQuests)
            Center(
              child: Text(
                'Limite de 3 chasses par jour atteinte.\nReviens demain !',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: AppColors.terra),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canAfford
                    ? () => Navigator.of(context).pop(
                          (radius: _selectedRadius, direction: _selectedDirection),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAfford ? AppColors.ink : AppColors.sandLight,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  canAfford ? 'C\'est parti !' : 'Pas assez de crédits',
                  style: AppText.metric.copyWith(
                    color: canAfford ? AppColors.parchment : AppColors.sand,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
