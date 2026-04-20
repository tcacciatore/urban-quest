import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../domain/entities/city_poi.dart';

class PoiLayer extends StatelessWidget {
  final List<CityPoi> pois;
  final ValueChanged<CityPoi> onPoiTapped;

  const PoiLayer({
    super.key,
    required this.pois,
    required this.onPoiTapped,
  });

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: pois.map((poi) {
        return Marker(
          point: poi.position,
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: _PoiMarker(
            poi: poi,
            onTap: () => onPoiTapped(poi),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Marqueur ─────────────────────────────────────────────────────────────────

class _PoiMarker extends StatelessWidget {
  final CityPoi poi;
  final VoidCallback onTap;

  const _PoiMarker({required this.poi, required this.onTap});

  static const _undiscoveredColors = [Color(0xFFFFD54F), Color(0xFFFFB300)];
  static const _discoveredColors   = [Color(0xFF66BB6A), Color(0xFF388E3C)];

  @override
  Widget build(BuildContext context) {
    final colors = poi.isDiscovered ? _discoveredColors : _undiscoveredColors;
    return GestureDetector(
      onTap: onTap,
      child: _buildCircle(colors),
    );
  }

  Widget _buildCircle(List<Color> colors) {
    final circle = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: poi.isDiscovered ? 0.25 : 0.55),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: poi.isDiscovered ? 0.4 : 0.85),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(poi.emoji, style: const TextStyle(fontSize: 22)),
      ),
    );

    return circle;
  }
}
