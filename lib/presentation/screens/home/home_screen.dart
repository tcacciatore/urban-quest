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
import 'widgets/personal_pin_sheet.dart';
import '../../providers/personal_pin_provider.dart';
import '../../../domain/entities/personal_pin.dart';
import '../../providers/walker_profile_provider.dart';
import '../../providers/km_milestone_provider.dart';
import '../profile/walker_profile_screen.dart' show WalkerProfileScreen, RarityBadge;
import '../splash/splash_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  String? _selectedCityId;
  Set<String>? _emotionFilter; // null = tout afficher
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
        .where((c) => _pip(latLng, c.polygon))
        .firstOrNull;
    setState(() {
      _selectedCityId = hit?.id == _selectedCityId ? null : hit?.id;
    });
  }

  void _showMilestoneBanner(BuildContext context, double km, WalkerAnimal animal) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _KmMilestoneBanner(
        km: km,
        animal: animal,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(initialPositionProvider);
    final questState = ref.watch(questProvider);
    final currentPosition = ref.watch(positionStreamProvider).valueOrNull;
    final routeState = ref.watch(routeProvider);

    // City Fog — lu ici pour que HomeScreen se rebuilde quand les villes changent
    final cityFog = ref.watch(cityFogProvider);

    // Milestones km
    ref.listen<double?>(pendingKmMilestoneProvider, (prev, next) {
      if (next != null && next != prev) {
        final profile = ref.read(walkerProfileProvider);
        _showMilestoneBanner(context, next, profile.animal);
        ref.read(lastShownMilestoneProvider.notifier).acknowledge(next);
      }
    });

    // POIs — initialise le notifier et reconstruit la carte lors de découvertes
    final poiState = ref.watch(poiProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // Carte plein écran
          positionAsync.when(
            data: (position) => _buildMap(position, routeState, cityFog, poiState, _selectedCityId),
            loading: () => const SplashScreen(),
            error: (_, __) => const SplashScreen(),
          ),

          // ── Nouvelle top bar ──────────────────────────────────────────────
          const Positioned(top: 0, left: 0, right: 0, child: TopBar()),

          // ── Indicateur de chargement POIs ────────────────────────────────
          if (cityFog.currentCityId != null &&
              poiState.isLoading(cityFog.currentCityId!))
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _PoiLoadingBanner(),
            ),

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

          // ── Bouton "épingle" personnel ───────────────────────────────────
          Positioned(
            bottom: 200,
            right: 16,
            child: _PinButton(
              onTap: () => _onAddPinTapped(context),
              onLongPress: () => _onFilterPinsTapped(context),
              hasActiveFilter: _emotionFilter != null,
            ),
          ),

          // ── Badge profil animal ──────────────────────────────────────────
          Positioned(
            bottom: 140,
            left: 16,
            child: _AnimalBadge(
              onTap: () => _showProfileSheet(context),
            ),
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

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProfileSheet(),
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
        // ── City Fog — trainée colorée au premier plan ──────────────────────
        FogWalkLayer(
          cities: lockedCities,
          completedRainbow: ref.watch(rainbowProvider),
        ),
        // ── Ville sélectionnée (glow animé) — au-dessus du brouillard ────────
        // Fill transparent pour ne pas masquer la trainée colorée en dessous.
        if (selectedCityId != null && cityFog.cities[selectedCityId] != null)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) {
              final t = _pulseAnim.value;
              final polygon = cityFog.cities[selectedCityId]!.polygon;
              return PolygonLayer(
                simplificationTolerance: 0,
                polygons: [
                  // Halo large pulsant
                  Polygon(
                    points: polygon,
                    color: Colors.transparent,
                    borderColor: Color.fromRGBO(180, 220, 255, 0.15 + 0.25 * t),
                    borderStrokeWidth: 22 + 10 * t,
                  ),
                  // Halo moyen
                  Polygon(
                    points: polygon,
                    color: Colors.transparent,
                    borderColor: Color.fromRGBO(200, 235, 255, 0.55 + 0.25 * t),
                    borderStrokeWidth: 6,
                  ),
                  // Contour net
                  Polygon(
                    points: polygon,
                    color: Colors.transparent,
                    borderColor: Color.fromRGBO(255, 255, 255, 0.92 + 0.08 * t),
                    borderStrokeWidth: 2.0,
                  ),
                ],
              );
            },
          ),
        // ── Contours : ville courante + arrondissements déjà visités ────────
        PolygonLayer(
          simplificationTolerance: 0,
          polygons: cityFog.cities.values
              .where((c) => c.lastVisitDate != null || c.id == cityFog.currentCityId)
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
                  width: 110,
                  height: 32,
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
                city.lastVisitDate != null;
          }).toList(),
          onPoiTapped: (poi) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PoiDetailScreen(poi: poi),
            ),
          ),
        ),
        // ── Pins personnels (avec clustering) ────────────────────────────
        Consumer(builder: (context, ref, _) {
          final pins = ref.watch(personalPinProvider);
          return _PinClusterLayer(
            pins: pins,
            emotionFilter: _emotionFilter,
            mapController: _mapController,
          );
        }),
        // ── Marqueur utilisateur ─────────────────────────────────────────
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

  Future<void> _onFilterPinsTapped(BuildContext context) async {
    final pins = ref.read(personalPinProvider);
    if (pins.isEmpty) return;

    final result = await showModalBottomSheet<Set<String>?>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PinFilterSheet(
        pins: pins,
        activeFilter: _emotionFilter,
      ),
    );
    // result == null → l'utilisateur a fermé sans choisir (on ne change rien)
    if (!context.mounted) return;
    if (result != null) {
      setState(() => _emotionFilter = result.isEmpty ? null : result);
    }
  }

  Future<void> _onAddPinTapped(BuildContext context) async {
    final position = ref.read(positionStreamProvider).valueOrNull
        ?? ref.read(initialPositionProvider).valueOrNull;
    if (position == null) return;

    final result = await showModalBottomSheet<PinResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PersonalPinSheet(),
    );
    if (result == null) return;

    final cityFog = ref.read(cityFogProvider);
    final currentCity = cityFog.cities.values
        .where((c) => _pip(LatLng(position.latitude, position.longitude), c.polygon))
        .firstOrNull;

    final pin = PersonalPin(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      latitude: position.latitude,
      longitude: position.longitude,
      emoji: result.emoji,
      label: result.label,
      photoPath: result.photoPath,
      createdAt: DateTime.now(),
      cityId: currentCity?.id ?? cityFog.currentCityId,
    );
    await ref.read(personalPinProvider.notifier).add(pin);

    // Révèle le brouillard autour du pin, comme lors d'une découverte de POI
    final pinCityId = pin.cityId;
    if (pinCityId != null) {
      ref.read(cityFogProvider.notifier).revealAroundPoint(
        pinCityId,
        LatLng(pin.latitude, pin.longitude),
        150.0,
      );
    }
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
    final huntUnlocked = AppConstants.testMode || cityFog.cities.values.any((c) => c.isUnlocked);

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

