// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;

class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(Point2 other) =>
      math.sqrt((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y));

  Map<String, Object> toJson() => {'x': x, 'y': y};

  factory Point2.fromJson(Map<String, dynamic> json) {
    final x = json['x'];
    final y = json['y'];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
      throw const FormatException('Point coordinates must be finite numbers.');
    }
    return Point2(x.toDouble(), y.toDouble());
  }
}

class Bounds2 {
  const Bounds2(this.left, this.top, this.right, this.bottom)
    : assert(left <= right),
      assert(top <= bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

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

  Bounds2 union(Bounds2 other) => Bounds2(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );
}

class GeometryObject {
  const GeometryObject({
    required this.id,
    required this.kind,
    required this.points,
    this.label,
  });

  final String id;
  final String kind;
  final List<Point2> points;
  final String? label;

  Bounds2 get bounds {
    if (points.isEmpty) {
      throw StateError('Geometry objects must contain at least one point.');
    }
    var result = Bounds2(
      points.first.x,
      points.first.y,
      points.first.x,
      points.first.y,
    );
    for (final point in points.skip(1)) {
      result = result.union(Bounds2(point.x, point.y, point.x, point.y));
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'points': points.map((point) => point.toJson()).toList(),
    if (label != null) 'label': label,
  };

  factory GeometryObject.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final kind = json['kind'];
    final rawPoints = json['points'];
    if (id is! String || id.isEmpty || kind is! String || rawPoints is! List) {
      throw const FormatException('Invalid geometry object.');
    }
    return GeometryObject(
      id: id,
      kind: kind,
      points: rawPoints
          .map(
            (point) => Point2.fromJson(Map<String, dynamic>.from(point as Map)),
          )
          .toList(growable: false),
      label: json['label'] as String?,
    );
  }
}

class GeometryDocument {
  GeometryDocument({required this.objects, this.metadata = const {}});

  final List<GeometryObject> objects;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => {
    'format': 'moesketchpad-document',
    'schemaVersion': 1,
    'objects': objects.map((object) => object.toJson()).toList(),
    'metadata': metadata,
  };

  factory GeometryDocument.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'moesketchpad-document' ||
        json['schemaVersion'] != 1 ||
        json['objects'] is! List) {
      throw const FormatException('Unsupported MoeSketchpad document payload.');
    }
    return GeometryDocument(
      objects: (json['objects'] as List)
          .map(
            (item) =>
                GeometryObject.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      metadata: json['metadata'] is Map
          ? Map<String, Object?>.from(json['metadata'] as Map)
          : const {},
    );
  }
}

class TriangleSolution {
  const TriangleSolution({
    required this.sides,
    required this.rotationDegrees,
    required this.type,
  });

  final List<double> sides;
  final double rotationDegrees;
  final String type;

  static TriangleSolution right({
    required List<double> sides,
    required double hypotenuse,
    double rotationDegrees = 0,
    double relativeTolerance = 1e-9,
  }) {
    if (sides.length != 3 ||
        sides.any((side) => !side.isFinite || side <= 0) ||
        !hypotenuse.isFinite ||
        !rotationDegrees.isFinite) {
      throw const FormatException(
        'Triangle sides and rotation must be finite and positive.',
      );
    }
    final sorted = [...sides]..sort();
    final scale = sorted.last;
    final pythagoreanError =
        (sorted[0] * sorted[0] + sorted[1] * sorted[1] - scale * scale).abs();
    if (pythagoreanError > relativeTolerance * scale * scale) {
      throw const FormatException('These sides do not form a right triangle.');
    }
    if ((hypotenuse - scale).abs() > relativeTolerance * scale) {
      throw const FormatException('The hypotenuse must be the longest side.');
    }
    return TriangleSolution(
      sides: List.unmodifiable(sides),
      rotationDegrees: rotationDegrees,
      type: 'right',
    );
  }

  Map<String, Object> toJson() => {
    'type': type,
    'sides': sides,
    'hypotenuse': sides.reduce(math.max),
    'rotationDegrees': rotationDegrees,
  };
}

class ExpressionEvaluator {
  const ExpressionEvaluator();

