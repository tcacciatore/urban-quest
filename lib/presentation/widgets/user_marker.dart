import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Marqueur utilisateur avec cône directionnel.
/// [heading] : cap en degrés (0 = Nord, sens horaire).
class UserDirectionalMarker extends StatelessWidget {
  final double heading;

  const UserDirectionalMarker({super.key, required this.heading});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: heading * math.pi / 180,
          child: Align(
            alignment: const Alignment(0, -0.9),
            child: CustomPaint(
              size: const Size(14, 18),
              painter: _ConePainter(),
            ),
          ),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.terra,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
      ],
    );
  }
}

class _ConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AppColors.terra.withValues(alpha: 0.9),
          AppColors.terra.withValues(alpha: 0.0),
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
  bool shouldRepaint(_ConePainter old) => false;
}
