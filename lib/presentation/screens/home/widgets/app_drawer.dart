import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../providers/quest_history_providers.dart';
import '../../../providers/trophy_providers.dart';
import '../../../providers/route_providers.dart';
import '../../../providers/location_providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/trophy.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_text.dart';
import '../../../providers/city_fog_provider.dart';
import '../../../providers/poi_providers.dart';
import '../../../providers/rainbow_provider.dart';
import '../../../providers/claimed_missions_provider.dart';
import '../../../providers/walker_profile_provider.dart';
import '../../profile/walker_profile_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        title: Text('Réinitialiser ?', style: AppText.sectionTitle.copyWith(fontSize: 20)),
        content: Text(
          'Trophées, historique, brouillard de guerre, lieux visités, arc-en-ciel et quêtes seront effacés.',
          style: AppText.body.copyWith(color: AppColors.sand),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Annuler', style: TextStyle(color: AppColors.ink)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(trophyProvider.notifier).reset();
              await ref.read(questHistoryProvider.notifier).reset();
              await ref.read(cityFogProvider.notifier).reset();
              await ref.read(poiProvider.notifier).reset();
              await ref.read(rainbowProvider.notifier).reset();
              await ref.read(claimedMissionsProvider.notifier).reset();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text('Réinitialiser', style: TextStyle(color: AppColors.terra)),
          ),
        ],
      ),
    );
  }

  Future<void> _onQuestTapped(BuildContext context, WidgetRef ref, QuestHistoryEntry entry) async {
    if (!entry.hasCoordinates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordonnées non disponibles pour cette chasse.')),
      );
      return;
    }

    Navigator.of(context).pop(); // ferme le drawer

    // Priorité 1 : chemin réellement parcouru (sauvegardé depuis la v2)
    if (entry.hasWalkedPath) {
      ref.read(routeProvider.notifier).setWalkedPath(
            path: entry.walkedPath!,
            destination: LatLng(entry.latitude!, entry.longitude!),
            destinationName: entry.placeName,
            photoPath: entry.photoPath,
            emotionEmoji: entry.emotionEmoji,
          );
      return;
    }

    // Priorité 2 : recalcul OSRM depuis la position de départ mémorisée
    LatLng from;
    if (entry.hasStartCoordinates) {
      from = LatLng(entry.startLatitude!, entry.startLongitude!);
    } else {
      // Fallback (anciennes entrées) : position courante
      var currentPos = ref.read(positionStreamProvider).valueOrNull;
      currentPos ??= ref.read(initialPositionProvider).valueOrNull;
      currentPos ??= await ref.read(locationServiceProvider).getCurrentPosition();
      from = currentPos;
    }

    ref.read(routeProvider.notifier).loadRoute(
          from: from,
          to: LatLng(entry.latitude!, entry.longitude!),
          destinationName: entry.placeName,
          photoPath: entry.photoPath,
          emotionEmoji: entry.emotionEmoji,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync  = ref.watch(questHistoryProvider);
    final trophiesAsync = ref.watch(trophyProvider);
    final profile       = ref.watch(walkerProfileProvider);

    return Drawer(
      backgroundColor: AppColors.parchment,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Text('🗺️', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Text('Urban Quest', style: AppText.sectionTitle.copyWith(fontSize: 20)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.sandLight),
                      ),
                      child: Icon(Icons.close, color: AppColors.sand, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.sandLight, height: 1),
            const SizedBox(height: 8),

            // ── Carte profil ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WalkerProfileScreen(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        profile.animal.color.withValues(alpha: 0.15),
                        profile.animal.color.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: profile.animal.color.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        profile.animal.emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.animal.title,
                              style: AppText.body.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Voir mon profil →',
                              style: AppText.label.copyWith(
                                letterSpacing: 0.5,
                                color: profile.animal.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Divider(color: AppColors.sandLight, height: 1),
            const SizedBox(height: 4),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Bouton reset (testMode uniquement)
                  if (AppConstants.testMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: GestureDetector(
                        onTap: () => _confirmReset(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                          ),
                          child: const Center(
                            child: Text(
                              '🔧 Réinitialiser trophées & trajets',
                              style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // --- Dernières chasses ---
                  _SectionTile(
                    emoji: '🏁',
                    title: 'Dernières chasses',
                    children: historyAsync.when(
                      data: (entries) => entries.isEmpty
                          ? [_EmptyHint('Aucune chasse encore.\nLance-toi !')]
                          : entries
                              .map((e) => _QuestHistoryTile(
                                    entry: e,
                                    onTap: () => _onQuestTapped(context, ref, e),
                                  ))
                              .toList(),
                      loading: () => [const _LoadingHint()],
                      error: (_, __) => [_EmptyHint('Erreur de chargement')],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // --- Trophées ---
                  _SectionTile(
                    emoji: '🏆',
                    title: 'Trophées',
                    children: trophiesAsync.when(
                      data: (trophies) => trophies.isEmpty
                          ? [_EmptyHint('Aucun trophée encore.\nComplète une chasse !')]
                          : trophies
                              .map((t) => _TrophyTile(trophy: t))
                              .toList(),
                      loading: () => [const _LoadingHint()],
                      error: (_, __) => [_EmptyHint('Erreur de chargement')],
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

// ─── Section expansible ──────────────────────────────────────────────────────

class _SectionTile extends StatelessWidget {
  final String emoji;
  final String title;
  final List<Widget> children;

  const _SectionTile({
    required this.emoji,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: AppColors.terra.withValues(alpha: 0.08),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        collapsedIconColor: AppColors.sand,
        iconColor: AppColors.terra,
        leading: Text(emoji, style: const TextStyle(fontSize: 20)),
        title: Text(title, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
        children: children,
      ),
    );
  }
}

// ─── Tuile chasse ─────────────────────────────────────────────────────────────

class _QuestHistoryTile extends StatelessWidget {
  final QuestHistoryEntry entry;
  final VoidCallback? onTap;

  const _QuestHistoryTile({required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = entry.startedAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
    final duration = entry.duration;
    final durationStr = duration != null ? '${duration.inMinutes} min' : null;
    final radiusStr = entry.radiusMeters >= 1000
        ? '${entry.radiusMeters ~/ 1000} km'
        : '${entry.radiusMeters} m';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: entry.wasCompleted
                ? AppColors.forestLight
                : AppColors.sandLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: entry.wasCompleted
                  ? AppColors.forest.withValues(alpha: 0.30)
                  : AppColors.sand.withValues(alpha: 0.40),
            ),
          ),
          child: Row(
            children: [
              Text(
                entry.wasCompleted ? '✅' : '❌',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.placeName,
                      style: AppText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        dateStr,
                        if (durationStr != null) durationStr,
                        radiusStr,
                        if (entry.emotionEmoji != null) entry.emotionEmoji!,
                      ].join(' · '),
                      style: AppText.label.copyWith(
                        letterSpacing: 0,
                        color: AppColors.ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tuile trophée ────────────────────────────────────────────────────────────

class _TrophyTile extends StatelessWidget {
  final EarnedTrophy trophy;

  const _TrophyTile({required this.trophy});

  @override
  Widget build(BuildContext context) {
    final d = trophy.earnedAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.forestLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.forest.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Text(
              trophy.definition.emoji,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trophy.definition.name,
                    style: AppText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${trophy.definition.description} · $dateStr',
                    style: AppText.label.copyWith(
                      letterSpacing: 0,
                      color: AppColors.ink.withValues(alpha: 0.55),
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Text(
          text,
          style: AppText.body.copyWith(color: AppColors.sand, fontSize: 13),
        ),
      );
}

class _LoadingHint extends StatelessWidget {
  const _LoadingHint();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.terra,
              strokeWidth: 2,
            ),
          ),
        ),
      );
}

