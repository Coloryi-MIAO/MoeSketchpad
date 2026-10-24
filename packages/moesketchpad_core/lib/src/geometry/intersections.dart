// SPDX-License-Identifier: GPL-3.0-only
/// Robust geometric predicates and intersections.
library;

import 'dart:math' as math;

import 'object.dart';
import 'point.dart';

class IntersectionResult {
  const IntersectionResult._(this.kind, this.points, [this.note]);

  const IntersectionResult.none([String? note])
    : this._(IntersectionKind.none, const [], note);

  IntersectionResult.one(Point2 point) : this._(IntersectionKind.one, [point]);

  IntersectionResult.two(Point2 first, Point2 second)
    : this._(IntersectionKind.two, [first, second]);

  const IntersectionResult.degenerate(String note)
    : this._(IntersectionKind.degenerate, const [], note);

  final IntersectionKind kind;
  final List<Point2> points;
  final String? note;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'points': [for (final point in points) point.toJson()],
    if (note != null) 'note': note,
  };
}

enum IntersectionKind { none, one, two, degenerate }

double orientation(Point2 a, Point2 b, Point2 c) =>
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

bool pointsCoincide(Point2 a, Point2 b, GeometryTolerance tolerance) =>
    a.distanceTo(b) <=
    tolerance.forScale(math.max(a.length, b.length) + a.distanceTo(b));

double distancePointToLine(Point2 point, Point2 a, Point2 b) {
  final direction = b - a;
  final length = direction.length;
  if (length <= 1e-15) return point.distanceTo(a);
  return orientation(a, b, point).abs() / length;
}

double distancePointToSegment(Point2 point, Point2 a, Point2 b) {
  final ab = b - a;
  final lengthSquared = ab.dot(ab);
  if (lengthSquared <= 1e-30) return point.distanceTo(a);
  final t = ((point - a).dot(ab) / lengthSquared).clamp(0.0, 1.0);
  return point.distanceTo(a + ab * t);
}

/// Parametric line intersection. Returns a point, two points (coincident
/// lines are represented as degenerate), or none.
IntersectionResult intersectLines(
  Point2 a,
  Point2 b,
  Point2 c,
  Point2 d, {
  GeometryTolerance tolerance = const GeometryTolerance(),
  bool segments = false,
  bool rays = false,
}) {
  final r = b - a;
  final s = d - c;
  if (!r.isFinite() || !s.isFinite()) {
    return const IntersectionResult.none('Non-finite direction.');
  }
  final denominator = r.cross(s);
  final scale = math.max(r.length * s.length, 1.0);
  if (tolerance.isZero(denominator, scale: scale)) {
    final collinear = tolerance.isZero(orientation(a, b, c), scale: scale);
    if (collinear) {
      return const IntersectionResult.degenerate(
        'Lines are coincident; the intersection is not a finite point set.',
      );
    }
    return const IntersectionResult.none('Lines are parallel.');
  }
  final qp = c - a;
  final t = qp.cross(s) / denominator;
  final u = qp.cross(r) / denominator;
  if (segments &&
      (t < -tolerance.relative ||
          t > 1 + tolerance.relative ||
          u < -tolerance.relative ||
          u > 1 + tolerance.relative)) {
    return const IntersectionResult.none('Segments do not intersect.');
  }
  if (!segments && rays) {
    if (t < -tolerance.relative || u < -tolerance.relative) {
      return const IntersectionResult.none('Rays do not intersect.');
    }
  }
  return IntersectionResult.one(a + r * t);
}

IntersectionResult intersectLineCircle(
  Point2 a,
  Point2 b,
  Point2 center,
  double radius, {
  GeometryTolerance tolerance = const GeometryTolerance(),
  bool segment = false,
  bool ray = false,
}) {
  if (!radius.isFinite || radius < 0) {
    return const IntersectionResult.none('Circle radius is invalid.');
  }
  final direction = b - a;
  final lengthSquared = direction.dot(direction);
  if (lengthSquared <= tolerance.absolute * tolerance.absolute) {
    return const IntersectionResult.degenerate('Line has zero length.');
  }
  final f = a - center;
  final bCoef = 2 * f.dot(direction);
  final cCoef = f.dot(f) - radius * radius;
  final discriminant = bCoef * bCoef - 4 * lengthSquared * cCoef;
  final discTolerance = tolerance.forScale(
    math.max(bCoef * bCoef, 4 * lengthSquared * cCoef.abs()) + radius * radius,
  );
  if (discriminant < -discTolerance) {
    return const IntersectionResult.none('No real intersection.');
  }
  if (discriminant.abs() <= discTolerance) {
    final t = -bCoef / (2 * lengthSquared);
    if (!_withinLineDomain(t, segment, ray, tolerance)) {
      return const IntersectionResult.none('Intersection outside domain.');
    }
    return IntersectionResult.one(a + direction * t);
  }
  final root = math.sqrt(math.max(0, discriminant));
  final t1 = (-bCoef - root) / (2 * lengthSquared);
  final t2 = (-bCoef + root) / (2 * lengthSquared);
  final points = <Point2>[];
  for (final t in [t1, t2]) {
    if (_withinLineDomain(t, segment, ray, tolerance)) {
      points.add(a + direction * t);
    }
  }
  if (points.isEmpty) {
    return const IntersectionResult.none('Intersections outside domain.');
  }
  if (points.length == 1) return IntersectionResult.one(points.single);
  return IntersectionResult.two(points[0], points[1]);
}

