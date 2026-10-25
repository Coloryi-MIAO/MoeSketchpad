// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/ui/canvas/geometry_construction.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

void main() {
  test('two-point tools create rays and arrowed vectors', () {
    final first = const Point2(1, 2);
    final second = const Point2(4, 6);
    final ray = GeometryConstruction.twoPoint(
      id: 'ray-1',
      kind: GeometryKind.ray,
      first: first,
      second: second,
    );
    final vector = GeometryConstruction.twoPoint(
      id: 'vector-1',
      kind: GeometryKind.vector,
      first: first,
      second: second,
    );

    expect(ray.kind, GeometryKind.ray);
    expect(ray.points, [first, second]);
    expect(vector.kind, GeometryKind.vector);
    expect(vector.points, [first, second]);
  });

  test('three-point arc projects endpoint to the start radius', () {
    final center = const Point2(2, 3);
    final start = const Point2(5, 3);
    final object = GeometryConstruction.arc(
      id: 'arc-1',
      center: center,
      start: start,
      endDirection: const Point2(2, 8),
    );

    expect(object.kind, GeometryKind.arc);
    expect(object.points, hasLength(3));
    expect(
      center.distanceTo(object.points[1]),
      closeTo(center.distanceTo(object.points[2]), 1e-12),
    );
    expect(object.points[2], const Point2(2, 6));
  });

  test('construction rejects degenerate points and arcs', () {
    expect(
      () => GeometryConstruction.twoPoint(
        id: 'ray',
        kind: GeometryKind.ray,
        first: const Point2(1, 1),
        second: const Point2(1, 1),
      ),
      throwsFormatException,
    );
    expect(
      () => GeometryConstruction.arc(
        id: 'arc',
        center: const Point2(0, 0),
        start: const Point2(0, 0),
        endDirection: const Point2(1, 0),
      ),
      throwsFormatException,
    );
  });
}
