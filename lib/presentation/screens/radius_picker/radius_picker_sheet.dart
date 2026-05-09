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
    500:  ('🐌 Balade',      '500 m · ~5 min'),
    1000: ('🦊 Exploration', '1 km · ~12 min'),
    2000: ('🐆 Sprint',      '2 km · ~25 min'),
  };

  // Grille 3×3 : null = centre (aléatoire)
  static const _compassGrid = [
    ['NO', 'N', 'NE'],
    ['O',  null, 'E'],
    ['SO', 'S', 'SE'],
  ];

  // Flèches Unicode pour chaque direction
  static const _arrows = {
    'NO': '↖', 'N': '↑', 'NE': '↗',
    'O':  '←',            'E':  '→',
    'SO': '↙', 'S': '↓', 'SE': '↘',
  };

  Widget _buildCompassButton(String? dir) {
    final isCenter = dir == null;
    final isSelected = isCenter ? _selectedDirection == null : _selectedDirection == dir;

    return GestureDetector(
      onTap: () => setState(() => _selectedDirection = dir),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        height: 56,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.terra.withValues(alpha: 0.12) : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.terra : AppColors.sandLight,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.terra.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Center(
          child: isCenter
              ? const Text('🎲', style: TextStyle(fontSize: 22))
              : Text(
                  _arrows[dir]!,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? AppColors.terra : AppColors.sand,
                    height: 1,
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

          // ── Rayon ────────────────────────────────────────────────────────────
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
                        AppConstants.testMode ? 'Gratuit' : '$radiusCost crédits',
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

          // ── Direction ────────────────────────────────────────────────────────
          Text('Dans quelle direction ?', style: AppText.sectionTitle),
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

          const SizedBox(height: 24),

          // ── Bouton CTA ───────────────────────────────────────────────────────
          if (!hasQuests)
            Center(
              child: Text(
                'Limite de 3 chasses par jour atteinte.\nReviens demain !',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: AppColors.terra),
              ),
            )
          else
            _CtaButton(
              canAfford: canAfford,
              onTap: canAfford
                  ? () => Navigator.of(context).pop(
                        (radius: _selectedRadius, direction: _selectedDirection),
                      )
                  : null,
            ),
        ],
      ),
    );
  }
}

// ─── Bouton CTA gradient ──────────────────────────────────────────────────────

class _CtaButton extends StatelessWidget {
  final bool canAfford;
  final VoidCallback? onTap;

  const _CtaButton({required this.canAfford, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: canAfford
              ? const LinearGradient(
                  colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: canAfford ? null : AppColors.sandLight,
          borderRadius: BorderRadius.circular(16),
          boxShadow: canAfford
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.40),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          canAfford ? 'C\'est parti !' : 'Pas assez de crédits',
          textAlign: TextAlign.center,
          style: AppText.metric.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: canAfford ? Colors.white : AppColors.sand,
          ),
        ),
      ),
    );
  }
}
