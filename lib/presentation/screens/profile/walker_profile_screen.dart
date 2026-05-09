import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text.dart';
import '../../providers/walker_profile_provider.dart';

// ─── Badge de rareté (exporté pour home_screen) ───────────────────────────────

class RarityBadge extends StatelessWidget {
  final ProfileRarity rarity;
  final bool onDark;
  const RarityBadge({super.key, required this.rarity, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final color  = onDark ? Colors.white : rarity.color;
    final bgAlpha = onDark ? 0.22 : 0.12;
    final bdAlpha = onDark ? 0.60 : (rarity == ProfileRarity.mythique ? 0.70 : 0.40);
    final stars  = '✦' * rarity.stars;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: bdAlpha),
          width: rarity == ProfileRarity.mythique ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stars, style: TextStyle(fontSize: 8, color: color, letterSpacing: 1.5)),
          const SizedBox(width: 4),
          Text(
            rarity.label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Écran principal ──────────────────────────────────────────────────────────

class WalkerProfileScreen extends ConsumerStatefulWidget {
  const WalkerProfileScreen({super.key});

  @override
  ConsumerState<WalkerProfileScreen> createState() => _WalkerProfileScreenState();
}

class _WalkerProfileScreenState extends ConsumerState<WalkerProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(walkerProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _ProfileHeader(profile: profile, pulse: _pulse)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 20),

                // ── Description ───────────────────────────────────────────
                _DescriptionCard(profile: profile),
                const SizedBox(height: 16),

                // ── Prochaine évolution ───────────────────────────────────
                if (profile.nextEvolution != null) ...[
                  _NextEvolutionCard(evo: profile.nextEvolution!),
                  const SizedBox(height: 16),
                ],

                // ── Axes ──────────────────────────────────────────────────
                _ScoreSection(profile: profile),
                const SizedBox(height: 16),

                // ── Stats ─────────────────────────────────────────────────
                _StatsGrid(profile: profile),
                const SizedBox(height: 24),

                // ── Galerie ───────────────────────────────────────────────
                _AllProfilesSection(profile: profile),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final WalkerProfile profile;
  final Animation<double> pulse;
  const _ProfileHeader({required this.profile, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final animal = profile.animal;
    final top    = MediaQuery.of(context).padding.top;
    final isMythique = animal.rarity == ProfileRarity.mythique;

    return Container(
      height: 270 + top,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [animal.color, animal.color.withValues(alpha: 0.65), AppColors.parchment],
          stops: const [0.0, 0.60, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Halo mythique
          if (isMythique)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: pulse,
                builder: (_, __) => Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.2,
                      colors: [
                        animal.color.withValues(alpha: 0.18 * pulse.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Bouton retour
          Positioned(
            top: top + 12, left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),

          // Contenu centré
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: top * 0.5),

                AnimatedBuilder(
                  animation: pulse,
                  builder: (_, __) => Transform.scale(
                    scale: 1.0 + (isMythique ? 0.10 : 0.05) * pulse.value,
                    child: Text(animal.emoji, style: const TextStyle(fontSize: 84)),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  animal.title,
                  style: AppText.sectionTitle.copyWith(
                    color: Colors.white, fontSize: 22,
                    shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10)],
                  ),
                ),

                const SizedBox(height: 4),
                Text(
                  animal.name,
                  style: AppText.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.80), fontSize: 14,
                  ),
                ),

                const SizedBox(height: 10),
                RarityBadge(rarity: animal.rarity, onDark: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Description ─────────────────────────────────────────────────────────────

class _DescriptionCard extends StatelessWidget {
  final WalkerProfile profile;
  const _DescriptionCard({required this.profile});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.sandLight),
    ),
    child: Text(
      profile.animal.description,
      style: AppText.body.copyWith(fontSize: 15, height: 1.6, color: AppColors.ink.withValues(alpha: 0.85)),
      textAlign: TextAlign.center,
    ),
  );
}

// ─── Prochaine évolution ──────────────────────────────────────────────────────

class _NextEvolutionCard extends StatelessWidget {
  final ProfileEvolution evo;
  const _NextEvolutionCard({required this.evo});

  @override
  Widget build(BuildContext context) {
    final color    = evo.animal.color;
    final progress = evo.overallProgress;
    final missing  = evo.conditions.where((c) => !c.isMet).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.04)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('PROCHAINE ÉVOLUTION',
                  style: AppText.label.copyWith(color: color, letterSpacing: 1.5)),
              const Spacer(),
              RarityBadge(rarity: evo.animal.rarity),
            ],
          ),
          const SizedBox(height: 14),

