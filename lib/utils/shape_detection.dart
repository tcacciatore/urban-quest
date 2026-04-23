import 'dart:math';
import 'package:latlong2/latlong.dart';

const _distCalc     = Distance();
const _maxGapMeters = 24.0; // rupture de continuité GPS
const _sampleMeters = 8.0;  // distance entre deux points consécutifs

// ─── Segment continu ─────────────────────────────────────────────────────────

/// Retourne le dernier segment continu de [points].
/// Remonte depuis le dernier point jusqu'à la première rupture GPS (> 24 m).
List<LatLng> lastContinuousSegment(List<LatLng> points) {
  if (points.length < 2) return points;
  int startIdx = points.length - 1;
  while (startIdx > 0) {
    if (_distCalc(points[startIdx - 1], points[startIdx]) > _maxGapMeters) break;
    startIdx--;
  }
  return points.sublist(startIdx);
}

/// Longueur approximative d'un segment (1 point ≈ 8 m).
double segmentLengthM(List<LatLng> pts) => pts.length * _sampleMeters;

// ─── Polygone de la forme détectée ───────────────────────────────────────────

/// Retourne le polygone enclosant la forme fermée détectée (triangle, carré, boucle).
/// Null si aucune forme fermée n'est trouvée dans [seg].
List<LatLng>? detectedShapePolygon(List<LatLng> seg) {
  if (seg.length < 3) return null;

  // Triangle et carré : forme fermée explicite (distance départ-arrivée < 120 m)
  if (segmentLengthM(seg) >= 300 && _distCalc(seg.first, seg.last) <= 120) {
    final triCorners = _simplifiedCorners(seg, epsilon: 40);
    if (triCorners.length == 3 && _checkAngles(triCorners, minDeg: 30, maxDeg: 120)) {
      return triCorners;
    }
    final sqCorners = _simplifiedCorners(seg, epsilon: 35);
    if (sqCorners.length == 4 && _checkAngles(sqCorners, minDeg: 60, maxDeg: 120)) {
      return sqCorners;
    }
  }

  // Boucle : utilise le segment lui-même comme polygone
  if (detectLoop(seg)) return seg;

  return null;
}

// ─── Détection de formes ─────────────────────────────────────────────────────

/// ⭕ Boucle — revenir à < 80 m du point de départ après ≥ 500 m parcourus.
bool detectLoop(List<LatLng> seg) {
  if (segmentLengthM(seg) < 500) return false;
  return _distCalc(seg.first, seg.last) < 80;
}

/// ↩️ Aller-retour — aller vers un point éloigné puis revenir au départ.
/// Le point le plus éloigné doit être dans la moitié centrale du tracé (30 %–70 %).
bool detectAllerRetour(List<LatLng> seg) {
  if (segmentLengthM(seg) < 400) return false;

  double maxDist = 0;
  int furthestIdx = 0;
  for (int i = 0; i < seg.length; i++) {
    final d = _distCalc(seg.first, seg[i]).toDouble();
    if (d > maxDist) {
      maxDist = d;
      furthestIdx = i;
    }
  }

  final midRatio = furthestIdx / seg.length;
  if (midRatio < 0.30 || midRatio > 0.70) return false;

  // L'arrivée doit être proche du départ (< 35 % de la distance max)
  return _distCalc(seg.first, seg.last) < maxDist * 0.35;
}

/// 🔺 Triangle — tracé fermé simplifié à 3 sommets avec angles entre 30° et 120°.
bool detectTriangle(List<LatLng> seg) {
  if (segmentLengthM(seg) < 300) return false;
  if (_distCalc(seg.first, seg.last) > 120) return false;

  final corners = _simplifiedCorners(seg, epsilon: 40);
  if (corners.length != 3) return false;

  return _checkAngles(corners, minDeg: 30, maxDeg: 120);
}

