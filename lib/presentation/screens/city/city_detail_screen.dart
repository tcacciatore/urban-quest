import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/city.dart';
import '../../../domain/entities/city_poi.dart';
import '../../providers/city_fog_provider.dart';
import '../../providers/poi_providers.dart';
import '../../providers/wallet_providers.dart';

class CityDetailScreen extends ConsumerStatefulWidget {
  final City city;

  const CityDetailScreen({super.key, required this.city});

  @override
  ConsumerState<CityDetailScreen> createState() => _CityDetailScreenState();
}

class _CityDetailScreenState extends ConsumerState<CityDetailScreen> {
  final _scrollController = ScrollController();
  bool _showTitle = false;

  // Seuil : le titre dans le contenu commence à ~140px du début du scroll.
  // On le montre dans l'AppBar dès qu'il sort de l'écran (~après 90px de scroll).
  static const _titleThreshold = 90.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final show = _scrollController.offset > _titleThreshold;
    if (show != _showTitle) setState(() => _showTitle = show);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ville live (se met à jour si déverrouillée)
    final city = ref.watch(
      cityFogProvider.select((s) => s.cities[widget.city.id] ?? widget.city),
    );
    final pois = ref.watch(
      poiProvider.select((s) => s.forCity(city.id)),
    );

    final discovered = pois.where((p) => p.isDiscovered).toList();
    final undiscovered = pois.where((p) => !p.isDiscovered).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1E30),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0F1E30),
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: AnimatedOpacity(
              opacity: _showTitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                city.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            titleSpacing: 0,
            centerTitle: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 8),
                // ── Emoji ville ──────────────────────────────────────────────
                Center(child: _CityEmoji(isUnlocked: city.isUnlocked)),
                const SizedBox(height: 24),
                // ── Nom ──────────────────────────────────────────────────────
                Text(
                  city.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                // ── Statut ───────────────────────────────────────────────────
                Center(child: _StatusChip(city: city)),
                const SizedBox(height: 20),
                // ── Barre de progression ─────────────────────────────────────
                _ProgressBar(city: city),
                const SizedBox(height: 20),
                // ── Stats : km + dernière visite ─────────────────────────────
                Center(child: _StatsRow(city: city)),
                // ── Bouton déverrouiller ──────────────────────────────────────
                if (!city.isUnlocked) ...[
                  const SizedBox(height: 20),
                  _UnlockButton(city: city),
                ],
                // ── POIs ─────────────────────────────────────────────────────
                if (pois.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _PoiSection(
                    discovered: discovered,
                    undiscovered: undiscovered,
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Badge emoji ville ────────────────────────────────────────────────────────

class _CityEmoji extends StatelessWidget {
  final bool isUnlocked;
  const _CityEmoji({required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isUnlocked
              ? [const Color(0xFF72C23A), const Color(0xFF4A9E22)]
              : [const Color(0xFFE8EEF6), const Color(0xFFBCC8DA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (isUnlocked
                    ? const Color(0xFF72C23A)
                    : const Color(0xFF8A9AB8))
                .withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: isUnlocked ? 0.6 : 0.5),
          width: 3,
        ),
      ),
      child: Center(
        child: Text(
          isUnlocked ? '🏙️' : '🔒',
          style: const TextStyle(fontSize: 46),
        ),
      ),
    );
  }
}

// ─── Chip statut ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final City city;
  const _StatusChip({required this.city});

  @override
  Widget build(BuildContext context) {
    final progress = (city.revealedRatio * 100).clamp(0, 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: city.isUnlocked
            ? const Color(0xFF72C23A).withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: city.isUnlocked
              ? const Color(0xFF72C23A).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            city.isUnlocked
                ? Icons.lock_open_rounded
                : Icons.lock_rounded,
            size: 16,
            color: city.isUnlocked
                ? const Color(0xFF72C23A)
                : Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Text(
            city.isUnlocked
                ? 'Déverrouillée'
                : 'Verrouillée — $progress % exploré',
            style: TextStyle(
              color: city.isUnlocked
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

// ─── Barre de progression ─────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final City city;
  const _ProgressBar({required this.city});

  @override
  Widget build(BuildContext context) {
    final progress = city.revealedRatio.clamp(0.0, 1.0);
    final tickPosition = City.requiredRatio; // 0.75

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress * 100).round()}% exploré',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '🔓 à ${(tickPosition * 100).round()}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            final tickX = barWidth * tickPosition;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Fond de la barre
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation(
                      city.isUnlocked
                          ? const Color(0xFF72C23A)
                          : const Color(0xFF5B9BD5),
                    ),
                  ),
                ),
                // Tick à 75%
                Positioned(
                  left: tickX - 1,
                  top: -3,
                  bottom: -3,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Stats km + dernière visite ───────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final City city;
  const _StatsRow({required this.city});

  @override
  Widget build(BuildContext context) {
    final km = city.walkedKm;
    final kmStr = km < 1.0
        ? '${(km * 1000).round()} m'
        : '${km.toStringAsFixed(1)} km';

    String? lastVisitStr;
    if (city.lastVisitDate != null) {
      final d = city.lastVisitDate!;
      lastVisitStr =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StatChip(emoji: '🥾', label: kmStr),
        if (lastVisitStr != null) ...[
          const SizedBox(width: 10),
          _StatChip(emoji: '📅', label: lastVisitStr),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String emoji;
  final String label;
  const _StatChip({required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bouton déverrouiller avec crédits ───────────────────────────────────────

class _UnlockButton extends ConsumerWidget {
  final City city;
  static const _cost = 3000;

  const _UnlockButton({required this.city});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final canAfford = wallet.credits >= _cost;

    return GestureDetector(
      onTap: () => _showConfirmDialog(context, ref, canAfford),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: canAfford
              ? const LinearGradient(
                  colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: canAfford ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: canAfford
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: canAfford
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '🔓',
              style: TextStyle(
                fontSize: 18,
                color: canAfford ? Colors.white : Colors.white38,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Déverrouiller — $_cost 🪙',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: canAfford ? Colors.white : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmDialog(BuildContext context, WidgetRef ref, bool canAfford) {
    final credits = ref.read(walletProvider).credits;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2840),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Déverrouiller la ville ?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cela va dépenser $_cost 🪙 pour :',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            ),
            const SizedBox(height: 10),
            _BulletPoint('Révéler 100 % du brouillard de ${city.name}'),
            _BulletPoint('Découvrir automatiquement tous les lieux'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: canAfford
                    ? const Color(0xFFFFB800).withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    canAfford ? Icons.account_balance_wallet_rounded : Icons.warning_rounded,
                    size: 16,
                    color: canAfford ? const Color(0xFFFFB800) : Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    canAfford
                        ? 'Solde après : ${credits - _cost} 🪙'
                        : 'Solde insuffisant ($credits 🪙)',
                    style: TextStyle(
                      color: canAfford ? const Color(0xFFFFB800) : Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Annuler', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          if (canAfford)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _unlock(ref);
              },
              child: const Text(
                'Confirmer',
                style: TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _unlock(WidgetRef ref) async {
    ref.read(walletProvider.notifier).addCredits(-_cost);
    await ref.read(cityFogProvider.notifier).revealCityFully(city.id);
    await ref.read(poiProvider.notifier).discoverAllForCity(city.id);
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section POIs ─────────────────────────────────────────────────────────────

class _PoiSection extends StatelessWidget {
  final List<CityPoi> discovered;
  final List<CityPoi> undiscovered;

  const _PoiSection({
    required this.discovered,
    required this.undiscovered,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Points d\'intérêt',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${discovered.length} découvert${discovered.length > 1 ? 's' : ''} · ${undiscovered.length} restant${undiscovered.length > 1 ? 's' : ''}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        ...discovered.map((poi) => _PoiRow(poi: poi, revealed: true)),
        ...undiscovered.map((poi) => _PoiRow(poi: poi, revealed: false)),
      ],
    );
  }
}

class _PoiRow extends StatelessWidget {
  final CityPoi poi;
  final bool revealed;

  const _PoiRow({required this.poi, required this.revealed});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: revealed ? 0.07 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: revealed ? 0.10 : 0.06),
        ),
      ),
      child: Row(
        children: [
          // Emoji (grisé si non découvert)
          ColorFiltered(
            colorFilter: revealed
                ? const ColorFilter.mode(
                    Colors.transparent, BlendMode.dst)
                : const ColorFilter.matrix([
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0,      0,      0,      0.5, 0,
                  ]),
            child: Text(poi.emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: revealed
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '✓ ',
                            style: TextStyle(
                              color: Color(0xFF72C23A),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              poi.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (poi.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          poi.description!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  )
                : Text(
                    '???',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