  double evaluate(String source, {Map<String, double> variables = const {}}) {
    final parser = _ExpressionParser(source, variables);
    final result = parser.parse();
    if (!result.isFinite) {
      throw const FormatException('Expression result is not finite.');
    }
    return result;
  }
}

class _ExpressionParser {
  _ExpressionParser(this.source, this.variables);

  static const int _maximumNesting = 64;
  final String source;
  final Map<String, double> variables;
  int _index = 0;
  int _nesting = 0;

  double parse() {
    if (source.length > 4096) {
      throw const FormatException('Expression exceeds the maximum length.');
    }
    final result = _sum();
    _skipSpaces();
    if (_index != source.length) {
      throw FormatException('Unexpected token at position $_index.');
    }
    return result;
  }

  double _sum() {
    var value = _product();
    while (true) {
      if (_take('+')) {
        value += _product();
      } else if (_take('-')) {
        value -= _product();
      } else {
        return value;
      }
    }
  }

  double _product() {
    var value = _unary();
    while (true) {
      if (_take('*')) {
        value *= _unary();
      } else if (_take('/')) {
        final divisor = _unary();
        if (divisor == 0) throw const FormatException('Division by zero.');
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  double _power() {
    final base = _primary();
    return _take('^') ? math.pow(base, _nested(_unary)).toDouble() : base;
  }

  double _unary() {
    if (_take('+')) return _nested(_unary);
    if (_take('-')) return -_nested(_unary);
    return _power();
  }

  double _primary() {
    _skipSpaces();
    if (_take('(')) {
      return _nested(() {
        final value = _sum();
        if (!_take(')')) {
          throw const FormatException('Missing closing parenthesis.');
        }
        return value;
      });
    }
    if (_index < source.length &&
        (source[_index].contains(RegExp(r'[0-9.]')))) {
      return _number();
    }
    final identifier = _identifier();
    if (identifier.isEmpty) {
      throw FormatException('Expected a number at position $_index.');
    }
    if (identifier == 'pi') return math.pi;
    if (identifier == 'e') return math.e;
    if (variables.containsKey(identifier)) return variables[identifier]!;
    if (!_take('(')) {
      throw FormatException('Unknown variable "$identifier".');
    }
    final argument = _nested(() {
      final value = _sum();
      if (!_take(')')) {
        throw const FormatException('Missing closing parenthesis.');
      }
      return value;
    });
    return switch (identifier) {
      'sin' => math.sin(argument),
      'cos' => math.cos(argument),
      'tan' => math.tan(argument),
      'sqrt' when argument >= 0 => math.sqrt(argument),
      'abs' => argument.abs(),
      'ln' when argument > 0 => math.log(argument),
      _ => throw FormatException('Unsupported function "$identifier".'),
    };
  }

  double _number() {
    _skipSpaces();
    final start = _index;
    while (_index < source.length &&
        RegExp(r'[0-9.eE+-]').hasMatch(source[_index])) {
      if ((_isSign(source[_index])) &&
          _index > start &&
          source[_index - 1] != 'e' &&
          source[_index - 1] != 'E') {
        break;
      }
      _index++;
    }
    final value = double.tryParse(source.substring(start, _index));
    if (value == null || !value.isFinite) {
      throw FormatException('Invalid number at position $start.');
    }
    return value;
  }

  String _identifier() {
    _skipSpaces();
    final start = _index;
    while (_index < source.length &&
        RegExp(r'[a-zA-Z_]').hasMatch(source[_index])) {
      _index++;
    }
    return source.substring(start, _index);
  }

  bool _take(String token) {
    _skipSpaces();
    if (source.startsWith(token, _index)) {
      _index += token.length;
      return true;
    }
    return false;
  }

  void _skipSpaces() {
    while (_index < source.length && source[_index].trim().isEmpty) {
      _index++;
    }
  }

  bool _isSign(String value) => value == '+' || value == '-';

  double _nested(double Function() parse) {
    if (++_nesting > _maximumNesting) {
      _nesting--;
      throw const FormatException('Expression nesting limit exceeded.');
    }
    try {
      return parse();
    } finally {
      _nesting--;
    }
  }
}
