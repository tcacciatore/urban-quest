import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/city.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FogWalkLayer — brouillard nuageux percé le long du tracé GPS.
//
// Fond bleu-gris + texture de puffs blancs → aspect nuageux.
// BlendMode.clear sur les zones marchées pour révéler la carte.
// ─────────────────────────────────────────────────────────────────────────────

class FogWalkLayer extends StatelessWidget {
  final List<City> cities;
  /// Points du rainbow accompli pour la journée (vide si pas encore atteint).
  final List<LatLng> completedRainbow;

  const FogWalkLayer({
    super.key,
    required this.cities,
    this.completedRainbow = const [],
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return OverflowBox(
      minWidth: camera.size.width,
      maxWidth: camera.size.width,
      minHeight: camera.size.height,
      maxHeight: camera.size.height,
      child: Transform.rotate(
        angle: camera.rotationRad,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _FogPainter(
              cities: cities,
              camera: camera,
              completedRainbow: completedRainbow,
            ),
            size: camera.size,
          ),
        ),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _FogPainter extends CustomPainter {
  final List<City> cities;
  final MapCamera camera;
  final List<LatLng> completedRainbow;

  // Couleur de base du brouillard — totalement opaque
  static const _fogBase = Color(0xFF1E2D42);
  // Puffs nuageux bleutés semi-transparents
  static const _puffColor = Color(0x20FFFFFF);
  static const _puffColor2 = Color(0x10A8C4DC);

  static const _revealRadiusMeters = 25.0;

  // Offsets déterministes pour les puffs (évite toute aléatoire au rendu)
  static const List<double> _offsets = [
    0.20, 0.72, 0.41, 0.85, 0.13, 0.58, 0.34,
    0.77, 0.29, 0.56, 0.08, 0.91, 0.47, 0.63,
    0.50, 0.18, 0.82, 0.39, 0.68, 0.23, 0.61,
    0.14, 0.86, 0.52, 0.31, 0.73, 0.44, 0.93,
    0.62, 0.21, 0.49, 0.76, 0.16, 0.57, 0.83,
    0.37, 0.66, 0.09, 0.53, 0.88, 0.27, 0.71,
  ];

  _FogPainter({
    required this.cities,
    required this.camera,
    required this.completedRainbow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    for (final city in cities) {
      if (city.polygon.length < 3) continue;
      final cityPath = _buildPath(city.polygon);
      final center   = _centroid(city.polygon);

      canvas.save();
      canvas.clipPath(cityPath);

      // ── 1. Fond brouillard ──────────────────────────────────────────────
      canvas.drawPath(cityPath, Paint()..color = _fogBase);

      // ── 2. Texture nuageuse (puffs blancs) ─────────────────────────────
      _drawCloudTexture(canvas, city.polygon, center);

      // ── 3. Révèle les zones marchées (BlendMode.clear) ─────────────────
      if (city.walkedPoints.isNotEmpty) {
        final revealPx = _metersToPixels(_revealRadiusMeters, center);
        final clearPaint = Paint()
          ..blendMode = BlendMode.clear;
        for (final p in city.walkedPoints) {
          canvas.drawCircle(_toOffset(p), revealPx, clearPaint);
        }
      }

      canvas.restore();
    }

    canvas.restore(); // composite le fog sur le canvas principal

    // ── 4. Rainbow accompli (permanent pour la journée) ──────────────────────
    if (completedRainbow.isNotEmpty) {
      _drawColoredSegment(canvas, completedRainbow, forceFullRainbow: true);
    }

    // ── 5. Trainée en cours (uniquement si c'est une nouvelle session) ───────
    _drawRecentTrail(canvas);
  }

  /// Retourne le dernier segment continu de [points].
  /// Une rupture est détectée quand deux points consécutifs sont à > [_maxGapMeters].
  static const _maxGapMeters = 24.0; // ≈ 3× l'intervalle d'échantillonnage (8 m)
  List<LatLng> _lastContinuousSegment(List<LatLng> points) {
    if (points.length < 2) return points;
    const distCalc = Distance();
    int startIdx = points.length - 1;
    while (startIdx > 0) {
      if (distCalc(points[startIdx - 1], points[startIdx]) > _maxGapMeters) break;
      startIdx--;
    }
    return points.sublist(startIdx);
  }

  static const _sampleMeters     = 8.0;
  static const _trailStartMeters = 100.0;  // en dessous : pas de trainée colorée
  static const _fullRainbowMeters = 1000.0;

  /// Dessine la trainée en cours SEULEMENT si elle est différente du rainbow accompli.
  /// - Pas de rainbow accompli → trainée progressive toujours visible
  /// - Rainbow accompli + même session (même premier point) → on ne dessine rien
  ///   (le rainbow permanent est déjà affiché)
  /// - Rainbow accompli + nouvelle session (GPS coupé puis repris) → trainée progressive
  void _drawRecentTrail(Canvas canvas) {
    for (final city in cities) {
      if (city.walkedPoints.length < 2) continue;

      final recent = _lastContinuousSegment(city.walkedPoints);
      if (recent.isEmpty) continue;

      // Si le rainbow est accompli ET que cette session en fait partie → on skip
      if (completedRainbow.isNotEmpty) {
        final sameRun = recent.first.latitude  == completedRainbow.first.latitude &&
                        recent.first.longitude == completedRainbow.first.longitude;
        if (sameRun) continue;
      }

      // Trainée visible seulement à partir de 100 m continus
      if (recent.length * _sampleMeters < _trailStartMeters) continue;

      _drawColoredSegment(canvas, recent, city: city, forceFullRainbow: false);
    }
  }

  /// Dessine [points] avec un dégradé progressif (bleu → arc-en-ciel complet à 1 000 m)
  /// ou en arc-en-ciel complet forcé si [forceFullRainbow] est vrai.
  void _drawColoredSegment(
    Canvas canvas,
    List<LatLng> points, {
    City? city,
    required bool forceFullRainbow,
  }) {
    if (points.isEmpty) return;

    // Centre pour la conversion mètres → pixels
    final center   = city != null
        ? _centroid(city.polygon)
        : _midpoint(points);
    final revealPx = _metersToPixels(_revealRadiusMeters, center);
    final count    = points.length;

    // Plage de teintes : 0°–270° selon la longueur, ou forcée à 270°
    final hueRange = forceFullRainbow
        ? 270.0
        : ((count * _sampleMeters) / _fullRainbowMeters * 270.0).clamp(0.0, 270.0);

    // Clip au polygone de la ville si disponible, sinon pas de clip
    if (city != null) {
      canvas.save();
      canvas.clipPath(_buildPath(city.polygon));
    }

    for (int i = 0; i < count; i++) {
      final t   = count == 1 ? 1.0 : i / (count - 1);
      final hue = t * hueRange;

      canvas.drawCircle(
        _toOffset(points[i]),
        revealPx * 0.85,
        Paint()
          ..color = HSVColor.fromAHSV(0.80, hue, 1.0, 1.0).toColor()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, revealPx * 0.30),
      );
    }

    if (city != null) canvas.restore();
  }

  LatLng _midpoint(List<LatLng> pts) {
    final lat = pts.map((p) => p.latitude ).reduce((a, b) => a + b) / pts.length;
    final lon = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lon);
  }

  /// Génère une grille de puffs nuageux déterministes dans le polygone.
  void _drawCloudTexture(Canvas canvas, List<LatLng> polygon, LatLng center) {
    double minLat = polygon.first.latitude,  maxLat = polygon.first.latitude;
    double minLon = polygon.first.longitude, maxLon = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    const rows = 6, cols = 7;
    final latStep = (maxLat - minLat) / rows;
    final lonStep = (maxLon - minLon) / cols;

    // Rayon de base des puffs ≈ 200 m
    final baseRadius = _metersToPixels(200, center);

    final paint1 = Paint()
      ..color = _puffColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    final paint2 = Paint()
      ..color = _puffColor2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);

    int idx = 0;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final off1 = _offsets[idx % _offsets.length];
        final off2 = _offsets[(idx + 1) % _offsets.length];
        final off3 = _offsets[(idx + 2) % _offsets.length];
        idx += 3;

        final lat = minLat + latStep * r + latStep * off1 * 0.6;
        final lon = minLon + lonStep * c + lonStep * off2 * 0.6;
        final pos = LatLng(lat, lon);
        if (!_pip(pos, polygon)) continue;

        final offset = _toOffset(pos);
        final radius = baseRadius * (0.6 + off3 * 0.9);

        canvas.drawCircle(offset, radius,         paint1);
        canvas.drawCircle(offset, radius * 0.65,  paint2);
      }
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  ui.Path _buildPath(List<LatLng> polygon) {
    final path = ui.Path();
    for (int i = 0; i < polygon.length; i++) {
      final o = _toOffset(polygon[i]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    return path..close();
  }

  Offset _toOffset(LatLng latLng) => camera.getOffsetFromOrigin(latLng);

  double _metersToPixels(double meters, LatLng center) {
    const dist = Distance();
    final east = dist.offset(center, meters, 90);
    final cPx  = camera.projectAtZoom(center);
    final ePx  = camera.projectAtZoom(east);
    return (ePx.dx - cPx.dx).abs();
  }

  LatLng _centroid(List<LatLng> polygon) {
    final lat = polygon.map((p) => p.latitude ).reduce((a, b) => a + b) / polygon.length;
    final lon = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
    return LatLng(lat, lon);
  }

  bool _pip(LatLng point, List<LatLng> polygon) {
    int crossings = 0;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }

  @override
  bool shouldRepaint(_FogPainter old) {
    if (old.camera != camera) return true;
    if (old.completedRainbow.length != completedRainbow.length) return true;
    if (old.cities.length != cities.length) return true;
    for (int i = 0; i < cities.length; i++) {
      if (old.cities[i].walkedPoints.length != cities[i].walkedPoints.length) return true;
    }
    return false;
  }
}
