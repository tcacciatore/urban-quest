import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../providers/missions_provider.dart';
import '../../../providers/claimed_missions_provider.dart';
import '../../../providers/city_rewards_provider.dart';
import '../../../providers/trophy_providers.dart';
import '../../../providers/city_fog_provider.dart';
import '../../../../domain/entities/city.dart';
import '../../../../domain/entities/trophy.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_text.dart';

// ─── Feuille Quêtes ───────────────────────────────────────────────────────────

class QuestSheet extends ConsumerWidget {
  final VoidCallback? onStartHunt;
  const QuestSheet({super.key, this.onStartHunt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions = ref.watch(missionsProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE4ED),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                const Text('Quêtes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A2840))),
                const Spacer(),
                // Bouton lancer une chasse
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    onStartHunt?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('⭐', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 5),
                        Text(
                          'Lancer',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Liste des missions
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            itemCount: missions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _MissionTile(mission: missions[i]),
          ),
        ],
      ),
    );
  }
}

class _MissionTile extends ConsumerWidget {
  final Mission mission;
  const _MissionTile({required this.mission});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild quand l'état des missions réclamées change
    ref.watch(claimedMissionsProvider);
    final isClaimed = ref.read(claimedMissionsProvider.notifier).isClaimed(mission);
    final done = mission.isCompleted;
    final claimable = done && !isClaimed;

    return GestureDetector(
      onTap: claimable
          ? () async {
              await ref.read(claimedMissionsProvider.notifier).claim(mission, ref);
              HapticFeedback.heavyImpact();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isClaimed
              ? const Color(0xFFF7F9FC)
              : done
                  ? const Color(0xFFFFFBEB)
                  : const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isClaimed
                ? const Color(0xFFE2EAF4)
                : done
                    ? const Color(0xFFFFB800).withValues(alpha: 0.6)
                    : const Color(0xFFE2EAF4),
          ),
        ),
        child: Row(
          children: [
            // Emoji
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isClaimed
                    ? const Color(0xFFEEF4FF)
                    : done
                        ? const Color(0xFFFFB800).withValues(alpha: 0.15)
                        : const Color(0xFFEEF4FF),
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(mission.emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),

            // Texte + barre
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mission.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isClaimed
                          ? const Color(0xFF8FA8C0)
                          : const Color(0xFF1A2840),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${mission.current} / ${mission.target}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8FA8C0), fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: mission.progress,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE2EAF4),
                      valueColor: AlwaysStoppedAnimation(
                        isClaimed
                            ? const Color(0xFFB0BEC5)
                            : done
                                ? const Color(0xFFFFB800)
                                : const Color(0xFF3A8EE6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Bouton réclamer / réclamé / en cours
            if (isClaimed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2EAF4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '✓ Réclamé',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8FA8C0)),
                ),
              )
            else if (done)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${mission.rewardCoins} 🪙',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${mission.rewardCoins} 🪙',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFFB800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Feuille Trophées ─────────────────────────────────────────────────────────

class TrophySheet extends ConsumerWidget {
  const TrophySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trophiesAsync = ref.watch(trophyProvider);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFDDE4ED), borderRadius: BorderRadius.circular(2))),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Trophées', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A2840))),
            ),
          ),
          Flexible(
            child: trophiesAsync.when(
              data: (trophies) => trophies.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucun trophée encore.\nComplète des chasses pour en gagner !',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8FA8C0), fontSize: 14)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: trophies.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _TrophyTile(trophy: trophies[i]),
                    ),
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrophyTile extends StatelessWidget {
  final EarnedTrophy trophy;
  const _TrophyTile({required this.trophy});

  @override
  Widget build(BuildContext context) {
    final d = trophy.earnedAt;
    final date = '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(trophy.definition.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trophy.definition.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A2840))),
              Text(trophy.definition.description, style: const TextStyle(fontSize: 12, color: Color(0xFF8FA8C0))),
            ]),
          ),
          Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF8FA8C0))),
        ],
      ),
    );
  }
}

// ─── Feuille Progression ──────────────────────────────────────────────────────

class ProgressionSheet extends ConsumerWidget {
  /// Appelé quand l'utilisateur sélectionne une ville → ferme le sheet et recentre la carte.
  final void Function(String cityId, LatLng center)? onCitySelected;

  const ProgressionSheet({super.key, this.onCitySelected});

  LatLng _centroid(List<LatLng> polygon) {
    final lat = polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final lon = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
    return LatLng(lat, lon);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fog = ref.watch(cityFogProvider);

    final cities = fog.cities.values
        .where((c) => c.walkedPoints.isNotEmpty || c.id == fog.currentCityId)
        .toList()
      ..sort((a, b) {
        final aCurrent = a.id == fog.currentCityId;
        final bCurrent = b.id == fog.currentCityId;
        if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
        if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? 1 : -1;
        return b.revealedRatio.compareTo(a.revealedRatio);
      });

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFDDE4ED), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Progression', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A2840))),
            ),
          ),
          Flexible(
            child: fog.isLoading && cities.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                : cities.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucune ville encore.\nCommence à marcher !',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8FA8C0), fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: cities.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final city = cities[i];
                          return _CityProgressCard(
                            city: city,
                            isCurrent: city.id == fog.currentCityId,
                            onTap: onCitySelected == null || city.polygon.isEmpty
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    onCitySelected!(city.id, _centroid(city.polygon));
                                  },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CityProgressCard extends ConsumerWidget {
  final City city;
  final bool isCurrent;

  final VoidCallback? onTap;

  const _CityProgressCard({
    required this.city,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnlocked = city.isUnlocked;
    final ratio      = (city.revealedRatio / City.requiredRatio).clamp(0.0, 1.0);
    final percent    = (city.revealedRatio * 100).round();

    ref.watch(cityRewardsProvider);
    final rewardClaimed = ref.read(cityRewardsProvider.notifier).isClaimed(city.id);
    final canClaim = isUnlocked && !rewardClaimed;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnlocked
              ? AppColors.forestLight
              : isCurrent
                  ? AppColors.white
                  : const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnlocked
                ? AppColors.forest.withValues(alpha: 0.30)
                : isCurrent
                    ? AppColors.terra.withValues(alpha: 0.40)
                    : const Color(0xFFE2EAF4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isUnlocked ? '🏙️' : isCurrent ? '📍' : '🗺️',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    city.name,
                    style: AppText.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isUnlocked ? AppColors.forest : const Color(0xFF1A2840),
                    ),
                  ),
                ),
                if (percent >= 100)
                  const Text('✅', style: TextStyle(fontSize: 16))
                else
                  Text(
                    '$percent %',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isUnlocked ? AppColors.forest : AppColors.terra,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Barre de progression (tappable si récompense disponible) ────
            GestureDetector(
              onTap: canClaim
                  ? () => ref.read(cityRewardsProvider.notifier).claim(city.id, ref)
                  : null,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: canClaim ? 32 : 6,
                      backgroundColor: const Color(0xFFE2EAF4),
                      valueColor: AlwaysStoppedAnimation(
                        isUnlocked ? AppColors.forest : AppColors.terra,
                      ),
                    ),
                  ),
                  if (canClaim)
                    Positioned.fill(
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🪙', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              'Toucher pour récupérer ${CityRewardsNotifier.rewardAmount} crédits',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (rewardClaimed && isUnlocked)
                    Positioned.fill(
                      child: Center(
                        child: Text(
                          '✓ Récompense réclamée',
                          style: TextStyle(
                            color: AppColors.forest,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
