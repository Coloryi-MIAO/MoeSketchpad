// SPDX-License-Identifier: GPL-3.0-only
import 'package:moesketchpad_core/moesketchpad_core.dart';

class GeometryConstruction {
  const GeometryConstruction._();

  static GeometryObject twoPoint({
    required String id,
    required GeometryKind kind,
    required Point2 first,
    required Point2 second,
  }) {
    if (!{
      GeometryKind.segment,
      GeometryKind.line,
      GeometryKind.ray,
      GeometryKind.vector,
      GeometryKind.circle,
    }.contains(kind)) {
      throw ArgumentError.value(kind, 'kind', 'Not a two-point construction.');
    }
    if (!first.isFinite() ||
        !second.isFinite() ||
        first.distanceTo(second) <= 1e-12) {
      throw const FormatException(
        'Geometry requires two distinct finite points.',
      );
    }
    return GeometryObject(id: id, kind: kind, points: [first, second]);
  }

  static GeometryObject arc({
    required String id,
    required Point2 center,
    required Point2 start,
    required Point2 endDirection,
    double tolerance = 1e-12,
  }) {
    final radius = center.distanceTo(start);
    final direction = endDirection - center;
    if (!center.isFinite() ||
        !start.isFinite() ||
        !endDirection.isFinite() ||
        !tolerance.isFinite ||
        tolerance <= 0 ||
        radius <= tolerance ||
        direction.length <= tolerance) {
      throw const FormatException(
        'Arc requires a center and distinct start/end directions.',
      );
    }
    return GeometryObject(
      id: id,
      kind: GeometryKind.arc,
      points: [center, start, center + direction.normalized() * radius],
    );
  }
}
