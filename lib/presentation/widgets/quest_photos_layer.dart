import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/quarter.dart';
import '../providers/fog_of_war_providers.dart';
import '../providers/quest_history_providers.dart';

/// Affiche les photos des chasses complétées sur les zones révélées.
class QuestPhotosLayer extends ConsumerWidget {
  const QuestPhotosLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fog = ref.watch(fogOfWarProvider);
    final historyAsync = ref.watch(questHistoryProvider);

    final revealedQuarters =
        fog.quarters.values.where((q) => q.isRevealed).toList();

    if (revealedQuarters.isEmpty) return const SizedBox.shrink();

    final entries = historyAsync.valueOrNull ?? [];
    final markers = <Marker>[];

    for (final entry in entries) {
      if (!entry.wasCompleted) continue;
      if (!entry.hasCoordinates) continue;
      if (entry.photoPath == null) continue;
      if (!File(entry.photoPath!).existsSync()) continue;

      final point = LatLng(entry.latitude!, entry.longitude!);
      if (!_inAnyRevealedZone(point, revealedQuarters)) continue;

      markers.add(Marker(
        point: point,
        width: 52,
        height: 52,
        child: _PhotoPin(photoPath: entry.photoPath!),
      ));
    }

    if (markers.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(markers: markers);
  }

  bool _inAnyRevealedZone(LatLng point, List<Quarter> quarters) {
    for (final q in quarters) {
      if (_pip(point, q.polygon)) return true;
    }
    return false;
  }

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
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }
}

class _PhotoPin extends StatelessWidget {
  final String photoPath;
  const _PhotoPin({required this.photoPath});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Bulle photo
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
            image: DecorationImage(
              image: FileImage(File(photoPath)),
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Pointe en bas
        Positioned(
          bottom: 0,
          child: CustomPaint(
            size: const Size(10, 8),
            painter: _PinTailPainter(),
          ),
        ),
      ],
    );
  }
}

class _PinTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTailPainter _) => false;
}
