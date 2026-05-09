import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_text.dart';
import '../../providers/walker_profile_provider.dart';

// Message d'éveil selon la rareté de l'animal
String _awakeMessage(WalkerAnimal animal) {
  if (animal.name == 'Pierre') return 'Bienvenue. L\'aventure commence ici.';
  switch (animal.rarity) {
    case ProfileRarity.commun:
      return 'La ville s\'éveille doucement…';
    case ProfileRarity.rare:
      return 'La ville a des secrets pour toi…';
    case ProfileRarity.epique:
      return 'La ville tremble sur ton passage…';
    case ProfileRarity.legendaire:
      return 'La légende reprend sa marche…';
    case ProfileRarity.mythique:
      return 'Le mythe s\'éveille. La ville retient son souffle.';
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animal = ref.watch(walkerProfileProvider).animal;
    final message = _awakeMessage(animal);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1208),
                animal.color.withValues(alpha: 0.35),
                const Color(0xFF0D1A14),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Grille de points façon carte
              Positioned.fill(child: _MapDots()),

              // Contenu centré
              Center(
                child: Opacity(
                  opacity: _fadeIn.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Halo derrière l'emoji
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 110 * _pulse.value,
                            height: 110 * _pulse.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: animal.color.withValues(alpha: 0.18),
                            ),
                          ),
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: animal.color.withValues(alpha: 0.12),
                            ),
                          ),
                          Transform.scale(
                            scale: _pulse.value,
                            child: Text(
                              animal.emoji,
                              style: const TextStyle(fontSize: 56),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // Nom de l'animal
                      Text(
                        animal.name.toUpperCase(),
                        style: AppText.label.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                          letterSpacing: 4,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Message d'éveil
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: AppText.sectionTitle.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 18,
                            fontWeight: FontWeight.w300,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Indicateur discret en bas
              Positioned(
                bottom: 52,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: _fadeIn.value,
                  child: _PulsingDots(color: animal.color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Grille de points façon carte ────────────────────────────────────────────

class _MapDots extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MapDotsPainter());
  }
}

class _MapDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    final cols = (size.width / spacing).ceil() + 1;
    final rows = (size.height / spacing).ceil() + 1;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final offset = r.isOdd ? spacing / 2 : 0.0;
        canvas.drawCircle(
          Offset(c * spacing + offset, r * spacing),
          1.5,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MapDotsPainter old) => false;
}

// ─── Trois points pulsants ────────────────────────────────────────────────────

class _PulsingDots extends StatefulWidget {
  final Color color;
  const _PulsingDots({required this.color});

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = ((_ctrl.value - i * 0.25) % 1.0);
            final opacity = (0.2 + 0.8 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2)).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}