bool _withinLineDomain(
  double t,
  bool segment,
  bool ray,
  GeometryTolerance tolerance,
) {
  if (segment) return t >= -tolerance.relative && t <= 1 + tolerance.relative;
  if (ray) return t >= -tolerance.relative;
  return true;
}

IntersectionResult intersectCircles(
  Point2 c1,
  double r1,
  Point2 c2,
  double r2, {
  GeometryTolerance tolerance = const GeometryTolerance(),
}) {
  if (r1 < 0 || r2 < 0 || !r1.isFinite || !r2.isFinite) {
    return const IntersectionResult.none('Invalid circle radius.');
  }
  final delta = c2 - c1;
  final distance = delta.length;
  final scale = math.max(math.max(r1, r2), distance);
  final eps = tolerance.forScale(scale);
  if (distance <= eps) {
    if ((r1 - r2).abs() <= eps) {
      return const IntersectionResult.degenerate(
        'Circles are coincident; intersection is not finite.',
      );
    }
    return const IntersectionResult.none('Concentric circles.');
  }
  if (distance > r1 + r2 + eps || distance < (r1 - r2).abs() - eps) {
    return const IntersectionResult.none('Circles are separated.');
  }
  final a = (r1 * r1 - r2 * r2 + distance * distance) / (2 * distance);
  final hSquared = r1 * r1 - a * a;
  final base = c1 + delta * (a / distance);
  if (hSquared.abs() <= eps * math.max(1, r1)) {
    return IntersectionResult.one(base);
  }
  final h = math.sqrt(math.max(0, hSquared));
  final perpendicular = Point2(-delta.y / distance, delta.x / distance) * h;
  return IntersectionResult.two(base + perpendicular, base - perpendicular);
}

/// Exact-enough point-in-polygon test (boundary counts as inside) using
/// orientation with a scale-relative epsilon.
bool pointInPolygon(
  Point2 point,
  List<Point2> polygon, {
  GeometryTolerance tolerance = const GeometryTolerance(),
}) {
  if (polygon.length < 3) return false;
  var inside = false;
  final epsilon = tolerance.forScale(
    polygon.map((p) => p.length).fold<double>(0, math.max) + point.length,
  );
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[j];
    final b = polygon[i];
    if (distancePointToSegment(point, a, b) <= epsilon) return true;
    final intersects =
        ((a.y > point.y) != (b.y > point.y)) &&
        (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x);
    if (intersects) inside = !inside;
  }
  return inside;
}

/// Circle through three points. Returns `(center, radius)` or null for
/// collinear/degenerate input.
({Point2 center, double radius})? circleThroughPoints(
  Point2 a,
  Point2 b,
  Point2 c, {
  GeometryTolerance tolerance = const GeometryTolerance(),
}) {
  final d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
  final scale = math.max(a.length, math.max(b.length, c.length));
  if (tolerance.isZero(d, scale: math.max(1, scale * scale))) return null;
  final a2 = a.dot(a);
  final b2 = b.dot(b);
  final c2 = c.dot(c);
  final ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d;
  final uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d;
  final center = Point2(ux, uy);
  return (center: center, radius: center.distanceTo(a));
}

/// Returns the angle ABC in radians, in [0, pi].
double angleAt(Point2 a, Point2 b, Point2 c) {
  final first = a - b;
  final second = c - b;
  if (first.length <= 1e-15 || second.length <= 1e-15) return 0;
  final cosine = (first.dot(second) / (first.length * second.length)).clamp(
    -1.0,
    1.0,
  );
  return math.acos(cosine);
}

