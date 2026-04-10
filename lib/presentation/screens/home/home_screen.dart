import 'dart:async';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/location_providers.dart';
import '../../providers/quest_providers.dart';
import '../../providers/route_providers.dart';
import '../../../domain/entities/quest.dart';
import '../../providers/wallet_providers.dart';
import '../radius_picker/radius_picker_sheet.dart';
import '../quest/quest_screen.dart';
import 'widgets/wallet_header.dart';
import 'widgets/app_drawer.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../../widgets/user_marker.dart';
import '../../providers/city_fog_provider.dart';
import '../../../domain/entities/city.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/fog_walk_layer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  String? _selectedCityId;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  LatLng _fogCentroid(List<LatLng> polygon) {
    if (polygon.isEmpty) return const LatLng(0, 0);
    final lat = polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final lon = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
    return LatLng(lat, lon);
  }

  /// Point-in-polygon (ray casting) pour détecter le tap sur une ville.
  bool _pip(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    int crossings = 0;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }

  void _onMapTap(LatLng latLng, CityFogState cityFog) {
    final hit = cityFog.cities.values
        .where((c) => !c.isUnlocked)
        .where((c) => _pip(latLng, c.polygon))
        .firstOrNull;
    setState(() => _selectedCityId = hit?.id == _selectedCityId ? null : hit?.id);
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(initialPositionProvider);
    final questState = ref.watch(questProvider);
    final currentPosition = ref.watch(positionStreamProvider).valueOrNull;
    final routeState = ref.watch(routeProvider);

    // City Fog — lu ici pour que HomeScreen se rebuilde quand les villes changent
    final cityFog = ref.watch(cityFogProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // Carte plein écran
          positionAsync.when(
            data: (position) => _buildMap(position, routeState, cityFog, _selectedCityId),
            loading: () => const _MapPlaceholder(),
            error: (_, __) => const _MapPlaceholder(),
          ),

          // Header crédits + chasses + pas
          const Positioned(top: 0, left: 0, right: 0, child: WalletHeader()),

          // Bouton menu
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 14, top: 10),
                child: Builder(
                  builder: (ctx) => GestureDetector(
                    onTap: () => Scaffold.of(ctx).openDrawer(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.sandLight, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.menu, color: AppColors.ink, size: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bouton recentrer (bas droite)
          Positioned(
            bottom: 140,
            right: 20,
            child: _RecenterButton(
              onTap: () {
                final pos = currentPosition ?? positionAsync.valueOrNull;
                if (pos != null) _mapController.move(pos, 15.0);
              },
            ),
          ),

          // Bouton GO
          Positioned(
            bottom: 44,
            left: 0,
            right: 0,
            child: Center(
              child: _GoButton(onTap: () => _onGoTapped(context)),
            ),
          ),

          // Photo / placeholder de la chasse sélectionnée
          if (routeState is AsyncData && routeState.value != null)
            Positioned(
              bottom: 196,
              left: 20,
              child: _QuestPhotoCard(
                photoPath: routeState.value!.photoPath,
                emotionEmoji: routeState.value!.emotionEmoji,
              ),
            ),

          // Bandeau route active
          if (routeState is AsyncLoading)
            const Positioned(
              bottom: 136,
              left: 20,
              right: 20,
              child: _RouteBanner(name: null, isLoading: true),
            ),
          if (routeState is AsyncData && routeState.value != null)
            Positioned(
              bottom: 136,
              left: 20,
              right: 20,
              child: _RouteBanner(
                name: routeState.value!.destinationName,
                isLoading: false,
                onClose: () => ref.read(routeProvider.notifier).clear(),
              ),
            ),

          // Message d'erreur
          if (questState is AsyncError)
            Positioned(
              bottom: 136,
              left: 20,
              right: 20,
              child: _ErrorBanner(message: (questState as AsyncError).error.toString()),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(LatLng position, AsyncValue<RouteState?> routeState, CityFogState cityFog, String? selectedCityId) {
    final route = routeState is AsyncData ? routeState.value : null;
    final lockedCities = cityFog.cities.values.where((c) => !c.isUnlocked).toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: position,
        initialZoom: 15.0,
        onTap: (_, latLng) => _onMapTap(latLng, cityFog),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.urbanquest',
          retinaMode: true,
        ),
        // ── City Fog — brouillard percé par la marche ───────────────────────
        FogWalkLayer(
          cities: lockedCities.where((c) => c.id != selectedCityId).toList(),
        ),
        // ── City Fog — ville sélectionnée (glow animé) ──────────────────────
        if (selectedCityId != null && cityFog.cities[selectedCityId] != null)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) {
              final t = _pulseAnim.value; // 0.0 → 1.0
              final polygon = cityFog.cities[selectedCityId]!.polygon;
              return PolygonLayer(
                simplificationTolerance: 0,
                polygons: [
                  // Halo large pulsant
                  Polygon(
                    points: polygon,
                    color: Color.fromRGBO(200, 168, 130, 0.08 + 0.10 * t),
                    borderColor: Color.fromRGBO(200, 168, 130, 0.15 + 0.20 * t),
                    borderStrokeWidth: 18 + 8 * t,
                  ),
                  // Halo moyen
                  Polygon(
                    points: polygon,
                    color: Colors.transparent,
                    borderColor: Color.fromRGBO(200, 168, 130, 0.35 + 0.25 * t),
                    borderStrokeWidth: 7,
                  ),
                  // Contour net + remplissage surélevé
                  Polygon(
                    points: polygon,
                    color: Color.fromRGBO(80, 48, 20, 0.75 + 0.10 * t),
                    borderColor: Color.fromRGBO(200, 168, 130, 0.85 + 0.15 * t),
                    borderStrokeWidth: 2.5,
                  ),
                ],
              );
            },
          ),
        MarkerLayer(
          rotate: false,
          markers: cityFog.cities.values
              .where((c) => !c.isUnlocked)
              .map((c) {
                final center = _fogCentroid(c.polygon);
                return Marker(
                  point: center,
                  width: 180,
                  height: 44,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔒', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(
                        '${(c.revealedRatio * 100).round()}\u202f/\u202f${(City.requiredRatio * 100).round()}% explorés',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.80),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(),
        ),
        // ────────────────────────────────────────────────────────────────────
        if (route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.polyline,
                color: AppColors.terra,
                strokeWidth: 4,
              ),
            ],
          ),
        if (route != null)
          MarkerLayer(
            markers: [
              Marker(
                point: route.destination,
                width: 36,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.forest,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.2),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.flag, color: AppColors.white, size: 18),
                ),
              ),
            ],
          ),
        Consumer(builder: (context, ref, _) {
          final livePos = ref.watch(positionStreamProvider).valueOrNull ?? position;
          final heading = ref.watch(headingStreamProvider).valueOrNull ?? 0.0;
          return MarkerLayer(
            markers: [
              Marker(
                point: livePos,
                width: 48,
                height: 48,
                child: UserDirectionalMarker(heading: heading),
              ),
            ],
          );
        }),
      ],
    );
  }

  Future<void> _onGoTapped(BuildContext context) async {
    final wallet = ref.read(walletProvider);
    if (!AppConstants.testMode && !wallet.hasQuestsRemaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limite de 3 chasses atteinte aujourd\'hui.')),
      );
      return;
    }

    final setup = await showModalBottomSheet<({int radius, String? direction})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const RadiusPickerSheet(),
    );

    if (setup == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _QuestLoadingDialog(),
    );

    try {
      final position = await ref.read(locationServiceProvider).getCurrentPosition();
      await ref.read(questProvider.notifier).startQuest(
            position,
            setup.radius,
            direction: setup.direction,
          );
    } finally {
      if (context.mounted) Navigator.of(context).pop();
    }

    if (!context.mounted) return;

    final quest = ref.read(questProvider).valueOrNull;
    if (quest != null && quest.status == QuestStatus.active && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const QuestScreen()),
      );
    }
  }
}

