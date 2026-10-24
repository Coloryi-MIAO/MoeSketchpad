// SPDX-License-Identifier: GPL-3.0-only
/// Triangle specifications shared by the CLI, MCP server and editor.
library;

import 'dart:math' as math;

import 'geometry/point.dart';

class TriangleSpec {
  const TriangleSpec({
    required this.type,
    required this.sides,
    required this.hypotenuse,
    required this.rotationDegrees,
    this.source = 'canonical',
  });

  final String type;
  final List<double> sides;
  final double hypotenuse;
  final double rotationDegrees;
  final String source;
}

class TriangleSolveException implements Exception {
  const TriangleSolveException(this.message);
  final String message;
  @override
  String toString() => 'TriangleSolveException: $message';
}

class TriangleSolution {
  const TriangleSolution({required this.spec, required this.vertices});

  final TriangleSpec spec;
  final List<Point2> vertices;

  List<double> get sides => spec.sides;
  String get type => spec.type;
  double get rotationDegrees => spec.rotationDegrees;
  double get hypotenuse => spec.hypotenuse;
  Point2 get a => vertices[0];
  Point2 get b => vertices[1];
  Point2 get c => vertices[2];

  Map<String, Object?> toJson() => {
    'type': type,
    'sides': sides,
    'hypotenuse': hypotenuse,
    'rotationDegrees': rotationDegrees,
    'vertices': [for (final vertex in vertices) vertex.toJson()],
    'source': spec.source,
  };

  static TriangleSolution right({
    required List<double> sides,
    required double hypotenuse,
    double rotationDegrees = 0,
    double relativeTolerance = 1e-9,
    String source = 'canonical',
  }) {
    if (sides.length != 3 ||
        sides.any((side) => !side.isFinite || side <= 0) ||
        !hypotenuse.isFinite ||
        hypotenuse <= 0 ||
        !rotationDegrees.isFinite ||
        rotationDegrees < 0 ||
        rotationDegrees > 360) {
      throw const TriangleSolveException(
        'Triangle sides must be finite positive numbers; rotation is 0..360.',
      );
    }
    final ordered = [...sides]..sort();
    final scale = ordered.last;
    final squaredError =
        ordered[0] * ordered[0] + ordered[1] * ordered[1] - scale * scale;
    if (squaredError.abs() > relativeTolerance * scale * scale) {
      throw const TriangleSolveException(
        'These sides do not form a right triangle. Suggestion: use 3,4,5.',
      );
    }
    if ((hypotenuse - scale).abs() > relativeTolerance * scale) {
      throw const TriangleSolveException(
        'The hypotenuse must be the longest side. Suggestion: --hypotenuse=5.',
      );
    }
    var legs = sides.where((side) => side != hypotenuse).toList();
    if (legs.length != 2) {
      throw const TriangleSolveException(
        'Two legs and one hypotenuse are required.',
      );
    }
    legs = [legs[0], legs[1]].toList();
    final rotation = degreesToRadians(rotationDegrees % 360);
    final a = Point2.zero;
    final b = Point2(
      hypotenuse * math.cos(rotation),
      hypotenuse * math.sin(rotation),
    );
    final along =
        (legs[0] * legs[0] - legs[1] * legs[1] + hypotenuse * hypotenuse) /
        (2 * hypotenuse);
    final heightSquared = legs[0] * legs[0] - along * along;
    final height = math.sqrt(math.max(0, heightSquared));
    final unit = (b - a) / hypotenuse;
    final normal = Point2(-unit.y, unit.x);
    final c = a + unit * along + normal * height;
    return TriangleSolution(
      spec: TriangleSpec(
        type: 'right',
        sides: List.unmodifiable(sides),
        hypotenuse: hypotenuse,
        rotationDegrees: rotationDegrees,
        source: source,
      ),
      vertices: List.unmodifiable([a, b, c]),
    );
  }
}

final RegExp _shorthandPattern = RegExp(
  r'^--?triangle-([+-]?[0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?)\*([0-9]+(?:\.[0-9]+)?)\*([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?)\/([+-]?[0-9]+(?:\.[0-9]+)?)$',
);

bool isTriangleShorthand(String value) => value.startsWith('--triangle-');

/// Parses the compatibility form:
/// `--triangle-<angleType>-<a>*<b>*<c>-<hypotenuse>/<rotation>`.
TriangleSolution parseTriangleShorthand(String source) {
  final match = _shorthandPattern.firstMatch(source);
  if (match == null) {
    throw const TriangleSolveException(
      'Malformed triangle shorthand. Expected '
      '--triangle-90-3*4*5-5/180.',
    );
  }
  final angleType = double.tryParse(match.group(1)!);
  if (angleType == null || (angleType - 90).abs() > 1e-9) {
    throw TriangleSolveException(
      'Unsupported angle type "${match.group(1)}"; only 90 is implemented. '
      'Use --type=right with explicit sides.',
    );
  }
  final sides = [
    double.parse(match.group(2)!),
    double.parse(match.group(3)!),
    double.parse(match.group(4)!),
  ];
  final hypotenuse = double.tryParse(match.group(5)!);
  final rotation = double.tryParse(match.group(6)!);
  if (hypotenuse == null || rotation == null) {
    throw const TriangleSolveException('Triangle numbers are malformed.');
  }
  return TriangleSolution.right(
    sides: sides,
    hypotenuse: hypotenuse,
    rotationDegrees: rotation,
    source: 'shorthand',
  );
}

double degreesToRadians(double degrees) => degrees * math.pi / 180;
