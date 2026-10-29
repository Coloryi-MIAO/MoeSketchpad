// SPDX-License-Identifier: GPL-3.0-only
/// Analytic function, parametric, polar and implicit curve support.
library;

import 'dart:math' as math;

import 'expression/expression.dart';
import 'geometry/intersections.dart';
import 'geometry/object.dart';
import 'geometry/point.dart';

class FunctionCurve {
  const FunctionCurve._(this.object);

  final GeometryObject object;

  static FunctionCurve fromObject(GeometryObject object) {
    if (object.kind != GeometryKind.function) {
      throw FormatException('${object.id} is not a function.');
    }
    return FunctionCurve._(object);
  }

  FunctionKind get kind => FunctionKind.parse(object.params['kind'] as String);

  String get _expression {
    final value = object.params['expression'];
    if (value is! String) {
      throw FormatException('Function ${object.id} has no expression.');
    }
    return value;
  }

  double get xMin => (object.params['xMin'] as num?)?.toDouble() ?? -10;
  double get xMax => (object.params['xMax'] as num?)?.toDouble() ?? 10;
  double get tMin => (object.params['tMin'] as num?)?.toDouble() ?? 0;
  double get tMax => (object.params['tMax'] as num?)?.toDouble() ?? 2 * math.pi;

  double explicit(double x) => _parsed('x', _expression).evaluate({'x': x});

  double polarRadius(double theta) {
    final expression =
        object.params['rExpression'] ?? object.params['expression'];
    if (expression is! String) {
      throw FormatException('Polar function ${object.id} has no r expression.');
    }
    return _parsed('theta', expression).evaluate({'theta': theta});
  }

  Point2 parametric(double t) {
    final xExpression = object.params['xExpression'];
    final yExpression = object.params['yExpression'];
    if (xExpression is! String || yExpression is! String) {
      throw FormatException(
        'Parametric function ${object.id} needs xExpression and yExpression.',
      );
    }
    return Point2(
      _parsed('t', xExpression).evaluate({'t': t}),
      _parsed('t', yExpression).evaluate({'t': t}),
    );
  }

  Point2 polarPoint(double theta) {
    final radius = polarRadius(theta);
    return Point2(radius * math.cos(theta), radius * math.sin(theta));
  }

  double implicitValue(double x, double y) {
    final expression = object.params['expression'];
    if (expression is! String) {
      throw FormatException(
        'Implicit function ${object.id} has no expression.',
      );
    }
    return _parsed('x,y', expression).evaluate({'x': x, 'y': y});
  }

  List<List<Point2>> sample(Bounds2 viewport, {int resolution = 512}) {
    switch (kind) {
      case FunctionKind.explicit:
        final from = math.max(xMin, viewport.left);
        final to = math.min(xMax, viewport.right);
        if (from >= to) return const [];
        final step = math.max((to - from) / resolution, 1e-9);
        final points = <Point2>[];
        for (var i = 0; i <= resolution; i++) {
          final x = from + step * i;
          try {
            final y = explicit(x);
            if (y.isFinite) points.add(Point2(x, y));
          } on EvaluationException {
            continue;
          } on FormatException {
            continue;
          }
        }
        return [points];
      case FunctionKind.parametric:
        final points = <Point2>[];
        for (var i = 0; i <= resolution; i++) {
          final t = tMin + (tMax - tMin) * i / resolution;
          try {
            final point = parametric(t);
            if (point.isFinite()) points.add(point);
          } on EvaluationException {
            continue;
          } on FormatException {
            continue;
          }
        }
        return [points];
      case FunctionKind.polar:
        final points = <Point2>[];
        for (var i = 0; i <= resolution; i++) {
          final theta = tMin + (tMax - tMin) * i / resolution;
          try {
            points.add(polarPoint(theta));
          } on EvaluationException {
            continue;
          } on FormatException {
            continue;
          }
        }
        return [points];
      case FunctionKind.implicit:
        final segments = sampleImplicit(
          evaluate: implicitValue,
          bounds: viewport,
          resolution: math.min(256, math.max(16, resolution ~/ 4)),
        );
        return [
          for (final segment in segments) [segment.a, segment.b],
        ];
    }
  }

  Point2? pointAtPhase(double phase) {
    final t = phase.clamp(0.0, 1.0);
    switch (kind) {
      case FunctionKind.explicit:
        final x = xMin + (xMax - xMin) * t;
        try {
          final y = explicit(x);
          return y.isFinite ? Point2(x, y) : null;
        } on Exception {
          return null;
        }
      case FunctionKind.parametric:
        try {
          return parametric(tMin + (tMax - tMin) * t);
        } on Exception {
          return null;
        }
      case FunctionKind.polar:
        try {
          return polarPoint(tMin + (tMax - tMin) * t);
        } on Exception {
          return null;
        }
      case FunctionKind.implicit:
        return null;
    }
  }

  static final Map<String, Expression> _cache = {};
  static const int _cacheLimit = 128;

  Expression _parsed(String variables, String source) {
    final key = '$variables::$source';
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= _cacheLimit) _cache.clear();
    final expression = Expression.parse(source);
    _cache[key] = expression;
    return expression;
  }
}

/// Generates a point on a path object for the animation runtime.
class PathSampler {
  const PathSampler();

  Point2? positionAt(GeometryObject path, double phase) {
    final t = phase.clamp(0.0, 1.0);
    switch (path.kind) {
      case GeometryKind.segment:
      case GeometryKind.line:
      case GeometryKind.ray:
      case GeometryKind.vector:
        return path.points[0] + (path.points[1] - path.points[0]) * t;
      case GeometryKind.circle:
        final center = path.points[0];
        final offset = path.points[1] - center;
        return center + offset.rotated(2 * math.pi * t);
      case GeometryKind.arc:
        final center = path.points[0];
        final start = math.atan2(
          path.points[1].y - center.y,
          path.points[1].x - center.x,
        );
        final end = math.atan2(
          path.points[2].y - center.y,
          path.points[2].x - center.x,
        );
        var sweep = end - start;
        while (sweep < 0) {
          sweep += 2 * math.pi;
        }
        final radius = center.distanceTo(path.points[1]);
        return center +
            Point2(
              radius * math.cos(start + sweep * t),
              radius * math.sin(start + sweep * t),
            );
      case GeometryKind.polygon:
      case GeometryKind.triangle:
        final lengths = <double>[];
        var perimeter = 0.0;
        for (var i = 0; i < path.points.length; i++) {
          final length = path.points[i].distanceTo(
            path.points[(i + 1) % path.points.length],
          );
          lengths.add(length);
          perimeter += length;
        }
        if (perimeter <= 1e-15) return path.points.first;
        var target = t * perimeter;
        for (var i = 0; i < lengths.length; i++) {
          if (target <= lengths[i]) {
            final local = lengths[i] == 0 ? 0.0 : target / lengths[i];
            return path.points[i] +
                (path.points[(i + 1) % path.points.length] - path.points[i]) *
                    local;
          }
          target -= lengths[i];
        }
        return path.points.first;
      case GeometryKind.function:
        return FunctionCurve.fromObject(path).pointAtPhase(t);
      default:
        return null;
    }
  }
}
