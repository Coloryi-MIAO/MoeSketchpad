// SPDX-License-Identifier: GPL-3.0-only
/// A bounded damped least-squares solver for the supported constraint set.
library;

import 'dart:math' as math;

import 'geometry/object.dart';
import 'geometry/point.dart';

class ConstraintSolveResult {
  const ConstraintSolveResult({
    required this.document,
    required this.converged,
    required this.iterations,
    required this.residual,
    this.message,
  });

  final GeometryDocument document;
  final bool converged;
  final int iterations;
  final double residual;
  final String? message;
}

class ConstraintSolver {
  const ConstraintSolver({
    this.tolerance = const GeometryTolerance(relative: 1e-9, absolute: 1e-9),
    this.maxIterations = 120,
  });

  final GeometryTolerance tolerance;
  final int maxIterations;

  ConstraintSolveResult solve(GeometryDocument document) {
    if (document.constraints.isEmpty) {
      return ConstraintSolveResult(
        document: document,
        converged: true,
        iterations: 0,
        residual: 0,
      );
    }
    final points = <_PointRef>[];
    for (
      var objectIndex = 0;
      objectIndex < document.objects.length;
      objectIndex++
    ) {
      final object = document.objects[objectIndex];
      if (object.locked || object.params['fixed'] == true) continue;
      for (
        var pointIndex = 0;
        pointIndex < object.points.length;
        pointIndex++
      ) {
        points.add(
          _PointRef(objectIndex, pointIndex, object.points[pointIndex]),
        );
      }
    }
    if (points.isEmpty) {
      return ConstraintSolveResult(
        document: document,
        converged: false,
        iterations: 0,
        residual: double.infinity,
        message: 'No movable points; all geometry is locked.',
      );
    }
    final positions = [
      for (final point in points)
        [
          ...[point.value.x, point.value.y],
        ],
    ];
    final evaluator = _ResidualEvaluator(document, points, tolerance);
    var lambda = 1e-3;
    var residual = evaluator.residualNorm(positions);
    var iterations = 0;
    for (; iterations < maxIterations; iterations++) {
      if (residual <= tolerance.absolute) {
        break;
      }
      final jacobian = evaluator.jacobian(positions);
      final values = evaluator.residuals(positions);
      final variableCount = points.length * 2;
      final normal = List.generate(
        variableCount,
        (_) => List<double>.filled(variableCount, 0),
      );
      final gradient = List<double>.filled(variableCount, 0);
      for (var row = 0; row < values.length; row++) {
        for (var column = 0; column < variableCount; column++) {
          gradient[column] += jacobian[row][column] * values[row];
          for (var other = 0; other < variableCount; other++) {
            normal[column][other] +=
                jacobian[row][column] * jacobian[row][other];
          }
        }
      }
      for (var i = 0; i < variableCount; i++) {
        normal[i][i] += lambda * math.max(1, normal[i][i]);
      }
      final step = _solveLinear(normal, [for (final value in gradient) -value]);
      if (step == null) {
        lambda *= 10;
        if (lambda > 1e12) break;
        continue;
      }
      final candidate = [
        for (var i = 0; i < positions.length; i++)
          [positions[i][0] + step[i * 2], positions[i][1] + step[i * 2 + 1]],
      ];
      final candidateResidual = evaluator.residualNorm(candidate);
      if (candidateResidual < residual) {
        positions
          ..clear()
          ..addAll(candidate);
        residual = candidateResidual;
        lambda = math.max(lambda * 0.5, 1e-12);
      } else {
        lambda *= 5;
        if (lambda > 1e12) break;
      }
    }
    final objects = [
      for (var i = 0; i < document.objects.length; i++) document.objects[i],
    ];
    for (var i = 0; i < points.length; i++) {
      final ref = points[i];
      final object = objects[ref.objectIndex];
      final updatedPoints = [...object.points];
      updatedPoints[ref.pointIndex] = Point2(positions[i][0], positions[i][1]);
      objects[ref.objectIndex] = object.copyWith(points: updatedPoints);
    }
    final solvedDocument = document.copyWith(objects: objects);
    return ConstraintSolveResult(
      document: solvedDocument,
      converged: residual <= tolerance.absolute,
      iterations: iterations,
      residual: residual,
      message: residual <= tolerance.absolute
          ? null
          : 'Constraints could not be satisfied within tolerance.',
    );
  }
}

class _PointRef {
  const _PointRef(this.objectIndex, this.pointIndex, this.value);
  final int objectIndex;
  final int pointIndex;
  final Point2 value;
}

class _ResidualEvaluator {
  _ResidualEvaluator(this.document, this.variables, this.tolerance)
    : _index = {
        for (var i = 0; i < variables.length; i++)
          _key(variables[i].objectIndex, variables[i].pointIndex): i,
      };

