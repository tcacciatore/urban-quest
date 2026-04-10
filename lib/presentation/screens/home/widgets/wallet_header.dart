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
            _Chip(
              icon: Icons.directions_walk,
              label: '$steps pas',
              iconColor: AppColors.sand,
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.sandLight, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.metric.copyWith(fontSize: 12, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
