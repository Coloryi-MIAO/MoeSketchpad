// SPDX-License-Identifier: GPL-3.0-only
/// Primitive construction shared by CLI create/inspect and the MCP create tool.
library;

import 'dart:math' as math;

import 'package:moesketchpad_core/moesketchpad_core.dart';

class PrimitiveException implements Exception {
  const PrimitiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PrimitiveFactory {
  const PrimitiveFactory();

  GeometryObject build(
    String primitive,
    Map<String, String> options,
    GeometryDocument document,
  ) {
    if (primitive == 'triangle') return _triangle(options, document);
    final points = _pointsOption(options);
    final label = options['label'] ?? _nextLabel(primitive, document);
    final id = options['id'] ?? _nextId(primitive, document);
    final layerId = document.layers.first.id;
    switch (primitive) {
      case 'point':
        final x = _number(options, 'x');
        final y = _number(options, 'y');
        return GeometryObject(
          id: id,
          kind: GeometryKind.point,
          points: [Point2(x, y)],
          label: label,
          layerId: layerId,
        );
      case 'segment':
      case 'line':
      case 'ray':
      case 'vector':
        final pair = points.length == 2
            ? points
            : [
                Point2(_number(options, 'x1'), _number(options, 'y1')),
                Point2(_number(options, 'x2'), _number(options, 'y2')),
              ];
        return GeometryObject(
          id: id,
          kind: GeometryKind.parse(primitive),
          points: pair,
          label: label,
          layerId: layerId,
        );
      case 'circle':
        final center = _center(options, points);
        final radius = options['radius'] ?? options['r'];
        if (radius == null || double.tryParse(radius) == null) {
          throw const PrimitiveException(
            'Circle requires --center=x,y --radius=r (or --cx/--cy/--r).',
          );
        }
        final r = _positiveNumber(options, 'r', fallback: radius);
        return GeometryObject(
          id: id,
          kind: GeometryKind.circle,
          points: [center, Point2(center.x + r, center.y)],
          label: label,
          layerId: layerId,
        );
      case 'arc':
        final center = _center(options, points);
        final r = _positiveNumber(options, 'r');
        final start = _number(options, 'start', fallback: 0) * math.pi / 180;
        final end = _number(options, 'end', fallback: 90) * math.pi / 180;
        return GeometryObject(
          id: id,
          kind: GeometryKind.arc,
          points: [
            center,
            Point2(
              center.x + r * math.cos(start),
              center.y + r * math.sin(start),
            ),
            Point2(center.x + r * math.cos(end), center.y + r * math.sin(end)),
          ],
          label: label,
          layerId: layerId,
        );
      case 'polygon':
        if (points.length < 3) {
          throw const PrimitiveException(
            'Polygon requires at least three points via --points=x,y;...',
          );
        }
        return GeometryObject(
          id: id,
          kind: GeometryKind.polygon,
          points: points,
          label: label,
          layerId: layerId,
          style: const ObjectStyle(fillColor: 0x33296fa8),
        );
      case 'conic':
        final type = options['type'] ?? 'ellipse';
        if (!const {'ellipse', 'parabola', 'hyperbola'}.contains(type)) {
          throw const PrimitiveException(
            'Conic type must be ellipse, parabola or hyperbola.',
          );
        }
        final center = _center(options, points);
        final a = _positiveNumber(options, 'a', fallback: '2');
        final b = _positiveNumber(options, 'b', fallback: '1');
        final rotation = _number(options, 'rotation', fallback: 0);
        return GeometryObject(
          id: id,
          kind: GeometryKind.conic,
          points: [
            center,
            Point2(center.x + a, center.y),
            Point2(center.x, center.y + b),
          ],
          label: label,
          layerId: layerId,
          params: {'conicType': type, 'a': a, 'b': b, 'rotation': rotation},
        );
      case 'function':
        return _function(options, id, label, layerId);
      case 'coordinate':
        return GeometryObject(
          id: id,
          kind: GeometryKind.coordinate,
          points: const [],
          label: label,
          layerId: layerId,
          params: {
            'xMin': _number(options, 'x-min', fallback: -10),
            'xMax': _number(options, 'x-max', fallback: 10),
          },
        );
      case 'solid':
        if (options['points'] == null || points.length < 4) {
          throw const PrimitiveException(
            'Solid requires --points with at least four projected vertices.',
          );
        }
        return GeometryObject(
          id: id,
          kind: GeometryKind.solid,
          points: points,
          label: label,
          layerId: layerId,
          params: {'edges': options['edges'] ?? '0-1,1-2,2-3,3-0'},
        );
      default:
        throw PrimitiveException(
          'Unsupported primitive "$primitive". Supported: point, segment, '
          'line, ray, circle, arc, triangle, polygon, conic, function, '
          'vector, coordinate, solid.',
        );
    }
  }

  GeometryObject _triangle(
    Map<String, String> options,
    GeometryDocument document,
  ) {
    final type = options['type'] ?? 'right';
    if (type != 'right') {
      throw const PrimitiveException(
        'Only --type=right is currently solvable; other angle types are '
        'reserved.',
      );
    }
    final sidesRaw = options['sides'];
    if (sidesRaw == null) {
      throw const PrimitiveException(
        'Triangle requires --sides=3,4,5 --hypotenuse=5.',
      );
    }
    final sides = sidesRaw
        .split(',')
        .map((value) => double.tryParse(value.trim()))
        .toList();
    final hypotenuse = double.tryParse(options['hypotenuse'] ?? '');
    final rotation = double.tryParse(options['rotation'] ?? '0');
    if (sides.any((side) => side == null) ||
        hypotenuse == null ||
        rotation == null) {
      throw const PrimitiveException('Triangle parameters must be numeric.');
    }
    final solution = TriangleSolution.right(
      sides: sides.cast<double>(),
      hypotenuse: hypotenuse,
      rotationDegrees: rotation,
    );
    final id = options['id'] ?? _nextId('triangle', document);
    return GeometryObject(
      id: id,
      kind: GeometryKind.triangle,
      points: solution.vertices,
      label: options['label'] ?? _nextLabel('triangle', document),
      layerId: document.layers.first.id,
      params: {
        'triangleType': 'right',
        'sides': solution.sides,
        'hypotenuse': solution.hypotenuse,
        'rotation': solution.rotationDegrees,
      },
      style: const ObjectStyle(fillColor: 0x1f296fa8),
    );
  }

  GeometryObject _function(
    Map<String, String> options,
    String id,
    String? label,
    String layerId,
  ) {
    final kind = options['kind'] ?? 'explicit';
    if (!const {'explicit', 'parametric', 'polar', 'implicit'}.contains(kind)) {
      throw const PrimitiveException(
        'Function kind must be explicit, parametric, polar or implicit.',
      );
    }
    Map<String, Object?> params = {'kind': kind};
    switch (kind) {
      case 'explicit':
        final expression = options['expr'] ?? options['expression'];
        if (expression == null) {
          throw const PrimitiveException('Explicit function needs --expr.');
        }
        Expression.parse(expression);
        params = {
          ...params,
          'expression': expression,
          'xMin': _number(options, 'x-min', fallback: -10),
          'xMax': _number(options, 'x-max', fallback: 10),
        };
      case 'parametric':
        final xExpression = options['x-expr'];
        final yExpression = options['y-expr'];
        if (xExpression == null || yExpression == null) {
          throw const PrimitiveException(
            'Parametric function needs --x-expr and --y-expr.',
          );
        }
        Expression.parse(xExpression);
        Expression.parse(yExpression);
        params = {
          ...params,
          'xExpression': xExpression,
          'yExpression': yExpression,
          'tMin': _number(options, 't-min', fallback: 0),
          'tMax': _number(options, 't-max', fallback: 6.283185307179586),
        };
      case 'polar':
        final rExpression = options['r-expr'] ?? options['expr'];
        if (rExpression == null) {
          throw const PrimitiveException('Polar function needs --r-expr.');
        }
        Expression.parse(rExpression);
        params = {
          ...params,
          'rExpression': rExpression,
          'tMin': _number(options, 't-min', fallback: 0),
          'tMax': _number(options, 't-max', fallback: 6.283185307179586),
        };
      case 'implicit':
        final expression = options['expr'] ?? options['expression'];
        if (expression == null) {
          throw const PrimitiveException('Implicit function needs --expr.');
        }
        Expression.parse(expression);
        params = {...params, 'expression': expression};
    }
    return GeometryObject(
      id: id,
      kind: GeometryKind.function,
      points: const [],
      label: label,
      layerId: layerId,
      params: params,
    );
  }

  List<Point2> _pointsOption(Map<String, String> options) {
    final raw = options['points'];
    if (raw == null || raw.trim().isEmpty) return const [];
    final result = <Point2>[];
    for (final group in raw.split(';')) {
      final parts = group.split(',');
      if (parts.length != 2) {
        throw const PrimitiveException(
          'Points must be formatted as "x,y;x,y;...".',
        );
      }
      final x = double.tryParse(parts[0].trim());
      final y = double.tryParse(parts[1].trim());
      if (x == null || y == null || !x.isFinite || !y.isFinite) {
        throw const PrimitiveException('Point coordinates must be finite.');
      }
      result.add(Point2(x, y));
    }
    return result;
  }

  Point2 _center(Map<String, String> options, List<Point2> points) {
    final center = options['center'];
    if (center != null) {
      final parts = center.split(',');
      if (parts.length != 2) {
        throw const PrimitiveException('--center must be x,y.');
      }
      final x = double.tryParse(parts[0].trim());
      final y = double.tryParse(parts[1].trim());
      if (x == null || y == null || !x.isFinite || !y.isFinite) {
        throw const PrimitiveException('Center must be finite.');
      }
      return Point2(x, y);
    }
    if (points.isNotEmpty) return points.first;
    return Point2(
      _number(options, 'cx', fallback: 0),
      _number(options, 'cy', fallback: 0),
    );
  }

  double _positiveNumber(
    Map<String, String> options,
    String key, {
    String? fallback,
  }) {
    final raw = options[key] ?? fallback;
    final value = raw == null ? null : double.tryParse(raw);
    if (value == null || !value.isFinite || value <= 0) {
      throw PrimitiveException('--$key must be a positive finite number.');
    }
    return value;
  }

  double _number(Map<String, String> options, String key, {double? fallback}) {
    final raw = options[key];
    if (raw == null) {
      if (fallback != null) return fallback;
      throw PrimitiveException('Missing required option --$key.');
    }
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) {
      throw PrimitiveException('--$key must be a finite number.');
    }
    return value;
  }

  String _nextId(String primitive, GeometryDocument document) {
    var index = 1;
    while (document.objectById('$primitive-$index') != null) {
      index++;
    }
    return '$primitive-$index';
  }

  String? _nextLabel(String primitive, GeometryDocument document) {
    if (primitive == 'point') {
      final count = document.objects
          .where((object) => object.kind == GeometryKind.point)
          .length;
      return autoLabel(count);
    }
    return null;
  }
}