  final GeometryDocument document;
  final List<_PointRef> variables;
  final GeometryTolerance tolerance;
  final Map<String, int> _index;

  static String _key(int objectIndex, int pointIndex) =>
      '$objectIndex:$pointIndex';

  Point2 _point(String id, List<List<double>> positions, {int pointIndex = 0}) {
    final objectIndex = document.objects.indexWhere(
      (object) => object.id == id,
    );
    if (objectIndex < 0) {
      throw FormatException('Constraint references unknown object "$id".');
    }
    final object = document.objects[objectIndex];
    final variableIndex = _index[_key(objectIndex, pointIndex)];
    if (variableIndex != null) {
      final value = positions[variableIndex];
      return Point2(value[0], value[1]);
    }
    if (pointIndex >= object.points.length) {
      throw FormatException('Object "$id" has no point at $pointIndex.');
    }
    return object.points[pointIndex];
  }

  List<Point2> _objectPoints(String id, List<List<double>> positions) {
    final objectIndex = document.objects.indexWhere(
      (object) => object.id == id,
    );
    if (objectIndex < 0) {
      throw FormatException('Constraint references unknown object "$id".');
    }
    final object = document.objects[objectIndex];
    return [
      for (var i = 0; i < object.points.length; i++)
        _point(id, positions, pointIndex: i),
    ];
  }

  List<double> residuals(List<List<double>> positions) {
    final result = <double>[];
    for (final constraint in document.constraints) {
      final targets = constraint.targetIds;
      switch (constraint.type) {
        case ConstraintType.coincident:
          _require(targets.length == 2, constraint);
          final a = _point(targets[0], positions);
          final b = _point(targets[1], positions);
          result
            ..add(a.x - b.x)
            ..add(a.y - b.y);
        case ConstraintType.distance:
          _require(targets.length == 2 && constraint.value != null, constraint);
          final a = _point(targets[0], positions);
          final b = _point(targets[1], positions);
          result.add(a.distanceTo(b) - constraint.value!);
        case ConstraintType.horizontal:
          final pair = _pair(targets, positions);
          result.add(pair.$1.y - pair.$2.y);
        case ConstraintType.vertical:
          final pair = _pair(targets, positions);
          result.add(pair.$1.x - pair.$2.x);
        case ConstraintType.pointOnLine:
          _require(targets.length == 2 || targets.length == 3, constraint);
          final p = _point(targets[0], positions);
          final a = targets.length == 3
              ? _point(targets[1], positions)
              : _objectPoints(targets[1], positions)[0];
          final b = targets.length == 3
              ? _point(targets[2], positions)
              : _objectPoints(targets[1], positions)[1];
          final scale = math.max(1.0, (b - a).length);
          result.add(((b - a).cross(p - a)) / scale);
        case ConstraintType.pointOnCircle:
          _require(targets.length == 2, constraint);
          final p = _point(targets[0], positions);
          final circle = _objectPoints(targets[1], positions);
          final center = circle[0];
          final radius = center.distanceTo(circle[1]);
          result.add(p.distanceTo(center) - radius);
        case ConstraintType.parallel:
          final pair = _directions(targets, positions);
          result.add(pair.$1.cross(pair.$2));
        case ConstraintType.perpendicular:
          final pair = _directions(targets, positions);
          result.add(pair.$1.dot(pair.$2));
        case ConstraintType.equalLength:
          _require(targets.length == 2, constraint);
          final first = _objectPoints(targets[0], positions);
          final second = _objectPoints(targets[1], positions);
          final firstLength = first.last.distanceTo(first.first);
          final secondLength = second.last.distanceTo(second.first);
          result.add(firstLength - secondLength);
        case ConstraintType.angle:
          _require(targets.length == 2 && constraint.value != null, constraint);
          final pair = _directions(targets, positions);
          final cosine = (pair.$1.normalized().dot(
            pair.$2.normalized(),
          )).clamp(-1.0, 1.0);
          result.add(math.acos(cosine) - constraint.value! * math.pi / 180);
        case ConstraintType.tangent:
        case ConstraintType.tangentLineCircle:
          _require(targets.length == 2, constraint);
          final firstIndex = document.objects.indexWhere(
            (object) => object.id == targets[0],
          );
          final secondIndex = document.objects.indexWhere(
            (object) => object.id == targets[1],
          );
          if (firstIndex < 0 || secondIndex < 0) {
            throw FormatException(
              'Constraint "${constraint.id}" references an unknown object.',
            );
          }
          final first = document.objects[firstIndex];
          final second = document.objects[secondIndex];
          final lineIndex = first.kind == GeometryKind.line
              ? firstIndex
              : second.kind == GeometryKind.line
              ? secondIndex
              : -1;
          final circleIndex = first.kind == GeometryKind.circle
              ? firstIndex
              : second.kind == GeometryKind.circle
              ? secondIndex
              : -1;
          _require(lineIndex >= 0 && circleIndex >= 0, constraint);
          final line = document.objects[lineIndex];
          final linePoints = _objectPoints(line.id, positions);
          final direction = linePoints[1] - linePoints[0];
          _require(direction.length > tolerance.absolute, constraint);
          final circle = _objectPoints(
            document.objects[circleIndex].id,
            positions,
          );
          final radius = circle[0].distanceTo(circle[1]);
          final distance =
              direction.cross(circle[0] - linePoints[0]).abs() /
              direction.length;
          result.add(distance - radius);
        case ConstraintType.tangentCircleCircle:
          _require(targets.length == 2, constraint);
          final circles = [
            for (final id in targets)
              document.objects.where((object) => object.id == id).firstOrNull,
          ];
          _require(
            circles.every(
              (object) => object != null && object.kind == GeometryKind.circle,
            ),
            constraint,
          );
          final first = _objectPoints(targets[0], positions);
          final second = _objectPoints(targets[1], positions);
          final firstRadius = first[0].distanceTo(first[1]);
          final secondRadius = second[0].distanceTo(second[1]);
          result.add(
            first[0].distanceTo(second[0]) - firstRadius - secondRadius,
          );
      }
    }
    return result;
  }