/// Samples a parametric function for rendering. The callback must be pure and
/// is bounded to avoid unbounded memory use.
List<Point2> sampleParametric({
  required Point2 Function(double t) evaluate,
  required double t0,
  required double t1,
  int samples = 512,
  int maxPoints = 8192,
}) {
  if (samples < 2) samples = 2;
  if (samples > maxPoints) samples = maxPoints;
  final result = <Point2>[];
  for (var i = 0; i <= samples; i++) {
    final t = t0 + (t1 - t0) * i / samples;
    final point = evaluate(t);
    if (point.isFinite()) result.add(point);
  }
  return result;
}

/// Marching-squares sampler for an implicit function `f(x,y)=0`.
List<Segment2> sampleImplicit({
  required double Function(double x, double y) evaluate,
  required Bounds2 bounds,
  int resolution = 96,
}) {
  final sampleResolution = resolution.clamp(4, 512);
  final segments = <Segment2>[];
  final cellWidth = bounds.width / sampleResolution;
  final cellHeight = bounds.height / sampleResolution;
  if (!cellWidth.isFinite || !cellHeight.isFinite) return segments;
  final values = List<double>.filled(
    (sampleResolution + 1) * (sampleResolution + 1),
    0,
  );
  for (var y = 0; y <= sampleResolution; y++) {
    for (var x = 0; x <= sampleResolution; x++) {
      final px = bounds.left + x * cellWidth;
      final py = bounds.top + y * cellHeight;
      values[y * (sampleResolution + 1) + x] = evaluate(px, py);
    }
  }
  Point2 vertex(int x, int y) =>
      Point2(bounds.left + x * cellWidth, bounds.top + y * cellHeight);
  Point2 edgePoint(int x1, int y1, int x2, int y2) {
    final v1 = values[y1 * (sampleResolution + 1) + x1];
    final v2 = values[y2 * (sampleResolution + 1) + x2];
    final t = (v1.abs() + v2.abs()) <= 1e-30
        ? 0.5
        : (v1 / (v1 - v2)).clamp(0.0, 1.0);
    final p1 = vertex(x1, y1);
    final p2 = vertex(x2, y2);
    return Point2(p1.x + (p2.x - p1.x) * t, p1.y + (p2.y - p1.y) * t);
  }

  for (var y = 0; y < sampleResolution; y++) {
    for (var x = 0; x < sampleResolution; x++) {
      final v0 = values[y * (sampleResolution + 1) + x];
      final v1 = values[y * (sampleResolution + 1) + x + 1];
      final v2 = values[(y + 1) * (sampleResolution + 1) + x + 1];
      final v3 = values[(y + 1) * (sampleResolution + 1) + x];
      if ([v0, v1, v2, v3].any((v) => !v.isFinite)) continue;
      final mask =
          (v0 > 0 ? 1 : 0) |
          (v1 > 0 ? 2 : 0) |
          (v2 > 0 ? 4 : 0) |
          (v3 > 0 ? 8 : 0);
      if (mask == 0 || mask == 15) continue;
      final left = edgePoint(x, y, x, y + 1);
      final top = edgePoint(x, y, x + 1, y);
      final right = edgePoint(x + 1, y, x + 1, y + 1);
      final bottom = edgePoint(x, y + 1, x + 1, y + 1);
      switch (mask) {
        case 1:
        case 14:
          segments.add(Segment2(left, top));
        case 2:
        case 13:
          segments.add(Segment2(top, right));
        case 3:
        case 12:
          segments.add(Segment2(left, right));
        case 4:
        case 11:
          segments.add(Segment2(right, bottom));
        case 6:
        case 9:
          segments.add(Segment2(top, bottom));
        case 7:
        case 8:
          segments.add(Segment2(left, bottom));
        case 5:
          segments.add(Segment2(left, top));
          segments.add(Segment2(right, bottom));
        case 10:
          segments.add(Segment2(top, right));
          segments.add(Segment2(left, bottom));
      }
    }
  }
  return segments;
}

class Segment2 {
  const Segment2(this.a, this.b);
  final Point2 a;
  final Point2 b;
}

/// Computes a viewport-bounded visual extent. Unbounded objects are clipped to
/// the world viewport or reported as having no static finite bound.
Bounds2? objectViewportBounds(GeometryObject object, Bounds2 viewport) {
  if (object.kind == GeometryKind.function) {
    return viewport;
  }
  final bounds = object.bounds;
  if (bounds == null) return viewport;
  return bounds.intersection(viewport) ??
      (bounds.containsBounds(viewport) ? viewport : bounds);
}
