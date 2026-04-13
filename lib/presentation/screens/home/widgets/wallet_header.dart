import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/wallet_providers.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_text.dart';

class WalletHeader extends ConsumerWidget {
  const WalletHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final steps = ref.watch(stepCountProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(60, 10, 14, 0),
        child: Row(
          children: [
            _Chip(
              icon: Icons.currency_exchange,
              label: '${wallet.credits}',
              iconColor: AppColors.terra,
            ),
            const SizedBox(width: 6),
            _Chip(
              icon: Icons.flag_outlined,
              label: '${wallet.questsRemainingToday}/3',
              iconColor: wallet.hasQuestsRemaining ? AppColors.forest : AppColors.terra,
            ),
            const Spacer(),
            _StepsChip(steps: steps),
          ],
        ),
      ),
    );
  }
}

class _StepsChip extends StatelessWidget {
  final int steps;
  const _StepsChip({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.sandLight, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.14),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 15, color: AppColors.terra),
          const SizedBox(width: 5),
          Text(
            '$steps',
            style: AppText.metric.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'pas',
            style: AppText.label.copyWith(
              fontSize: 10,
              color: AppColors.sand,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _Chip({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.sandLight, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.14),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.metric.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