  void _require(bool condition, Constraint constraint) {
    if (!condition) {
      throw FormatException('Constraint "${constraint.id}" is malformed.');
    }
  }

  (Point2, Point2) _pair(List<String> targets, List<List<double>> positions) {
    if (targets.length == 2) {
      final firstObject = document.objects
          .where((object) => object.id == targets[0])
          .firstOrNull;
      if (firstObject?.kind == GeometryKind.point ||
          firstObject?.kind == GeometryKind.vector) {
        return (_point(targets[0], positions), _point(targets[1], positions));
      }
    }
    _require(
      targets.length == 1,
      const Constraint(id: '_', type: ConstraintType.horizontal, targetIds: []),
    );
    final points = _objectPoints(targets[0], positions);
    return (points[0], points[1]);
  }

  (Point2, Point2) _directions(
    List<String> targets,
    List<List<double>> positions,
  ) {
    if (targets.length == 2) {
      final first = document.objects
          .where((object) => object.id == targets[0])
          .firstOrNull;
      if (first?.kind == GeometryKind.point ||
          first?.kind == GeometryKind.vector) {
        final a = _point(targets[0], positions);
        final b = _point(targets[1], positions);
        return (a, b);
      }
    }
    _require(
      targets.length == 2,
      const Constraint(id: '_', type: ConstraintType.parallel, targetIds: []),
    );
    final a = _objectPoints(targets[0], positions);
    final b = _objectPoints(targets[1], positions);
    return (a.last - a.first, b.last - b.first);
  }

  double residualNorm(List<List<double>> positions) {
    final values = residuals(positions);
    if (values.any((value) => !value.isFinite)) return double.infinity;
    var squared = 0.0;
    for (final value in values) {
      squared += value * value;
    }
    return math.sqrt(squared);
  }

  List<List<double>> jacobian(List<List<double>> positions) {
    final base = residuals(positions);
    final rows = <List<double>>[];
    for (var row = 0; row < base.length; row++) {
      final values = List<double>.filled(variables.length * 2, 0);
      for (var variable = 0; variable < variables.length; variable++) {
        for (var axis = 0; axis < 2; axis++) {
          final original = positions[variable][axis];
          final step = 1e-6 * math.max(1, original.abs());
          positions[variable][axis] = original + step;
          final increased = residuals(positions)[row];
          positions[variable][axis] = original - step;
          final decreased = residuals(positions)[row];
          positions[variable][axis] = original;
          values[variable * 2 + axis] = (increased - decreased) / (2 * step);
        }
      }
      rows.add(values);
    }
    return rows;
  }
}

List<double>? _solveLinear(List<List<double>> matrix, List<double> rhs) {
  final n = rhs.length;
  final a = [
    for (var i = 0; i < n; i++) [...matrix[i], rhs[i]],
  ];
  for (var column = 0; column < n; column++) {
    var pivot = column;
    for (var row = column + 1; row < n; row++) {
      if (a[row][column].abs() > a[pivot][column].abs()) pivot = row;
    }
    if (a[pivot][column].abs() < 1e-15) return null;
    if (pivot != column) {
      final temp = a[pivot];
      a[pivot] = a[column];
      a[column] = temp;
    }
    final divisor = a[column][column];
    for (var j = column; j <= n; j++) {
      a[column][j] /= divisor;
    }
    for (var row = 0; row < n; row++) {
      if (row == column) continue;
      final factor = a[row][column];
      if (factor == 0) continue;
      for (var j = column; j <= n; j++) {
        a[row][j] -= factor * a[column][j];
      }
    }
  }
  return [for (var i = 0; i < n; i++) a[i][n]];
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
