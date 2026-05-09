import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/walker_profile_provider.dart';

/// Marqueur utilisateur avec cône directionnel et emoji animal.
/// [heading] : cap en degrés (0 = Nord, sens horaire).
class UserDirectionalMarker extends ConsumerWidget {
  final double heading;

  const UserDirectionalMarker({super.key, required this.heading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animal = ref.watch(walkerProfileProvider).animal;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Cône directionnel
        Transform.rotate(
          angle: heading * math.pi / 180,
          child: Align(
            alignment: const Alignment(0, -0.9),
            child: CustomPaint(
              size: const Size(14, 18),
              painter: _ConePainter(color: animal.color),
            ),
          ),
        ),
        // Cercle coloré + emoji
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: animal.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: animal.color.withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              animal.emoji,
              style: const TextStyle(fontSize: 16, height: 1),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConePainter extends CustomPainter {
  final Color color;
  const _ConePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          color.withValues(alpha: 0.85),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = ui.Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ConePainter old) => old.color != color;
}
