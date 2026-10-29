// SPDX-License-Identifier: GPL-3.0-only
/// Immutable world-space primitives shared by the editor, CLI and MCP server.
library;

import 'dart:math' as math;

/// A finite point in the unbounded world coordinate system.
class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  static const Point2 zero = Point2(0, 0);

  Point2 operator +(Point2 other) => Point2(x + other.x, y + other.y);
  Point2 operator -(Point2 other) => Point2(x - other.x, y - other.y);
  Point2 operator *(double factor) => Point2(x * factor, y * factor);
  Point2 operator /(double factor) => Point2(x / factor, y / factor);

  double get length => math.sqrt(x * x + y * y);
  double dot(Point2 other) => x * other.x + y * other.y;
  double cross(Point2 other) => x * other.y - y * other.x;
  double distanceTo(Point2 other) => (this - other).length;

  Point2 normalized({double epsilon = 1e-15}) {
    final magnitude = length;
    return magnitude <= epsilon ? zero : this / magnitude;
  }

  Point2 rotated(double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Point2(x * c - y * s, x * s + y * c);
  }

  bool isFinite() => x.isFinite && y.isFinite;

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  factory Point2.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Point must be an object.');
    }
    final x = value['x'];
    final y = value['y'];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
      throw const FormatException('Point coordinates must be finite numbers.');
    }
    return Point2(x.toDouble(), y.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is Point2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2($x, $y)';
}

/// Axis-aligned finite bounds. Invalid or empty bounds are never constructed.
class Bounds2 {
  const Bounds2(this.left, this.top, this.right, this.bottom)
    : assert(left <= right),
      assert(top <= bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  factory Bounds2.fromPoints(Iterable<Point2> points) {
    final iterator = points.iterator;
    if (!iterator.moveNext()) {
      throw ArgumentError.value(points, 'points', 'At least one point needed.');
    }
    var left = iterator.current.x;
    var right = left;
    var top = iterator.current.y;
    var bottom = top;
    while (iterator.moveNext()) {
      final point = iterator.current;
      left = math.min(left, point.x);
      right = math.max(right, point.x);
      top = math.min(top, point.y);
      bottom = math.max(bottom, point.y);
    }
    return Bounds2(left, top, right, bottom);
  }

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;

  Point2 get center => Point2((left + right) / 2, (top + bottom) / 2);

  bool intersects(Bounds2 other) =>
      left <= other.right &&
      right >= other.left &&
      top <= other.bottom &&
      bottom >= other.top;

  bool contains(Point2 point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  bool containsBounds(Bounds2 other) =>
      other.left >= left &&
      other.right <= right &&
      other.top >= top &&
      other.bottom <= bottom;

  Bounds2 union(Bounds2 other) => Bounds2(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  Bounds2 inflate(double amount) =>
      Bounds2(left - amount, top - amount, right + amount, bottom + amount);

  Bounds2? intersection(Bounds2 other) {
    final newLeft = math.max(left, other.left);
    final newTop = math.max(top, other.top);
    final newRight = math.min(right, other.right);
    final newBottom = math.min(bottom, other.bottom);
    if (newLeft > newRight || newTop > newBottom) return null;
    return Bounds2(newLeft, newTop, newRight, newBottom);
  }

  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      right.isFinite &&
      bottom.isFinite &&
      left <= right &&
      top <= bottom;

  Map<String, Object?> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory Bounds2.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid bounds.');
    final left = value['left'];
    final top = value['top'];
    final right = value['right'];
    final bottom = value['bottom'];
    if (left is! num ||
        top is! num ||
        right is! num ||
        bottom is! num ||
        !left.isFinite ||
        !top.isFinite ||
        !right.isFinite ||
        !bottom.isFinite ||
        left > right ||
        top > bottom) {
      throw const FormatException('Bounds must be finite and ordered.');
    }
    return Bounds2(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
  }

  @override
  String toString() => 'Bounds2($left, $top, $right, $bottom)';
}

/// Relative tolerance policy used by predicates and the constraint solver.
class GeometryTolerance {
  const GeometryTolerance({this.relative = 1e-9, this.absolute = 1e-12});

  final double relative;
  final double absolute;

  double forScale(double scale) {
    final finiteScale = scale.isFinite ? scale.abs() : 0.0;
    return math.max(absolute, relative * finiteScale);
  }

  bool isZero(double value, {double scale = 1}) =>
      value.abs() <= forScale(scale);

  Map<String, Object?> toJson() => {'relative': relative, 'absolute': absolute};

  factory GeometryTolerance.fromJson(Object? value) {
    if (value == null) return const GeometryTolerance();
    if (value is! Map) throw const FormatException('Invalid tolerance.');
    final relative = value['relative'];
    final absolute = value['absolute'];
    if (relative is! num ||
        absolute is! num ||
        relative <= 0 ||
        absolute <= 0 ||
        !relative.isFinite ||
        !absolute.isFinite) {
      throw const FormatException('Tolerance values must be positive.');
    }
    return GeometryTolerance(
      relative: relative.toDouble(),
      absolute: absolute.toDouble(),
    );
  }
}

/// Converts between world coordinates and screen coordinates.
class ViewTransform {
  const ViewTransform({
    required this.center,
    required this.zoom,
    this.origin = Point2.zero,
    this.devicePixelRatio = 1,
  });

  final Point2 center;
  final double zoom;
  final Point2 origin;
  final double devicePixelRatio;

  Point2 worldToScreen(
    Point2 point, {
    required double width,
    required double height,
  }) {
    final local = (point - origin) * zoom;
    return Point2(width / 2 + local.x, height / 2 + local.y);
  }

  Point2 screenToWorld(
    Point2 point, {
    required double width,
    required double height,
  }) {
    if (zoom == 0 || !zoom.isFinite) {
      throw StateError('Cannot invert a zero or non-finite view scale.');
    }
    return Point2(
      (point.x - width / 2) / zoom + origin.x,
      (point.y - height / 2) / zoom + origin.y,
    );
  }

  Bounds2 visibleWorldBounds({required double width, required double height}) {
    final topLeft = screenToWorld(Point2.zero, width: width, height: height);
    final bottomRight = screenToWorld(
      Point2(width, height),
      width: width,
      height: height,
    );
    return Bounds2(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y);
  }

  Map<String, Object?> toJson() => {
    'center': center.toJson(),
    'zoom': zoom,
    'origin': origin.toJson(),
    'devicePixelRatio': devicePixelRatio,
  };

  factory ViewTransform.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid view transform.');
    final zoom = value['zoom'];
    if (zoom is! num || !zoom.isFinite || zoom <= 0) {
      throw const FormatException('Zoom must be a positive finite number.');
    }
    return ViewTransform(
      center: value['center'] == null
          ? Point2.zero
          : Point2.fromJson(value['center']),
      zoom: zoom.toDouble(),
      origin: value['origin'] == null
          ? Point2.zero
          : Point2.fromJson(value['origin']),
      devicePixelRatio: value['devicePixelRatio'] is num
          ? (value['devicePixelRatio'] as num).toDouble()
          : 1,
    );
  }
}