class _QuestPhotoCard extends ConsumerWidget {
  final String? photoPath;
  final String? emotionEmoji;

  const _QuestPhotoCard({this.photoPath, this.emotionEmoji});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsDir = ref.watch(appDocsDirProvider).valueOrNull;
    // Si photoPath est déjà un chemin absolu (anciens enregistrements),
    // on l'utilise tel quel ; sinon on reconstruit depuis docsDir + basename.
    final fullPath = photoPath == null
        ? null
        : (photoPath!.contains('/') ? photoPath : (docsDir != null ? '$docsDir/$photoPath' : null));
    final hasPhoto = fullPath != null && File(fullPath).existsSync();

    return GestureDetector(
      onTap: () => _showFullScreen(context, hasPhoto, fullPath),
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
              ? Image.file(File(fullPath), fit: BoxFit.cover)
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

  void _showFullScreen(BuildContext context, bool hasPhoto, String? fullPath) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => _FullScreenPhoto(
          photoPath: hasPhoto ? fullPath : null,
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
    _timer = Timer(const Duration(seconds: 4), () {
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
                          'Ville actuelle',
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

// ─── Bandeau chargement POIs ──────────────────────────────────────────────────

class _PoiLoadingBanner extends StatefulWidget {
  @override
  State<_PoiLoadingBanner> createState() => _PoiLoadingBannerState();
}

class _PoiLoadingBannerState extends State<_PoiLoadingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 72),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1E30).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Chargement des lieux…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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

// ─── Badge animal flottant ────────────────────────────────────────────────────

class _AnimalBadge extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const _AnimalBadge({required this.onTap});

  @override
  ConsumerState<_AnimalBadge> createState() => _AnimalBadgeState();
}

class _AnimalBadgeState extends ConsumerState<_AnimalBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(walkerProfileProvider);
    final color   = profile.animal.color;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: color.withValues(alpha: 0.4 + 0.3 * _pulse.value),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.20 + 0.15 * _pulse.value),
                blurRadius: 12 + 6 * _pulse.value,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: child,
        ),
        child: Center(
          child: Text(
            profile.animal.emoji,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}

// ─── Profile bottom sheet compact ─────────────────────────────────────────────

class _ProfileSheet extends ConsumerWidget {
  const _ProfileSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(walkerProfileProvider);
    final animal  = profile.animal;
    final color   = animal.color;

    final axes = [
      ('🏃', '  Vitesse',    profile.speed),
      ('💪', '  Endurance',  profile.endurance),
      ('🗺️', '  Exploration', profile.exploration),
      ('🔍', '  Curiosité',  profile.curiosity),
      ('⚡', '  Activité',   profile.activity),
    ];

    final km = profile.totalKm;
    final kmStr = km >= 10 ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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

          // ── Emoji + titre ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.10),
                  border: Border.all(color: color.withValues(alpha: 0.30), width: 2),
                ),
                child: Center(
                  child: Text(animal.emoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animal.title,
                      style: AppText.sectionTitle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 6),
                    RarityBadge(rarity: animal.rarity),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Axes compacts ──────────────────────────────────────────────
          ...axes.map((axis) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(axis.$1, style: const TextStyle(fontSize: 13)),
                SizedBox(
                  width: 88,
                  child: Text(
                    axis.$2,
                    style: AppText.body.copyWith(fontSize: 12, color: AppColors.ink.withValues(alpha: 0.65)),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: axis.$3,
                      minHeight: 6,
                      backgroundColor: AppColors.sandLight,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
              ],
            ),
          )),

          const SizedBox(height: 16),

          // ── Stats rapides ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _QuickStat('🗺️', kmStr, 'parcourus'),
              _QuickStat('🏙️', '${profile.citiesVisited}', 'quartiers'),
              _QuickStat('🏁', '${profile.questsCompleted}', 'chasses'),
              _QuickStat('🏆', '${profile.trophiesCount}', 'trophées'),
            ],
          ),

          const SizedBox(height: 16),

          // ── Teaser prochaine évolution ─────────────────────────────────
          if (profile.nextEvolution != null)
            _NextEvolutionTeaser(evo: profile.nextEvolution!),

          const SizedBox(height: 16),

          // ── Bouton profil complet ──────────────────────────────────────
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WalkerProfileScreen(),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.75)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                'Voir le profil complet  →',
                textAlign: TextAlign.center,
                style: AppText.metric.copyWith(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextEvolutionTeaser extends StatelessWidget {
  final ProfileEvolution evo;
  const _NextEvolutionTeaser({required this.evo});

  @override
  Widget build(BuildContext context) {
    final color    = evo.animal.color;
    final progress = evo.overallProgress;
    final missing  = evo.conditions.where((c) => !c.isMet).toList();
    final first    = missing.isNotEmpty ? missing.first : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(evo.animal.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Prochaine évolution',
                      style: AppText.label.copyWith(
                        color: color, letterSpacing: 0.8, fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 6),
                    RarityBadge(rarity: evo.animal.rarity),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress, minHeight: 5,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                if (first != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Il manque ${first.remaining < 10 ? first.remaining.toStringAsFixed(1) : first.remaining.toStringAsFixed(0)} ${first.unit}',
                    style: AppText.label.copyWith(
                      color: color.withValues(alpha: 0.85),
                      letterSpacing: 0.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _QuickStat(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 2),
      Text(value, style: AppText.metric.copyWith(fontSize: 14)),
      Text(label, style: AppText.label.copyWith(fontSize: 9, letterSpacing: 0.3)),
    ],
  );
}

// ─── Visionneuse photo plein écran ────────────────────────────────────────────

class _PinFullScreenPhoto extends StatelessWidget {
  final String path;
  const _PinFullScreenPhoto({required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Photo interactive (pinch-to-zoom)
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5.0,
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
          ),
          // Bouton fermer
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Marqueur cadenas compact ─────────────────────────────────────────────────

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
    final pct = (progress * 100).toStringAsFixed(0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 13, color: Color(0xFF8FA8C0)),
            const SizedBox(width: 5),
            // Barre de progression
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                width: 40,
                height: 5,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFFE2EAF4),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB300)),
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$pct%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5A6A82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bouton épingle personnel ─────────────────────────────────────────────────

class _PinButton extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool hasActiveFilter;

  const _PinButton({
    required this.onTap,
    required this.onLongPress,
    required this.hasActiveFilter,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Text('📍', style: TextStyle(fontSize: 20)),
            ),
          ),
          // Badge filtre actif
          if (hasActiveFilter)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Clustering des pins personnels ───────────────────────────────────────────

class _PinGroup {
  final List<PersonalPin> pins;
  final LatLng center;
  const _PinGroup({required this.pins, required this.center});
}

class _PinClusterLayer extends StatelessWidget {
  final List<PersonalPin> pins;
  final Set<String>? emotionFilter;
  final MapController mapController;

  const _PinClusterLayer({
    required this.pins,
    required this.emotionFilter,
    required this.mapController,
  });

  // Rayon de clustering en degrés selon le zoom (distance carrée utilisée)
  static double _clusterRadius(double zoom) {
    if (zoom >= 16) return 0.0003;
    if (zoom >= 15) return 0.0006;
    if (zoom >= 14) return 0.0012;
    if (zoom >= 13) return 0.0025;
    return 0.005;
  }

  List<_PinGroup> _cluster(List<PersonalPin> filtered, double zoom) {
    final r2 = _clusterRadius(zoom);
    final groups = <_PinGroup>[];
    final assigned = <String>{};

    for (final pin in filtered) {
      if (assigned.contains(pin.id)) continue;
      final nearby = filtered.where((p) {
        if (assigned.contains(p.id)) return false;
        final dlat = pin.latitude - p.latitude;
        final dlon = pin.longitude - p.longitude;
        return (dlat * dlat + dlon * dlon) <= r2 * r2;
      }).toList();
      for (final p in nearby) assigned.add(p.id);
      final lat = nearby.map((p) => p.latitude).reduce((a, b) => a + b) / nearby.length;
      final lon = nearby.map((p) => p.longitude).reduce((a, b) => a + b) / nearby.length;
      groups.add(_PinGroup(pins: nearby, center: LatLng(lat, lon)));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MapEvent>(
      stream: mapController.mapEventStream,
      builder: (context, _) {
        double zoom;
        try { zoom = mapController.camera.zoom; } catch (_) { zoom = 15.0; }

        final filtered = emotionFilter == null
            ? pins
            : pins.where((p) => emotionFilter!.contains(p.label)).toList();

        final groups = _cluster(filtered, zoom);

        return MarkerLayer(
          markers: groups.map((g) => Marker(
            point: g.center,
            width: 44,
            height: 44,
            child: g.pins.length == 1
                ? _PersonalPinMarker(
                    pin: g.pins.first,
                    onTap: () => _showPinDetail(context, g.pins.first),
                  )
                : _ClusterMarker(count: g.pins.length),
          )).toList(),
        );
      },
    );
  }
}

class _ClusterMarker extends StatelessWidget {
  final int count;
  const _ClusterMarker({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF7C3AED),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.40),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ─── Sheet de filtrage par émotion ────────────────────────────────────────────

class _PinFilterSheet extends StatefulWidget {
  final List<PersonalPin> pins;
  final Set<String>? activeFilter;

  const _PinFilterSheet({required this.pins, required this.activeFilter});

  @override
  State<_PinFilterSheet> createState() => _PinFilterSheetState();
}

class _PinFilterSheetState extends State<_PinFilterSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.activeFilter ?? {});
  }

  @override
  Widget build(BuildContext context) {
    // Compte les pins par émotion
    final counts = <String, ({String emoji, int count})>{};
    for (final pin in widget.pins) {
      final entry = counts[pin.label];
      counts[pin.label] = (
        emoji: pin.emoji,
        count: (entry?.count ?? 0) + 1,
      );
    }
    final emotions = counts.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Text('Filtrer mes souvenirs', style: AppText.sectionTitle),
          const SizedBox(height: 4),
          Text(
            'Appui long sur 📍 pour ouvrir ce filtre',
            style: AppText.label.copyWith(letterSpacing: 0),
          ),
          const SizedBox(height: 16),

          // ── Pill "Tout afficher" ──────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _selected.clear()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _selected.isEmpty ? AppColors.terraLight : AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selected.isEmpty ? AppColors.terra : AppColors.sandLight,
                  width: _selected.isEmpty ? 2 : 1,
                ),
              ),
              child: Text(
                'Tout afficher — ${widget.pins.length} souvenir${widget.pins.length > 1 ? 's' : ''}',
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                  letterSpacing: 0,
                  fontWeight: _selected.isEmpty ? FontWeight.bold : FontWeight.w500,
                  color: _selected.isEmpty ? AppColors.terra : AppColors.sand,
                ),
              ),
            ),
          ),

          // ── Pills émotions ────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: emotions.map((e) {
              final isOn = _selected.contains(e.key);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isOn) _selected.remove(e.key);
                  else _selected.add(e.key);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isOn ? const Color(0xFF7C3AED).withValues(alpha: 0.10) : AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOn ? const Color(0xFF7C3AED) : AppColors.sandLight,
                      width: isOn ? 1.8 : 1,
                    ),
                  ),
                  child: Text(
                    '${e.value.emoji} ${e.key}  ${e.value.count}',
                    style: AppText.label.copyWith(
                      letterSpacing: 0,
                      fontWeight: isOn ? FontWeight.bold : FontWeight.w500,
                      color: isOn ? const Color(0xFF7C3AED) : AppColors.ink.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // ── Bouton appliquer ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(_selected),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  _selected.isEmpty ? 'Afficher tout' : 'Appliquer le filtre',
                  textAlign: TextAlign.center,
                  style: AppText.metric.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Marqueur pin personnel sur la carte ──────────────────────────────────────

void _showPinDetail(BuildContext context, PersonalPin pin) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PinDetailSheet(pin: pin),
  );
}

