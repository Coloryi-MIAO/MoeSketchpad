// SPDX-License-Identifier: GPL-3.0-only
/// Live measurements attached to document objects.
library;

import 'dart:math' as math;

import 'expression/expression.dart';
import 'geometry/intersections.dart';
import 'geometry/object.dart';
import 'geometry/point.dart';

class MeasurementValue {
  const MeasurementValue({
    required this.rawValue,
    required this.display,
    required this.unit,
    this.note,
  });

  final double rawValue;
  final String display;
  final String unit;
  final String? note;

  Map<String, Object?> toJson() => {
    'rawValue': rawValue,
    'display': display,
    'unit': unit,
    if (note != null) 'note': note,
  };
}

class MeasurementEngine {
  const MeasurementEngine();

  MeasurementValue measure(Measurement measurement, GeometryDocument document) {
    if (!measurement.visible) {
      return MeasurementValue(
        rawValue: 0,
        display: '',
        unit: measurement.unit.name,
        note: 'hidden',
      );
    }
    final objects = [
      for (final id in measurement.targetIds) _requireObject(document, id),
    ];
    final raw = switch (measurement.type) {
      MeasurementType.length => _length(objects),
      MeasurementType.arcLength => _arcLength(objects),
      MeasurementType.angle => _angle(objects),
      MeasurementType.area => _area(objects),
      MeasurementType.slope => _slope(objects),
      MeasurementType.functionValue => _functionValue(objects),
    };
    return _format(raw, measurement, document.view.unitScaleMm);
  }

  GeometryObject _requireObject(GeometryDocument document, String id) {
    final object = document.objectById(id);
    if (object == null) {
      throw FormatException('Measurement target "$id" does not exist.');
    }
    return object;
  }

  double _length(List<GeometryObject> objects) {
    if (objects.length != 1) {
      throw const FormatException('Length measurement needs one object.');
    }
    final object = objects.single;
    switch (object.kind) {
      case GeometryKind.segment:
      case GeometryKind.line:
      case GeometryKind.ray:
      case GeometryKind.vector:
        return object.points[0].distanceTo(object.points[1]);
      case GeometryKind.circle:
        return 2 * math.pi * object.points[0].distanceTo(object.points[1]);
      case GeometryKind.arc:
        return _arcLength(objects);
      case GeometryKind.polygon:
      case GeometryKind.triangle:
        var perimeter = 0.0;
        for (var i = 0; i < object.points.length; i++) {
          perimeter += object.points[i].distanceTo(
            object.points[(i + 1) % object.points.length],
          );
        }
        return perimeter;
      default:
        throw FormatException('Cannot measure length of ${object.kind.name}.');
    }
  }

  double _arcLength(List<GeometryObject> objects) {
    if (objects.length != 1 || objects.single.kind != GeometryKind.arc) {
      throw const FormatException('Arc length needs one arc object.');
    }
    final arc = objects.single;
    final center = arc.points[0];
    final radius = center.distanceTo(arc.points[1]);
    final start = math.atan2(
      arc.points[1].y - center.y,
      arc.points[1].x - center.x,
    );
    final end = math.atan2(
      arc.points[2].y - center.y,
      arc.points[2].x - center.x,
    );
    var sweep = end - start;
    while (sweep < 0) {
      sweep += 2 * math.pi;
    }
    while (sweep > 2 * math.pi) {
      sweep -= 2 * math.pi;
    }
    return radius * sweep;
  }

  double _angle(List<GeometryObject> objects) {
    if (objects.length == 3) {
      return radiansToDegrees(
        angleAt(
          objects[0].points.first,
          objects[1].points.first,
          objects[2].points.first,
        ),
      );
    }
    if (objects.length == 2) {
      final first = _direction(objects[0]);
      final second = _direction(objects[1]);
      final cosine = (first.normalized().dot(
        second.normalized(),
      )).clamp(-1.0, 1.0);
      return radiansToDegrees(math.acos(cosine));
    }
    if (objects.length == 1 && objects.single.points.length >= 3) {
      final points = objects.single.points;
      return radiansToDegrees(angleAt(points[0], points[1], points[2]));
    }
    throw const FormatException('Angle measurement needs 1..3 objects.');
  }

  double _area(List<GeometryObject> objects) {
    if (objects.length != 1) {
      throw const FormatException('Area measurement needs one object.');
    }
    final object = objects.single;
    switch (object.kind) {
      case GeometryKind.circle:
        final radius = object.points[0].distanceTo(object.points[1]);
        return math.pi * radius * radius;
      case GeometryKind.polygon:
      case GeometryKind.triangle:
        return polygonArea(object.points);
      default:
        throw FormatException('Cannot measure area of ${object.kind.name}.');
    }
  }

  double _slope(List<GeometryObject> objects) {
    if (objects.length != 1) {
      throw const FormatException('Slope measurement needs one object.');
    }
    final direction = _direction(objects.single);
    if ((direction.x).abs() <= 1e-15) {
      throw const FormatException('Vertical line has no finite slope.');
    }
    return direction.y / direction.x;
  }

  double _functionValue(List<GeometryObject> objects) {
    if (objects.isEmpty || objects.first.kind != GeometryKind.function) {
      throw const FormatException('Function value needs a function object.');
    }
    final function = objects.first;
    final expression = function.params['expression'];
    if (expression is! String) {
      throw const FormatException('Function has no explicit expression.');
    }
    final x = objects.length > 1
        ? objects[1].points.first.x
        : (function.params['x'] as num?)?.toDouble() ?? 0;
    return Expression.parse(expression).evaluate({'x': x});
  }

  Point2 _direction(GeometryObject object) {
    if (object.points.length < 2) {
      throw FormatException('Object ${object.id} has no direction vector.');
    }
    return object.points[1] - object.points[0];
  }

  MeasurementValue _format(
    double raw,
    Measurement measurement,
    double unitScaleMm,
  ) {
    final isArea = measurement.type == MeasurementType.area;
    final isAngle = measurement.type == MeasurementType.angle;
    if (isAngle) {
      return MeasurementValue(
        rawValue: raw,
        display: '${raw.toStringAsFixed(measurement.decimals)}°',
        unit: 'deg',
      );
    }
    final conversion = switch (measurement.unit) {
      MeasureUnit.unitless || MeasureUnit.px => 1.0,
      MeasureUnit.cm => unitScaleMm / 10,
      MeasureUnit.mm => unitScaleMm,
      MeasureUnit.custom => measurement.customScale,
    };
    final exponent = isArea ? 2 : 1;
    final scaled = raw * math.pow(conversion, exponent);
    final suffix = switch (measurement.unit) {
      MeasureUnit.unitless => '',
      MeasureUnit.cm => isArea ? ' cm²' : ' cm',
      MeasureUnit.mm => isArea ? ' mm²' : ' mm',
      MeasureUnit.px => isArea ? ' px²' : ' px',
      MeasureUnit.custom => '',
    };
    return MeasurementValue(
      rawValue: raw,
      display: '${scaled.toStringAsFixed(measurement.decimals)}$suffix',
      unit: measurement.unit.name,
    );
  }
}
