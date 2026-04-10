import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/location_providers.dart';
import '../../providers/quest_providers.dart';
import '../../providers/route_providers.dart';
import '../../providers/trophy_providers.dart';
import '../../providers/quest_history_providers.dart';
import '../../providers/wallet_providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/emotion_tags.dart';
import '../../../domain/entities/trophy.dart';
import 'widgets/emotion_tag_sheet.dart';

import '../../../core/extensions/latlng_extensions.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../../../domain/entities/clue.dart';
import '../../widgets/user_marker.dart';

class QuestScreen extends ConsumerStatefulWidget {
  const QuestScreen({super.key});

  @override
  ConsumerState<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends ConsumerState<QuestScreen> {
  bool _arrivalHandled = false;
  final MapController _mapController = MapController();
  final List<LatLng> _visitedPath = [];
  LatLng? _lastTrackedPosition;
  LatLng? _startPosition;

  @override
  Widget build(BuildContext context) {
    final questAsync = ref.watch(questProvider);
    final positionAsync = ref.watch(positionStreamProvider);
    final stepCount = ref.watch(stepCountProvider);

    return questAsync.when(
      data: (quest) {
        if (quest == null) return const SizedBox.shrink();

        return positionAsync.when(
          data: (position) {
            final target = LatLng(quest.targetPlace.latitude, quest.targetPlace.longitude);
            final distance = position.distanceTo(target);
            final direction = position.cardinalDirectionTo(target);
            final isHotMode = distance <= 50.0;

            final circleRadiusMeters = isHotMode
                ? 3.0 + (1.0 - (distance / 50.0).clamp(0.0, 1.0)) * 32.0
                : 0.0;

            if (_lastTrackedPosition == null ||
                position.distanceTo(_lastTrackedPosition!) > 5) {
              _visitedPath.add(position);
              _lastTrackedPosition = position;
            }
            _startPosition ??= position;

            ref.read(questProvider.notifier).tryRevealNextClue(position);

            if (distance < AppConstants.arrivalRadiusMeters && !_arrivalHandled) {
              _arrivalHandled = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _handleArrival(context, quest),
              );
            }

            return Scaffold(
              body: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: position,
                      initialZoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}{r}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.urbanquest',
                        retinaMode: true,
                      ),
                      if (_visitedPath.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _visitedPath,
                              color: Colors.blue.withValues(alpha: 0.75),
                              strokeWidth: 3.5,
                            ),
                          ],
                        ),
                      if (isHotMode)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: position,
                              radius: circleRadiusMeters * 1.5,
                              color: Colors.red.withValues(alpha: 0.06),
                              borderColor: Colors.transparent,
                              borderStrokeWidth: 0,
                              useRadiusInMeter: true,
                            ),
                            CircleMarker(
                              point: position,
                              radius: circleRadiusMeters,
                              color: Colors.deepOrange.withValues(alpha: 0.15),
                              borderColor: Colors.red.withValues(alpha: 0.7),
                              borderStrokeWidth: 2.0,
                              useRadiusInMeter: true,
                            ),
                          ],
                        ),
                      if (_visitedPath.isNotEmpty)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _visitedPath.first,
                              width: 28,
                              height: 28,
                              child: const Text('📍', style: TextStyle(fontSize: 22)),
                            ),
                          ],
                        ),
                      Consumer(builder: (context, ref, _) {
                        final heading = ref.watch(headingStreamProvider).valueOrNull ?? 0.0;
                        return MarkerLayer(
                          markers: [
                            Marker(
                              point: position,
                              width: 48,
                              height: 48,
                              child: UserDirectionalMarker(heading: heading),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),

                  // Overlay brûlant (non interactif)
                  if (isHotMode)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeInOut,
                          color: Colors.deepOrange.withValues(alpha: 0.14),
                        ),
                      ),
                    ),

                  // Boutons haut
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _MapButton(
                              icon: Icons.arrow_back,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                            if (isHotMode) const _HotBadge(),
                            _MapButton(
                              icon: Icons.close,
                              label: 'Abandonner',
                              onTap: () => _confirmAbandon(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bouton test (testMode uniquement)
                  if (AppConstants.testMode)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 56),
                            child: GestureDetector(
                              onTap: () {
                                if (!_arrivalHandled) {
                                  _arrivalHandled = true;
                                  _handleArrival(context, quest);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '🔧 Simuler l\'arrivée',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Bouton recentrer
                  Positioned(
                    bottom: 220,
                    right: 16,
                    child: GestureDetector(
                      onTap: () => _mapController.move(position, 15.0),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.sandLight),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.ink.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(Icons.my_location, color: AppColors.ink, size: 20),
                      ),
                    ),
                  ),

                  // Panel infos en bas
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _QuestInfoPanel(
                      distance: distance,
                      direction: direction,
                      clues: quest.clues,
                      isHotMode: isHotMode,
                      stepCount: stepCount,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.terra)),
          ),
          error: (_, __) => Scaffold(
            body: Center(child: Text('Erreur GPS', style: AppText.body)),
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.terra))),
      error: (e, _) => Scaffold(body: Center(child: Text(e.toString()))),
    );
  }

  Future<void> _handleArrival(BuildContext context, quest) async {
    if (!context.mounted) return;

    final photoPath = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WinDialog(placeName: quest.targetPlace.name),
    );
    if (!context.mounted) return;

    final suggestedTag = suggestFromOsm(
      quest.targetPlace.tags['nearby_poi_osm_key'],
      quest.targetPlace.tags['nearby_poi_osm_value'],
    );

    final selectedTag = await showModalBottomSheet<EmotionTag>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EmotionTagSheet(suggestedTag: suggestedTag),
    );
    if (selectedTag == null || !context.mounted) return;

    ref.read(questProvider.notifier).completeQuest(selectedTag.label);
    final completed = ref.read(questProvider).valueOrNull;

    if (completed != null) {
      await ref.read(questHistoryProvider.notifier).add(
            QuestHistoryEntry(
              placeName: completed.targetPlace.name,
              startedAt: completed.startedAt,
              completedAt: completed.completedAt,
              radiusMeters: completed.radiusMeters,
              wasCompleted: true,
              latitude: completed.targetPlace.latitude,
              longitude: completed.targetPlace.longitude,
              emotionEmoji: selectedTag.emoji,
              emotionLabel: selectedTag.label,
              photoPath: photoPath,
              startLatitude: _startPosition?.latitude,
              startLongitude: _startPosition?.longitude,
              walkedPath: _visitedPath.isNotEmpty ? List.from(_visitedPath) : null,
            ),
          );
    }

    final newTrophies = completed != null
        ? await ref.read(trophyProvider.notifier).evaluateQuest(completed)
        : <EarnedTrophy>[];

    if (_visitedPath.isNotEmpty && completed != null) {
      ref.read(routeProvider.notifier).setWalkedPath(
        path: List.from(_visitedPath),
        destination: LatLng(completed.targetPlace.latitude, completed.targetPlace.longitude),
        destinationName: completed.targetPlace.name,
        photoPath: photoPath,
        emotionEmoji: selectedTag.emoji,
      );
    }

    // ── Fog of War : révéler le quartier du point d'arrivée ─────────────────
    if (completed != null) {
      final target = LatLng(
        completed.targetPlace.latitude,
        completed.targetPlace.longitude,
      );
      // TODO: intégrer déverrouillage ville via cityFogProvider
    }

    if (context.mounted) {
      _showSuccessDialog(context, quest.targetPlace.name, newTrophies, selectedTag);
    }
  }

  void _showSuccessDialog(BuildContext context, String placeName, List<EarnedTrophy> newTrophies, EmotionTag selectedTag) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                'Tu l\'as trouvé !',
                textAlign: TextAlign.center,
                style: AppText.sectionTitle,
              ),
              const SizedBox(height: 8),
              Text(
                'Bravo, explorateur urbain !',
                textAlign: TextAlign.center,
                style: AppText.hint.copyWith(color: AppColors.sand),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.forestLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  placeName,
                  textAlign: TextAlign.center,
                  style: AppText.metric.copyWith(color: AppColors.forest, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.terraLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.terra.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${selectedTag.emoji}  ${selectedTag.label}',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w500),
                ),
              ),

              if (newTrophies.isNotEmpty) ...[
                const SizedBox(height: 24),
                Divider(color: AppColors.sandLight, height: 20),
                const SizedBox(height: 12),
                Text(
                  'Trophées débloqués !',
                  style: AppText.body.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...newTrophies.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text(t.definition.emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.definition.name,
                                  style: AppText.body.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  t.definition.description,
                                  style: AppText.label.copyWith(letterSpacing: 0),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
              ],

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Terminer la chasse',
                    style: AppText.metric.copyWith(
                      color: AppColors.parchment,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmAbandon(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        title: Text('Abandonner ?', style: AppText.sectionTitle.copyWith(fontSize: 20)),
        content: Text(
          'Les crédits dépensés ne seront pas remboursés.',
          style: AppText.body.copyWith(color: AppColors.sand),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Continuer', style: TextStyle(color: AppColors.ink)),
          ),
          TextButton(
            onPressed: () async {
              final quest = ref.read(questProvider).valueOrNull;
              ref.read(questProvider.notifier).abandonQuest();
              if (quest != null) {
                await ref.read(questHistoryProvider.notifier).add(
                      QuestHistoryEntry(
                        placeName: quest.targetPlace.name,
                        startedAt: quest.startedAt,
                        completedAt: null,
                        radiusMeters: quest.radiusMeters,
                        wasCompleted: false,
                        latitude: quest.targetPlace.latitude,
                        longitude: quest.targetPlace.longitude,
                        startLatitude: _startPosition?.latitude,
                        startLongitude: _startPosition?.longitude,
                        walkedPath: _visitedPath.isNotEmpty ? List.from(_visitedPath) : null,
                      ),
                    );
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text('Abandonner', style: TextStyle(color: AppColors.terra)),
          ),
        ],
      ),
    );
  }
}

// ─── Popup de victoire ────────────────────────────────────────────────────────

class _WinDialog extends StatefulWidget {
  final String placeName;
  const _WinDialog({required this.placeName});

  @override
  State<_WinDialog> createState() => _WinDialogState();
}

class _WinDialogState extends State<_WinDialog> {
  String? _photoPath;
  bool _takingPhoto = false;

  Future<void> _takePhoto() async {
    setState(() => _takingPhoto = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null && mounted) {
        final docsDir = await getApplicationDocumentsDirectory();
        final fileName = 'quest_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final permanent = await File(photo.path).copy('${docsDir.path}/$fileName');
        if (mounted) setState(() => _photoPath = permanent.path);
      }
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text(
              'Tu as trouvé le lieu !',
              textAlign: TextAlign.center,
              style: AppText.sectionTitle,
            ),
            const SizedBox(height: 6),
            Text(
              widget.placeName,
              textAlign: TextAlign.center,
              style: AppText.metric.copyWith(color: AppColors.forest, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),

            if (_photoPath != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.forestLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.forest.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: AppColors.forest, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Photo prise !',
                      style: AppText.body.copyWith(color: AppColors.forest, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _takingPhoto ? null : _takePhoto,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.sandLight),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _takingPhoto
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.terra))
                      : Icon(Icons.camera_alt, color: AppColors.terra, size: 18),
                  label: Text(
                    _takingPhoto ? 'Ouverture...' : '📸 Prendre une photo souvenir',
                    style: AppText.body.copyWith(fontSize: 13),
                  ),
                ),
              ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_photoPath),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Continuer →',
                  style: AppText.metric.copyWith(
                    color: AppColors.parchment,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Panel infos ─────────────────────────────────────────────────────────────

class _QuestInfoPanel extends StatelessWidget {
  final double distance;
  final String direction;
  final List<Clue> clues;
  final bool isHotMode;
  final int stepCount;

  const _QuestInfoPanel({
    required this.distance,
    required this.direction,
    required this.clues,
    required this.isHotMode,
    required this.stepCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.sandLight),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isHotMode) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on, color: AppColors.terra, size: 18),
                const SizedBox(width: 4),
                Text(
                  distance >= 1000
                      ? '${(distance / 1000).toStringAsFixed(1)} km'
                      : '${distance.toInt()} m',
                  style: AppText.metric.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                Icon(Icons.navigation, color: AppColors.forest, size: 18),
                const SizedBox(width: 4),
                Text(
                  direction,
                  style: AppText.metric.copyWith(color: AppColors.forest, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions_walk, color: AppColors.sand, size: 15),
                const SizedBox(width: 4),
                Text('$stepCount pas', style: AppText.label.copyWith(letterSpacing: 0)),
              ],
            ),
            Divider(color: AppColors.sandLight, height: 20),
          ],
          ...clues.map((clue) => _ClueRow(clue: clue)),
        ],
      ),
    );
  }
}

class _ClueRow extends StatelessWidget {
  final Clue clue;

  const _ClueRow({required this.clue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            clue.isRevealed ? Icons.lightbulb : Icons.lock,
            size: 16,
            color: clue.isRevealed ? AppColors.forest : AppColors.sand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              clue.isRevealed ? clue.text : 'Indice ${clue.index} (se déverrouille en approchant)',
              style: AppText.hint.copyWith(
                fontSize: 14,
                height: 1.4,
                color: clue.isRevealed ? AppColors.ink : AppColors.sand,
                fontStyle: clue.isRevealed ? FontStyle.italic : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Badge ───────────────────────────────────────────────────────────────────

class _HotBadge extends StatelessWidget {
  const _HotBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.terra,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.terra.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '🔥 Tu chauffes !',
        style: AppText.label.copyWith(
          color: AppColors.parchment,
          letterSpacing: 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.sandLight),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.07),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.ink, size: 18),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!, style: AppText.label.copyWith(letterSpacing: 0, color: AppColors.ink)),
            ],
          ],
        ),
      ),
    );
  }
}