          // Animal + progression globale
          Row(
            children: [
              Text(evo.animal.emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(evo.animal.title,
                        style: AppText.metric.copyWith(fontSize: 15, color: AppColors.ink)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: color.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(progress * 100).round()}% accompli',
                      style: AppText.label.copyWith(
                        color: color, letterSpacing: 0.5, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Conditions détaillées
          ...evo.conditions.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(c.emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(c.label,
                          style: AppText.body.copyWith(fontSize: 12, color: AppColors.ink.withValues(alpha: 0.75))),
                    ),
                    Text(
                      c.isMet
                          ? '✓'
                          : '${c.current.toStringAsFixed(c.current < 10 ? 1 : 0)} / ${c.target.toStringAsFixed(0)} ${c.unit}',
                      style: AppText.metric.copyWith(
                        fontSize: 12,
                        color: c.isMet ? const Color(0xFF1A6B52) : AppColors.ink.withValues(alpha: 0.55),
                        fontWeight: c.isMet ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: c.progress,
                    minHeight: 5,
                    backgroundColor: AppColors.sandLight,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        c.isMet ? const Color(0xFF1A6B52) : color),
                  ),
                ),
              ],
            ),
          )),

          // Message "il te manque..."
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _missingText(missing),
                style: AppText.body.copyWith(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600, height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _missingText(List<EvolutionCondition> missing) {
    final parts = missing.map((c) {
      final n = c.remaining;
      final v = n < 10 ? n.toStringAsFixed(1) : n.toStringAsFixed(0);
      return '$v ${c.unit} de ${c.label.toLowerCase()}';
    }).toList();

    if (parts.length == 1) return 'Il te manque ${parts[0]}.';
    final last = parts.removeLast();
    return 'Il te manque ${parts.join(', ')} et $last.';
  }
}

// ─── Axes de score ────────────────────────────────────────────────────────────

// ─── Section radar + explication ─────────────────────────────────────────────

class _ScoreSection extends StatelessWidget {
  final WalkerProfile profile;
  const _ScoreSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    final color  = profile.animal.color;
    final scores = [profile.speed, profile.endurance, profile.exploration,
                    profile.curiosity, profile.activity];
    final ideal  = profile.animal.ideal;
    final why    = _generateWhyText(profile);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.sandLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROFIL', style: AppText.label.copyWith(letterSpacing: 2)),
          const SizedBox(height: 16),

          // ── Radar chart ────────────────────────────────────────────────────
          Center(child: _AnimatedRadar(scores: scores, ideal: ideal, color: color)),
          const SizedBox(height: 14),

          // ── Explication ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              why,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.ink.withValues(alpha: 0.70),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _generateWhyText(WalkerProfile p) {
    if (p.animal.name == 'Pierre') {
      return 'Lance ta première chasse pour découvrir ton profil.';
    }

    // (nom, valeur, trait fort, trait faible)
    final axes = [
      ('speed',       p.speed,       'tu marches vite',                  'ta vitesse est encore modérée'),
      ('endurance',   p.endurance,   'tu accumules les kilomètres',       'tu fais encore de courtes sorties'),
      ('exploration', p.exploration, 'tu explores de nouvelles villes',   'tu restes dans tes quartiers habituels'),
      ('curiosity',   p.curiosity,   'tu poses beaucoup de repères',      'tu poses peu de repères'),
      ('activity',    p.activity,    'tu enchaînes les chasses',          'tu fais encore peu de chasses'),
    ];

    final strong = axes.where((a) => a.$2 >= 0.50).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final weak   = axes.where((a) => a.$2 <= 0.25).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));

    if (strong.isEmpty && weak.isEmpty) {
      return 'Ton profil est encore en construction. Chaque sortie le précise.';
    }
    if (strong.isEmpty) {
      return '${_cap(weak.first.$4).replaceFirst(weak.first.$4[0], weak.first.$4[0].toUpperCase())}.';
    }

    final strongText = strong.take(2).map((a) => a.$3).join(' et ');
    if (weak.isEmpty) return '${_cap(strongText)}.';
    return '${_cap(strongText)}, mais ${weak.first.$4}.';
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── Radar chart animé ────────────────────────────────────────────────────────

class _AnimatedRadar extends StatefulWidget {
  final List<double> scores;
  final List<double>? ideal;
  final Color color;

  const _AnimatedRadar({required this.scores, this.ideal, required this.color});

  @override
  State<_AnimatedRadar> createState() => _AnimatedRadarState();
}

class _AnimatedRadarState extends State<_AnimatedRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    Future.delayed(
        const Duration(milliseconds: 250), () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => CustomPaint(
          size: const Size(220, 220),
          painter: _RadarPainter(
            scores: widget.scores,
            ideal:  widget.ideal,
            color:  widget.color,
            progress: _anim.value,
          ),
        ),
      );
}

class _RadarPainter extends CustomPainter {
  final List<double> scores;
  final List<double>? ideal;
  final Color color;
  final double progress;

