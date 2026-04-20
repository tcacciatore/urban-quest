import 'dart:async';
import 'dart:io';
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
import 'widgets/top_bar.dart';
import 'widgets/app_drawer.dart';
import 'widgets/quest_sheet.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../../widgets/user_marker.dart';
import '../../providers/city_fog_provider.dart';
import '../../providers/missions_provider.dart';
import '../../providers/claimed_missions_provider.dart';
import '../../../domain/entities/city.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/fog_walk_layer.dart';
import '../../providers/rainbow_provider.dart';
import '../../providers/poi_providers.dart';
import '../../widgets/poi_layer.dart';
import '../poi/poi_detail_screen.dart';
import '../city/city_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
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

  void _animatedMove(LatLng dest, double zoom) {
    final latTween  = Tween<double>(begin: _mapController.camera.center.latitude,  end: dest.latitude);
    final lngTween  = Tween<double>(begin: _mapController.camera.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: _mapController.camera.zoom,             end: zoom);

    final ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);

    ctrl.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(anim), lngTween.evaluate(anim)),
        zoomTween.evaluate(anim),
      );
    });
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        ctrl.dispose();
      }
    });
    ctrl.forward();
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
    setState(() {
      _selectedCityId = hit?.id == _selectedCityId ? null : hit?.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(initialPositionProvider);
    final questState = ref.watch(questProvider);
    final currentPosition = ref.watch(positionStreamProvider).valueOrNull;
    final routeState = ref.watch(routeProvider);

    // City Fog — lu ici pour que HomeScreen se rebuilde quand les villes changent
    final cityFog = ref.watch(cityFogProvider);

    // POIs — initialise le notifier et reconstruit la carte lors de découvertes
    final poiState = ref.watch(poiProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // Carte plein écran
          positionAsync.when(
            data: (position) => _buildMap(position, routeState, cityFog, poiState, _selectedCityId),
            loading: () => const _MapPlaceholder(),
            error: (_, __) => const _MapPlaceholder(),
          ),

          // ── Nouvelle top bar ──────────────────────────────────────────────
          const Positioned(top: 0, left: 0, right: 0, child: TopBar()),

          // Bouton recentrer (bas droite, au-dessus de la nav)
          Positioned(
            bottom: 140,
            right: 16,
            child: _RecenterButton(
              onTap: () {
                final pos = currentPosition ?? positionAsync.valueOrNull;
                if (pos != null) _animatedMove(pos, 15.0);
              },
            ),
          ),

          // Photo / placeholder de la chasse sélectionnée
          if (routeState is AsyncData && routeState.value != null)
            Positioned(
              bottom: 165,
              left: 16,
              child: _QuestPhotoCard(
                photoPath: routeState.value!.photoPath,
                emotionEmoji: routeState.value!.emotionEmoji,
              ),
            ),

          // Bandeau route active
          if (routeState is AsyncLoading)
            const Positioned(
              bottom: 160,
              left: 16,
              right: 16,
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

          // Bannière changement de ville
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _CityChangeBanner(),
          ),

          // ── Pilule pas + barre de navigation ─────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomArea(
              onProgressionTap: () => _showProgressionSheet(context),
              onQuestsTap: () => _showQuestSheet(context),
              onTrophiesTap: () => _showTrophySheet(context),
              onHuntTap: () => _onGoTapped(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showProgressionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProgressionSheet(
        onCitySelected: (cityId, center) {
          setState(() => _selectedCityId = cityId);
          _animatedMove(center, 14.0);
        },
      ),
    );
  }

  void _showQuestSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => QuestSheet(onStartHunt: () => _onGoTapped(context)),
    );
  }

  void _showTrophySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const TrophySheet(),
    );
  }

  Widget _buildMap(LatLng position, AsyncValue<RouteState?> routeState, CityFogState cityFog, PoiState poiState, String? selectedCityId) {
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
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.urbanquest',
          retinaMode: true,
          // Teinte chaude légère pour l'ambiance "carte illustrée"
          tileBuilder: (context, tileWidget, tile) => ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              1.04,  0.02,  0.00, 0, 6,
              0.00,  1.01,  0.00, 0, 3,
             -0.02,  0.00,  0.96, 0, 0,
              0,     0,     0,    1, 0,
            ]),
            child: tileWidget,
          ),
        ),
        // ── Ville sélectionnée (glow animé) — en dessous du brouillard ────
        if (selectedCityId != null && cityFog.cities[selectedCityId] != null)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) {
              final t = _pulseAnim.value;
              final polygon = cityFog.cities[selectedCityId]!.polygon;
              return PolygonLayer(
                simplificationTolerance: 0,
                polygons: [
                  Polygon(
                    points: polygon,
                    color: Color.fromRGBO(200, 168, 130, 0.08 + 0.10 * t),
                    borderColor: Color.fromRGBO(200, 168, 130, 0.15 + 0.20 * t),
                    borderStrokeWidth: 18 + 8 * t,
                  ),
                  Polygon(
                    points: polygon,
                    color: Colors.transparent,
                    borderColor: Color.fromRGBO(200, 168, 130, 0.35 + 0.25 * t),
                    borderStrokeWidth: 7,
                  ),
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
        // ── City Fog — trainée colorée au premier plan ──────────────────────
        FogWalkLayer(
          cities: lockedCities,
          completedRainbow: ref.watch(rainbowProvider),
        ),
        // ── Contours : ville courante + arrondissements déjà visités ────────
        PolygonLayer(
          simplificationTolerance: 0,
          polygons: cityFog.cities.values
              .where((c) => c.walkedPoints.isNotEmpty || c.id == cityFog.currentCityId)
              .map((c) => Polygon(
                points: c.polygon,
                color: Colors.transparent,
                borderColor: Colors.white.withValues(alpha: 0.5),
                borderStrokeWidth: 1.5,
              )).toList(),
        ),
        MarkerLayer(
          key: ValueKey(cityFog.cities.values
              .fold<int>(0, (s, c) => s + c.walkedPoints.length)),
          rotate: false,
          markers: cityFog.cities.values
              .where((c) => !c.isUnlocked)
              .map((c) {
                final center = _fogCentroid(c.polygon);
                final progress = (c.revealedRatio / City.requiredRatio).clamp(0.0, 1.0);
                return Marker(
                  point: center,
                  width: 120,
                  height: 90,
                  child: _CityLockMarker(
                    name: c.name,
                    progress: progress,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CityDetailScreen(city: c),
                      ),
                    ),
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
        // ── POIs — ville courante + arrondissements/villes déjà visités ────
        PoiLayer(
          pois: poiState.allPois.where((poi) {
            final city = cityFog.cities[poi.cityId];
            if (city == null) return false;
            return poi.cityId == cityFog.currentCityId ||
                city.walkedPoints.isNotEmpty;
          }).toList(),
          onPoiTapped: (poi) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PoiDetailScreen(poi: poi),
            ),
          ),
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

// ─── Zone bas (pilule pas + nav) ──────────────────────────────────────────────

class _BottomArea extends ConsumerWidget {
  final VoidCallback onProgressionTap;
  final VoidCallback onQuestsTap;
  final VoidCallback onTrophiesTap;
  final VoidCallback onHuntTap;

  const _BottomArea({
    required this.onProgressionTap,
    required this.onQuestsTap,
    required this.onTrophiesTap,
    required this.onHuntTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missions = ref.watch(missionsProvider);
    final claimedNotifier = ref.watch(claimedMissionsProvider.notifier);
    ref.watch(claimedMissionsProvider);
    final unclaimedCount = missions
        .where((m) => m.isCompleted && !claimedNotifier.isClaimed(m))
        .length;

    final cityFog = ref.watch(cityFogProvider);
    final huntUnlocked = cityFog.cities.values.any((c) => c.isUnlocked);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavBtn(icon: Icons.bar_chart_rounded, label: 'Progression', color: const Color(0xFF6B8DAD), onTap: onProgressionTap),
                _NavBtn(icon: Icons.flag_rounded, label: 'Quêtes', color: const Color(0xFF6B8DAD), onTap: onQuestsTap, badge: unclaimedCount),
                _NavBtn(icon: Icons.emoji_events_rounded, label: 'Trophées', color: const Color(0xFF6B8DAD), onTap: onTrophiesTap),
                _HuntNavBtn(unlocked: huntUnlocked, onTap: huntUnlocked ? onHuntTap : null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HuntNavBtn extends StatelessWidget {
  final bool unlocked;
  final VoidCallback? onTap;
  const _HuntNavBtn({required this.unlocked, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            unlocked
                ? Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.search_rounded, color: Color(0xFFCDD8E3), size: 22),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2EAF4)),
                          ),
                          child: const Icon(Icons.lock_rounded, size: 8, color: Color(0xFF8FA8C0)),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 3),
            Text(
              'Chasse',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: unlocked ? const Color(0xFFFFB800) : const Color(0xFFCDD8E3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  const _NavBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 22),
                if (badge > 0)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
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

// ─── Bannière changement de ville ─────────────────────────────────────────────

class _CityChangeBanner extends ConsumerStatefulWidget {
  const _CityChangeBanner();

  @override
  ConsumerState<_CityChangeBanner> createState() => _CityChangeBannerState();
}

class _CityChangeBannerState extends ConsumerState<_CityChangeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  String? _cityName;
  String? _pendingCityId; // ID en attente de chargement du nom
  bool _firstBuild = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _show(String name) {
    setState(() => _cityName = name);
    _timer?.cancel();
    _ctrl.forward(from: 0);
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CityFogState>(cityFogProvider, (prev, next) {
      if (_firstBuild) {
        _firstBuild = false;
        return;
      }
      final prevId = prev?.currentCityId;
      final nextId = next.currentCityId;

      // Changement de ville
      if (nextId != null && nextId != prevId) {
        final name = next.cities[nextId]?.name;
        if (name != null) {
          _pendingCityId = null;
          _show(name);
        } else {
          // Nom pas encore chargé — on attend
          _pendingCityId = nextId;
        }
      }

      // Le nom d'une ville en attente vient d'être chargé
      if (_pendingCityId != null) {
        final name = next.cities[_pendingCityId!]?.name;
        if (name != null) {
          _pendingCityId = null;
          _show(name);
        }
      }
    });
    _firstBuild = false;

    if (_cityName == null) return const SizedBox.shrink();

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📍', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Nouveau quartier',
                          style: AppText.label.copyWith(
                            color: AppColors.sand,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _cityName!,
                          style: AppText.body.copyWith(
                            color: AppColors.parchment,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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
      ),
    );
  }
}

// ─── Marqueur cadenas "style jeu" ─────────────────────────────────────────────

class _CityLockMarker extends StatelessWidget {
  final String name;
  final double progress; // 0.0 → 1.0
  final VoidCallback? onTap;

  const _CityLockMarker({
    required this.name,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Boîte cadenas 3D ────────────────────────────────────────────────
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Ombre portée (effet 3D)
            Positioned(
              bottom: -5,
              child: Container(
                width: 52,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            // Face principale du bloc
            Container(
              width: 52,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE8EEF6), Color(0xFFBCC8DA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  // Tranche inférieure (effet 3D)
                  const BoxShadow(
                    color: Color(0xFF8A9AB8),
                    blurRadius: 0,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, color: Color(0xFF5A6A82), size: 24),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.4),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB300)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      ),
    );
  }
}