class _PersonalPinMarker extends StatelessWidget {
  final PersonalPin pin;
  final VoidCallback onTap;

  const _PersonalPinMarker({required this.pin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF7C3AED),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.40),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(
          child: Text(pin.emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}

// ─── Fiche détail d'un pin personnel ──────────────────────────────────────────

class _PinDetailSheet extends ConsumerWidget {
  final PersonalPin pin;
  const _PinDetailSheet({required this.pin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = pin.createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    // Résolution du chemin photo : pin.photoPath est un nom de fichier simple
    final docsDir  = ref.watch(appDocsDirProvider).valueOrNull;
    final fullPath = (pin.photoPath != null && docsDir != null)
        ? '$docsDir/${pin.photoPath}'
        : null;
    final photoExists = fullPath != null && File(fullPath).existsSync();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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

          // ── Photo (aperçu cliquable → plein écran) ────────────────────────
          if (photoExists) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _PinFullScreenPhoto(path: fullPath),
                ),
              ),
              child: Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(fullPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.sandLight,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40, color: AppColors.sand),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Indicateur "tap pour agrandir"
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.50),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Agrandir',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Émotion + date ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  '${pin.emoji}  ${pin.label}',
                  style: AppText.label.copyWith(
                    letterSpacing: 0,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                dateStr,
                style: AppText.label.copyWith(
                  letterSpacing: 0,
                  color: AppColors.sand,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Bouton supprimer ──────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                ref.read(personalPinProvider.notifier).remove(pin.id);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Supprimer ce souvenir'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.terra,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bannière milestone km ────────────────────────────────────────────────────

class _KmMilestoneBanner extends StatefulWidget {
  final double km;
  final WalkerAnimal animal;
  final VoidCallback onDone;

  const _KmMilestoneBanner({
    required this.km,
    required this.animal,
    required this.onDone,
  });

  @override
  State<_KmMilestoneBanner> createState() => _KmMilestoneBannerState();
}

class _KmMilestoneBannerState extends State<_KmMilestoneBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    _ctrl.forward();
    Future.delayed(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kmLabel = widget.km >= 1
        ? '${widget.km.toInt()} km'
        : '${(widget.km * 1000).toInt()} m';
    final message = kMilestoneMessages[widget.km.toInt()] ?? 'Nouveau palier atteint !';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: _dismiss,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.animal.color,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: widget.animal.color.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(widget.animal.emoji,
                        style: const TextStyle(fontSize: 32)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$kmLabel parcourus !',
                            style: AppText.metric.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            message,
                            style: AppText.label.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0,
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
      ),
    );
  }
}

