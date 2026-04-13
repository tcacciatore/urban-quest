import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/city.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FogWalkLayer — brouillard percé le long du tracé GPS de l'utilisateur.
//
// Utilise un CustomPainter avec BlendMode.clear pour "effacer" des cercles
// de 50 m autour de chaque point parcouru, révélant la carte sous-jacente.
// ─────────────────────────────────────────────────────────────────────────────

class FogWalkLayer extends StatelessWidget {
  final List<City> cities;

  const FogWalkLayer({super.key, required this.cities});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    // Reproduit MobileLayerTransformer (non exporté) pour que le layer
    // suive les tuiles lors des zooms/pans/rotations, exactement comme PolygonLayer.
    return OverflowBox(
      minWidth: camera.size.width,
      maxWidth: camera.size.width,
      minHeight: camera.size.height,
      maxHeight: camera.size.height,
      child: Transform.rotate(
        angle: camera.rotationRad,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _FogPainter(cities: cities, camera: camera),
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

  static const _lockedColor        = Color(0x66FF3030); // rouge semi-transparent
  static const _revealedColor      = Color(0x6640CC60); // vert semi-transparent
  static const _revealRadiusMeters = 120.0;

  _FogPainter({required this.cities, required this.camera});

  @override
  void paint(Canvas canvas, Size size) {
    // Un seul saveLayer pour tous les polygones → une seule allocation GPU.
    canvas.saveLayer(Offset.zero & size, Paint());

    for (final city in cities) {
      if (city.polygon.length < 3) continue;

      final cityPath = _buildPath(city.polygon);

      canvas.save();
      canvas.clipPath(cityPath);

      // 1. Rouge sur toute la zone verrouillée
      canvas.drawPath(cityPath, Paint()..color = _lockedColor);

      // 2. Vert sur les zones parcourues (remplace le rouge, BlendMode.src)
      if (city.walkedPoints.isNotEmpty) {
        final center   = _centroid(city.polygon);
        final revealPx = _metersToPixels(_revealRadiusMeters, center);

        final greenPaint = Paint()
          ..blendMode  = BlendMode.src
          ..color      = _revealedColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, revealPx * 0.30);

        for (final p in city.walkedPoints) {
          canvas.drawCircle(_toOffset(p), revealPx, greenPaint);
        }
      }

      canvas.restore();
    }

    canvas.restore(); // fusionne le layer avec la carte
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  ui.Path _buildPath(List<LatLng> polygon) {
    final path = ui.Path();
    for (int i = 0; i < polygon.length; i++) {
      final o = _toOffset(polygon[i]);
      if (i == 0) path.moveTo(o.dx, o.dy);
      else path.lineTo(o.dx, o.dy);
    }
    return path..close();
  }

  Offset _toOffset(LatLng latLng) =>
      camera.getOffsetFromOrigin(latLng);

  /// Convertit une distance en mètres en pixels au zoom courant.
  /// Utilise la différence de projection (l'origine s'annule).
  double _metersToPixels(double meters, LatLng center) {
    const dist = Distance();
    final east = dist.offset(center, meters, 90); // 90° = Est
    final cPx  = camera.projectAtZoom(center);
    final ePx  = camera.projectAtZoom(east);
    return (ePx.dx - cPx.dx).abs();
  }

  LatLng _centroid(List<LatLng> polygon) {
    final lat = polygon.map((p) => p.latitude ).reduce((a, b) => a + b) / polygon.length;
    final lon = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
    return LatLng(lat, lon);
  }

  @override
  bool shouldRepaint(_FogPainter old) {
    if (old.camera != camera) return true;
    if (old.cities.length != cities.length) return true;
    for (int i = 0; i < cities.length; i++) {
      if (old.cities[i].walkedPoints.length != cities[i].walkedPoints.length) {
        return true;
      }
    }
    return false;
  }
}