  static const _n = 5;
  static const _labels = [
    '🏃 Vitesse', '💪 Endurance', '🗺️ Exploration', '🔍 Curiosité', '⚡ Activité',
  ];

  const _RadarPainter({
    required this.scores,
    this.ideal,
    required this.color,
    required this.progress,
  });

  Offset _vertex(Offset center, double r, int i) {
    final angle = -pi / 2 + i * 2 * pi / _n;
    return Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
  }

  Path _polygonPath(Offset center, double maxR, List<double> values) {
    final path = Path();
    for (int i = 0; i < _n; i++) {
      final pt = _vertex(center, maxR * values[i].clamp(0.0, 1.0), i);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR   = size.width / 2 - 34.0; // marge pour les labels

    // ── Grille ────────────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = AppColors.sandLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int level = 1; level <= 4; level++) {
      final r    = maxR * level / 4;
      final path = Path();
      for (int i = 0; i < _n; i++) {
        final pt = _vertex(center, r, i);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // ── Axes ──────────────────────────────────────────────────────────────────
    final axisPaint = Paint()
      ..color = AppColors.sandLight
      ..strokeWidth = 1.0;
    for (int i = 0; i < _n; i++) {
      canvas.drawLine(center, _vertex(center, maxR, i), axisPaint);
    }

    // ── Profil idéal (ghost) ──────────────────────────────────────────────────
    if (ideal != null) {
      canvas.drawPath(
        _polygonPath(center, maxR, ideal!),
        Paint()
          ..color = color.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        _polygonPath(center, maxR, ideal!),
        Paint()
          ..color = color.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // ── Scores utilisateur (animé) ─────────────────────────────────────────────
    final animated = scores.map((s) => s * progress).toList();
    canvas.drawPath(
      _polygonPath(center, maxR, animated),
      Paint()
        ..color = color.withValues(alpha: 0.30)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      _polygonPath(center, maxR, animated),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Points sur les axes ────────────────────────────────────────────────────
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    for (int i = 0; i < _n; i++) {
      canvas.drawCircle(_vertex(center, maxR * animated[i].clamp(0.0, 1.0), i), 3.5, dotPaint);
    }

    // ── Labels ────────────────────────────────────────────────────────────────
    for (int i = 0; i < _n; i++) {
      final angle  = -pi / 2 + i * 2 * pi / _n;
      final labelR = maxR + 20;
      final lx     = center.dx + labelR * cos(angle);
      final ly     = center.dy + labelR * sin(angle);

      final tp = TextPainter(
        text: TextSpan(
          text: _labels[i],
          style: TextStyle(
            fontSize: 10,
            color: AppColors.ink.withValues(alpha: 0.70),
            fontWeight: FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 72);

      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.progress != progress || old.color != color;
}

// ─── Grille de stats ──────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final WalkerProfile profile;
  const _StatsGrid({required this.profile});

  @override
  Widget build(BuildContext context) {
    final km    = profile.totalKm;
    final kmStr = km >= 10 ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';

    final items = [
      _StatItem('🗺️', kmStr,                       'parcourus'),
      _StatItem('🏙️', '${profile.citiesVisited}',  'quartiers'),
      _StatItem('🏁', '${profile.questsCompleted}', 'chasses'),
      _StatItem('📍', '${profile.pinsCount}',       'souvenirs'),
      _StatItem('🏆', '${profile.trophiesCount}',   'trophées'),
    ];

    return GridView.count(
      crossAxisCount: 3, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.3,
      children: items.map((i) => _StatCard(item: i)).toList(),
    );
  }
}

class _StatItem { final String e, v, l; const _StatItem(this.e, this.v, this.l); }

class _StatCard extends StatelessWidget {
  final _StatItem item;
  const _StatCard({required this.item});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.sandLight),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(item.e, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(item.v, style: AppText.metric.copyWith(fontSize: 15)),
        Text(item.l, style: AppText.label.copyWith(fontSize: 10, letterSpacing: 0.5)),
      ],
    ),
  );
}

// ─── Galerie de tous les profils ──────────────────────────────────────────────

class _AllProfilesSection extends StatelessWidget {
  final WalkerProfile profile;
  const _AllProfilesSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    final raw     = profile.rawStats;
    final current = profile.animal.emoji;

    final tiers = [
      (ProfileRarity.commun,     [pierreAnimal, ...euclideanAnimals.where((a) => a.rarity == ProfileRarity.commun)]),
      (ProfileRarity.rare,       euclideanAnimals.where((a) => a.rarity == ProfileRarity.rare).toList()),
      (ProfileRarity.epique,     euclideanAnimals.where((a) => a.rarity == ProfileRarity.epique).toList()),
      (ProfileRarity.legendaire, thresholdAnimals.where((a) => a.animal.rarity == ProfileRarity.legendaire).map((a) => a.animal).toList()),
      (ProfileRarity.mythique,   thresholdAnimals.where((a) => a.animal.rarity == ProfileRarity.mythique).map((a) => a.animal).toList()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TOUS LES PROFILS', style: AppText.label.copyWith(letterSpacing: 2)),
        const SizedBox(height: 14),
        ...tiers.map((tier) {
          final rarity  = tier.$1;
          final animals = tier.$2;

          // Pour les threshold animals, calculer le progress
          final isThreshold = rarity == ProfileRarity.legendaire || rarity == ProfileRarity.mythique;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                RarityBadge(rarity: rarity),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: rarity.color.withValues(alpha: 0.25), height: 1)),
              ]),
              const SizedBox(height: 10),
              Row(
                children: animals.map((animal) {
                  final isCurrent  = animal.emoji == current;
                  final unlocked   = isThreshold
                      ? thresholdAnimals.firstWhere((t) => t.animal.emoji == animal.emoji).isUnlocked(raw)
                      : true; // euclidean = toujours "accessible"
                  final progress   = isThreshold
                      ? thresholdAnimals.firstWhere((t) => t.animal.emoji == animal.emoji)
                          .toEvolution(raw).overallProgress
                      : 1.0;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _AnimalCard(
                        animal: animal,
                        isCurrent: isCurrent,
                        isUnlocked: unlocked || isCurrent,
                        progress: progress,
                        isMythique: rarity == ProfileRarity.mythique,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          );
        }),
      ],
    );
  }
}

class _AnimalCard extends StatefulWidget {
  final WalkerAnimal animal;
  final bool isCurrent, isUnlocked, isMythique;
  final double progress;
  const _AnimalCard({
    required this.animal, required this.isCurrent,
    required this.isUnlocked, required this.progress,
    required this.isMythique,
  });

  @override
  State<_AnimalCard> createState() => _AnimalCardState();
}

class _AnimalCardState extends State<_AnimalCard> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));
    if (widget.isMythique && !widget.isUnlocked) _shimmer.repeat();
    if (widget.isCurrent) _shimmer.repeat(reverse: true);
  }

  @override
  void dispose() { _shimmer.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color     = widget.animal.color;
    final locked    = !widget.isUnlocked;
    final pct       = (widget.progress * 100).round();

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, child) {
        BoxDecoration decoration;

        if (widget.isCurrent) {
          decoration = BoxDecoration(
            color: color.withValues(alpha: 0.10 + 0.06 * _shimmer.value),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.7 + 0.3 * _shimmer.value), width: 2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25 * _shimmer.value), blurRadius: 10)],
          );
        } else if (widget.isMythique && locked) {
          // Shimmer sur les mythiques non obtenus
          final shimmerColor = Color.lerp(color.withValues(alpha: 0.05), color.withValues(alpha: 0.12), _shimmer.value)!;
          decoration = BoxDecoration(
            color: shimmerColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.2 + 0.25 * _shimmer.value),
              width: 1.5,
            ),
          );
        } else if (locked) {
          decoration = BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.sandLight),
          );
        } else {
          decoration = BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: decoration,
          child: child,
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji
          Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.animal.emoji,
                style: TextStyle(
                  fontSize: 28,
                  color: locked ? null : null,
                ),
              ),
              if (locked)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: widget.isMythique
                          ? color.withValues(alpha: 0.20)
                          : const Color(0xFFE5E7EB),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 1),
                    ),
                    child: Center(
                      child: Text(
                        '🔒',
                        style: TextStyle(fontSize: widget.isMythique ? 7 : 7),
                      ),
                    ),
                  ),
                ),
              if (widget.isCurrent)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 1),
                    ),
                    child: const Center(
                      child: Icon(Icons.check, color: Colors.white, size: 8),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 5),

          // Nom
          Text(
            widget.animal.name,
            style: AppText.label.copyWith(
              fontSize: 9, letterSpacing: 0.3,
              color: locked && !widget.isMythique
                  ? AppColors.sand
                  : (widget.isCurrent ? color : AppColors.ink.withValues(alpha: 0.7)),
              fontWeight: widget.isCurrent ? FontWeight.w800 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 4),

          // Barre de progression (threshold uniquement) ou badge "TOI"
          if (widget.isCurrent)
            Text('• TOI •', style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w800, letterSpacing: 1))
          else if (!widget.isUnlocked)
            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: widget.progress, minHeight: 3,
                  backgroundColor: widget.isMythique
                      ? color.withValues(alpha: 0.15)
                      : AppColors.sandLight,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.isMythique ? color.withValues(alpha: 0.7) : AppColors.sand,
                  ),
                ),
              ),
            ),

          if (!widget.isCurrent && !widget.isUnlocked)
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 9,
                color: widget.isMythique ? color.withValues(alpha: 0.8) : AppColors.sand,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