// ─── Placeholder carte ────────────────────────────────────────────────────────

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.parchment,
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.terra, strokeWidth: 2),
      ),
    );
  }
}

// ─── Bouton recentrer ─────────────────────────────────────────────────────────

class _RecenterButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RecenterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.sandLight, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.my_location, color: AppColors.ink, size: 18),
      ),
    );
  }
}

// ─── Bouton GO ────────────────────────────────────────────────────────────────

class _GoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.30),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'GO',
            style: AppText.label.copyWith(
              fontSize: 13,
              letterSpacing: 4,
              color: AppColors.parchment,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bandeau route ────────────────────────────────────────────────────────────

class _RouteBanner extends StatelessWidget {
  final String? name;
  final bool isLoading;
  final VoidCallback? onClose;

  const _RouteBanner({this.name, required this.isLoading, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.sandLight, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(color: AppColors.terra, strokeWidth: 2),
            )
          else
            const Icon(Icons.route, color: AppColors.terra, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isLoading ? 'Calcul de l\'itinéraire...' : '📍 $name',
              style: AppText.body.copyWith(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isLoading && onClose != null)
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, color: AppColors.sand, size: 16),
            ),
        ],
      ),
    );
  }
}

// ─── Bannière erreur ──────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.terraLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.terra.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: AppText.body.copyWith(color: AppColors.terra, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Dialog chargement ────────────────────────────────────────────────────────