/// 🔲 Carré / Rectangle — tracé fermé simplifié à 4 sommets avec angles proches de 90°.
bool detectSquare(List<LatLng> seg) {
  if (segmentLengthM(seg) < 300) return false;
  if (_distCalc(seg.first, seg.last) > 120) return false;

  final corners = _simplifiedCorners(seg, epsilon: 35);
  if (corners.length != 4) return false;

  return _checkAngles(corners, minDeg: 60, maxDeg: 120);
}

// ─── Algorithme RDP ──────────────────────────────────────────────────────────

/// Applique RDP sur [pts], puis retire le point de fermeture si la forme est fermée.
/// Retourne la liste des sommets significatifs.
List<LatLng> _simplifiedCorners(List<LatLng> pts, {required double epsilon}) {
  final simplified = _rdp(pts, epsilon);
  // Retire le dernier point s'il est proche du premier (tracé fermé)
  if (simplified.length >= 3 &&
      _distCalc(simplified.first, simplified.last) < 60) {
    return simplified.sublist(0, simplified.length - 1);
  }
  return simplified;
}

/// Ramer-Douglas-Peucker : simplifie une polyligne en conservant
/// uniquement les points à plus de [epsilon] mètres de la droite locale.
List<LatLng> _rdp(List<LatLng> pts, double epsilon) {
  if (pts.length <= 2) return pts;

  double maxDist = 0;
  int maxIdx = 0;
  for (int i = 1; i < pts.length - 1; i++) {
    final d = _perpDist(pts[i], pts.first, pts.last);
    if (d > maxDist) {
      maxDist = d;
      maxIdx = i;
    }
  }

  if (maxDist > epsilon) {
    final left  = _rdp(pts.sublist(0, maxIdx + 1), epsilon);
    final right = _rdp(pts.sublist(maxIdx), epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [pts.first, pts.last];
}

// ─── Géométrie planaire approchée ────────────────────────────────────────────

/// Distance perpendiculaire du point [p] à la droite ([a],[b]) en mètres.
double _perpDist(LatLng p, LatLng a, LatLng b) {
  const latM   = 111000.0;
  final cosLat = cos(a.latitude * pi / 180);

  final px = (p.longitude - a.longitude) * latM * cosLat;
  final py = (p.latitude  - a.latitude)  * latM;
  final bx = (b.longitude - a.longitude) * latM * cosLat;
  final by = (b.latitude  - a.latitude)  * latM;

  final len2 = bx * bx + by * by;
  if (len2 == 0) return sqrt(px * px + py * py);

  final t = (px * bx + py * by) / len2;
  return sqrt(pow(px - t * bx, 2) + pow(py - t * by, 2));
}

/// Angle intérieur en degrés au sommet [b], formé par [a]-[b]-[c].
double _angleDeg(LatLng a, LatLng b, LatLng c) {
  const latM   = 111000.0;
  final cosLat = cos(b.latitude * pi / 180);

  final ax = (a.longitude - b.longitude) * latM * cosLat;
  final ay = (a.latitude  - b.latitude)  * latM;
  final cx = (c.longitude - b.longitude) * latM * cosLat;
  final cy = (c.latitude  - b.latitude)  * latM;

  final dot  = ax * cx + ay * cy;
  final magA = sqrt(ax * ax + ay * ay);
  final magC = sqrt(cx * cx + cy * cy);

  if (magA == 0 || magC == 0) return 0;
  return acos((dot / (magA * magC)).clamp(-1.0, 1.0)) * 180 / pi;
}

/// Vérifie que tous les angles intérieurs du polygone [pts] sont dans [minDeg, maxDeg].
bool _checkAngles(List<LatLng> pts, {required double minDeg, required double maxDeg}) {
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final angle = _angleDeg(
      pts[(i - 1 + n) % n],
      pts[i],
      pts[(i + 1) % n],
    );
    if (angle < minDeg || angle > maxDeg) return false;
  }
  return true;
}
