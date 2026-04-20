import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/city_poi.dart';

class PoiDetailScreen extends StatelessWidget {
  final CityPoi poi;

  const PoiDetailScreen({super.key, required this.poi});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1E30),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1E30),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            // ── Emoji ──────────────────────────────────────────────────────────
            Center(child: _EmojiBadge(poi: poi)),
            const SizedBox(height: 24),
            // ── Nom ────────────────────────────────────────────────────────────
            Text(
              poi.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            // ── Statut ─────────────────────────────────────────────────────────
            Center(child: _StatusChip(isDiscovered: poi.isDiscovered)),
            // ── Stats de visite ────────────────────────────────────────────────
            if (poi.isDiscovered) ...[
              const SizedBox(height: 16),
              _VisitStats(poi: poi),
            ],
            // ── Description (uniquement si découvert) ──────────────────────────
            if (poi.isDiscovered && poi.description != null) ...[
              const SizedBox(height: 24),
              _DescriptionBox(description: poi.description!),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Stats de visite ──────────────────────────────────────────────────────────

class _VisitStats extends StatelessWidget {
  final CityPoi poi;
  const _VisitStats({required this.poi});

  @override
  Widget build(BuildContext context) {
    final dateStr = poi.firstVisitDate != null
        ? DateFormat('d MMMM yyyy', 'fr_FR').format(poi.firstVisitDate!)
        : '—';
    final count = poi.visitCount;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StatPill(
          icon: '📅',
          label: 'Première visite',
          value: dateStr,
        ),
        const SizedBox(width: 10),
        _StatPill(
          icon: '🔁',
          label: 'Visites',
          value: count.toString(),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final String icon;
  final String label;
  final String value;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Description (Mérimée ou Wikipedia) ──────────────────────────────────────

class _DescriptionBox extends StatelessWidget {
  final String description;
  const _DescriptionBox({required this.description});

  /// Sépare le badge Mérimée (première ligne si elle contient "MH")
  /// du reste du texte.
  (String?, String) _split() {
    final lines = description.split('\n\n');
    if (lines.length >= 2 && lines.first.contains('MH')) {
      return (lines.first, lines.sublist(1).join('\n\n'));
    }
    return (null, description);
  }

  @override
  Widget build(BuildContext context) {
    final (badge, body) = _split();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏛️', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    badge,
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (body.isNotEmpty)
            Text(
              body,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 15,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Badge emoji ──────────────────────────────────────────────────────────────

class _EmojiBadge extends StatelessWidget {
  final CityPoi poi;

  const _EmojiBadge({required this.poi});

  @override
  Widget build(BuildContext context) {
    final Widget badge = Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: poi.isDiscovered
              ? [const Color(0xFFB0BEC5), const Color(0xFF90A4AE)]
              : [const Color(0xFFFFD54F), const Color(0xFFFFB300)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (poi.isDiscovered
                    ? const Color(0xFF90A4AE)
                    : const Color(0xFFFFB300))
                .withValues(alpha: poi.isDiscovered ? 0.25 : 0.55),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: poi.isDiscovered ? 0.4 : 0.85),
          width: 3,
        ),
      ),
      child: Center(
        child: Text(poi.emoji, style: const TextStyle(fontSize: 48)),
      ),
    );

    if (!poi.isDiscovered) return badge;

    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      0.55, 0,
      ]),
      child: badge,
    );
  }
}

// ─── Chip statut ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final bool isDiscovered;

  const _StatusChip({required this.isDiscovered});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDiscovered
            ? const Color(0xFF72C23A).withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDiscovered
              ? const Color(0xFF72C23A).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDiscovered ? Icons.check_circle_rounded : Icons.lock_rounded,
            size: 16,
            color: isDiscovered
                ? const Color(0xFF72C23A)
                : Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            isDiscovered ? 'Découvert' : 'Non découvert',
            style: TextStyle(
              color: isDiscovered
                  ? const Color(0xFF72C23A)
                  : Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
