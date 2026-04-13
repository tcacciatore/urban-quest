import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../domain/entities/city_poi.dart';

class PoiLayer extends StatelessWidget {
  final List<CityPoi> pois;
  final String? selectedPoiId;
  final ValueChanged<String?> onPoiTapped;

  const PoiLayer({
    super.key,
    required this.pois,
    required this.selectedPoiId,
    required this.onPoiTapped,
  });

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: pois.map((poi) {
        final isSelected = poi.id == selectedPoiId;
        return Marker(
          point: poi.position,
          width: isSelected ? 150 : 44,
          height: isSelected ? 68 : 40,
          alignment: Alignment.bottomCenter,
          child: _PoiMarker(
            poi: poi,
            isSelected: isSelected,
            onTap: () => onPoiTapped(isSelected ? null : poi.id),
          ),
        );
      }).toList(),
    );
  }
}

class _PoiMarker extends StatelessWidget {
  final CityPoi poi;
  final bool isSelected;
  final VoidCallback onTap;

  const _PoiMarker({
    required this.poi,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final emojiWidget = _buildEmoji();

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (isSelected) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (poi.isDiscovered) ...[
                    const Text('✓ ', style: TextStyle(color: Color(0xFF72C23A), fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                  Flexible(
                    child: Text(
                      poi.name,
                      style: TextStyle(
                        color: poi.isDiscovered
                            ? Colors.white.withValues(alpha: 0.65)
                            : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
          ],
          emojiWidget,
        ],
      ),
    );
  }

  Widget _buildEmoji() {
    final text = Text(
      poi.emoji,
      style: TextStyle(
        fontSize: 28,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.50),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );

    if (!poi.isDiscovered) return text;

    // Grisé + semi-transparent pour les POIs déjà visités
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      0.50, 0,
      ]),
      child: text,
    );
  }
}