class _QuestLoadingDialog extends StatefulWidget {
  const _QuestLoadingDialog();

  @override
  State<_QuestLoadingDialog> createState() => _QuestLoadingDialogState();
}

class _QuestLoadingDialogState extends State<_QuestLoadingDialog> {
  static const _messages = [
    ('🔍', 'Consultation des archives secrètes de la ville...'),
    ('🗺️', 'Dépoussiérage des vieilles cartes du quartier...'),
    ('🧭', 'Calibration de la boussole mystique...'),
    ('🎲', 'Tirage au sort du destin urbain...'),
    ('🕵️', 'Vérification de l\'absence de dragons...'),
    ('🏚️', 'Sélection d\'un coin méconnu des touristes...'),
    ('🌆', 'Analyse des ruelles et impasses cachées...'),
    ('✨', 'Préparation de ta prochaine aventure...'),
    ('🦉', 'Consultation de l\'oracle de la rue...'),
    ('🗝️', 'Déverrouillage du lieu mystère...'),
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      setState(() => _index = (_index + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (emoji, text) = _messages[_index];
    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.terra,
              strokeWidth: 2,
            ),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Column(
                key: ValueKey(_index),
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 36)),
                  const SizedBox(height: 12),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: AppText.hint,
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

// ─── Photo / placeholder chasse ───────────────────────────────────────────────

class _QuestPhotoCard extends StatelessWidget {
  final String? photoPath;
  final String? emotionEmoji;

  const _QuestPhotoCard({this.photoPath, this.emotionEmoji});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoPath != null && File(photoPath!).existsSync();

    return GestureDetector(
      onTap: () => _showFullScreen(context, hasPhoto),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.sandLight, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: hasPhoto
              ? Image.file(File(photoPath!), fit: BoxFit.cover)
              : Container(
                  color: AppColors.white,
                  child: Center(
                    child: Text(
                      emotionEmoji ?? '📍',
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context, bool hasPhoto) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => _FullScreenPhoto(
          photoPath: hasPhoto ? photoPath : null,
          emotionEmoji: emotionEmoji,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

class _FullScreenPhoto extends StatelessWidget {
  final String? photoPath;
  final String? emotionEmoji;

  const _FullScreenPhoto({this.photoPath, this.emotionEmoji});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Center(
              child: photoPath != null
                  ? InteractiveViewer(
                      child: Image.file(File(photoPath!), fit: BoxFit.contain),
                    )
                  : Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Text(
                          emotionEmoji ?? '📍',
                          style: const TextStyle(fontSize: 80),
                        ),
                      ),
                    ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.sandLight),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.08),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close, color: AppColors.ink, size: 16),
                    ),
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
