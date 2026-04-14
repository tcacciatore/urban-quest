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
import '../../providers/poi_providers.dart';
import '../../widgets/poi_layer.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  String? _selectedCityId;
  String? _selectedPoiId;
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
      _selectedPoiId = null; // désélectionne le POI sur tap carte
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
      drawer: AppDrawer(
        selectedCityId: _selectedCityId,
        onCitySelected: (cityId, center) {
          setState(() => _selectedCityId = cityId);
          _animatedMove(center, 14.0);
        },
      ),
      body: Stack(
        children: [
          // Carte plein écran
          positionAsync.when(
            data: (position) => _buildMap(position, routeState, cityFog, poiState, _selectedCityId, _selectedPoiId),
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
                if (pos != null) _animatedMove(pos, 15.0);
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

          // Bannière changement de ville
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _CityChangeBanner(),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(LatLng position, AsyncValue<RouteState?> routeState, CityFogState cityFog, PoiState poiState, String? selectedCityId, String? selectedPoiId) {
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
        // ── City Fog — brouillard percé par la marche (toutes les villes) ──
        FogWalkLayer(cities: lockedCities),
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
          key: ValueKey(cityFog.cities.values
              .fold<int>(0, (s, c) => s + c.walkedPoints.length)),
          rotate: false,
          markers: cityFog.cities.values
              .where((c) => !c.isUnlocked)
              .map((c) {
                final center = _fogCentroid(c.polygon);
                final pct = (c.revealedRatio * 100).round();
                final target = (City.requiredRatio * 100).round();
                return Marker(
                  point: center,
                  width: 200,
                  height: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔒', style: TextStyle(fontSize: 26)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$pct\u202f/\u202f$target\u202f% explorés',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.95),
                            letterSpacing: 0.3,
                          ),
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
        // ── POIs — au premier plan, par-dessus fog et polygones de ville ────
        PoiLayer(
          pois: poiState.allPois,
          selectedPoiId: selectedPoiId,
          onPoiTapped: (id) => setState(() => _selectedPoiId = id),
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
