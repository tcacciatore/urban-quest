import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_colors.dart';
import '../providers/fog_of_war_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FogOfWarLayer — masques de quartier (PolygonLayer simple)
//
// À placer dans FlutterMap(children: [..., FogOfWarLayer(), FogOfWarLabels()])
// ─────────────────────────────────────────────────────────────────────────────

/// Masque sombre sur les quartiers inconnus, teinte parchemin sur les révélés.
class FogOfWarLayer extends ConsumerWidget {
  const FogOfWarLayer({super.key});

  static const _fogColor  = Color(0xBF2C2010);
  static const _tintColor = Color(0x59C8A882);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fogOfWarProvider);

    debugPrint('[FogOfWarLayer] build: ${state.quarters.length} quartiers');

    final polygons = state.quarters.values.map((q) {
      final color = q.isRevealed ? _tintColor : _fogColor;
      return Polygon(
        points: q.polygon,
        color: color,
        borderColor: q.isRevealed ? const Color(0x33C8A882) : Colors.transparent,
        borderStrokeWidth: q.isRevealed ? 0.8 : 0,
      );
    }).toList();

    return PolygonLayer(polygons: polygons, simplificationTolerance: 0);
  }
}

// ─── Labels DM Mono sur les quartiers révélés ─────────────────────────────────

/// Labels sur les polygones : nom si révélé, mention verrouillée sinon.
class FogOfWarLabels extends ConsumerWidget {
  const FogOfWarLabels({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fogOfWarProvider);

    final markers = state.quarters.values.map((q) {
      final center = _centroid(q.polygon);

      if (q.isRevealed) {
        return Marker(
          point: center,
          width: 140,
          height: 24,
          child: Center(
            child: Text(
              q.name.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmMono(
                fontSize: 8,
                fontWeight: FontWeight.w500,
                color: AppColors.ink.withValues(alpha: 0.50),
                letterSpacing: 1.0,
              ),
            ),
          ),
        );
      }

      // Zone non révélée avec seuil > 1 → mention verrouillée
      if (q.requiredHunts > 1) {
        final done = q.huntCount.clamp(0, q.requiredHunts);
        return Marker(
          point: center,
          width: 160,
          height: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔒', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(
                '$done / ${q.requiredHunts} chasses requises',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      }

      return null;
    }).whereType<Marker>().toList();

    return MarkerLayer(markers: markers, rotate: false);
  }

  LatLng _centroid(List<LatLng> polygon) {
    if (polygon.isEmpty) return const LatLng(0, 0);
    final lat = polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final lon = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
    return LatLng(lat, lon);
  }
}

