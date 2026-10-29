// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

void main() {
  group('safe expression AST', () {
    const evaluator = ExpressionEvaluator();

    test('evaluates arithmetic, powers, functions and variables', () {
      expect(evaluator.evaluate('sqrt(3^2 + 4^2)'), 5);
      expect(evaluator.evaluate('-2^2'), -4);
      expect(evaluator.evaluate('2^3^2'), 512);
      expect(
        evaluator.evaluate('x * pi', variables: {'x': 2}),
        closeTo(2 * 3.141592653589793, 1e-12),
      );
    });

    test('rejects unsafe or unbounded input', () {
      expect(
        () => evaluator.evaluate('1/0'),
        throwsA(isA<EvaluationException>()),
      );
      expect(() => evaluator.evaluate('unknown(2)'), throwsFormatException);
      expect(() => evaluator.evaluate('1; print(2)'), throwsFormatException);
      expect(() => evaluator.evaluate('a' * 5000), throwsFormatException);
    });
  });

  group('geometry', () {
    test('line intersections distinguish parallel and crossing', () {
      final crossing = intersectLines(
        const Point2(0, 0),
        const Point2(2, 2),
        const Point2(0, 2),
        const Point2(2, 0),
      );
      expect(crossing.kind, IntersectionKind.one);
      expect(crossing.points.single.x, closeTo(1, 1e-12));

      final parallel = intersectLines(
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(0, 1),
        const Point2(1, 1),
      );
      expect(parallel.kind, IntersectionKind.none);
    });

    test('line-circle and circle-circle intersections', () {
      final line = intersectLineCircle(
        const Point2(-10, 0),
        const Point2(10, 0),
        const Point2(0, 0),
        2,
        segment: true,
      );
      expect(line.points.length, 2);
      final circles = intersectCircles(
        const Point2(0, 0),
        2,
        const Point2(3, 0),
        2,
      );
      expect(circles.points.length, 2);
    });

    test('R-tree query and removal', () {
      final tree = RTree<String>();
      for (var i = 0; i < 100; i++) {
        tree.insert('item-$i', Bounds2(i.toDouble(), 0, i + 0.5, 1), 'v$i');
      }
      expect(tree.search(const Bounds2(0, 0, 10, 2)).length, 11);
      expect(tree.remove('item-5'), isTrue);
      expect(tree.search(const Bounds2(0, 0, 10, 2)).length, 10);
    });

    test('right triangle shorthand solves and rejects impossible sides', () {
      final triangle = parseTriangleShorthand('--triangle-90-3*4*5-5/180');
      expect(triangle.sides, [3, 4, 5]);
      expect(triangle.vertices.length, 3);
      expect(
        () => parseTriangleShorthand('--triangle-90-2*3*4-4/0'),
        throwsA(isA<TriangleSolveException>()),
      );
    });
  });

  test('MSP v2 compresses, encrypts and authenticates', () async {
    final codec = MspCodec();
    final document = GeometryDocument(
      objects: [
        const GeometryObject(
          id: 'A',
          kind: GeometryKind.point,
          points: [Point2(1.5, -2)],
          label: 'A',
        ),
      ],
    );
    final encoded = await codec.encode(document, password: 'test-password');
    expect(String.fromCharCodes(encoded.take(12)), 'MOESKETCHPAD');
    expect(codec.validate(encoded).compressed, isTrue);
    final decoded = await codec.decode(encoded, password: 'test-password');
    expect(decoded.objects.single.points.single.x, 1.5);
    await expectLater(
      codec.decode(encoded, password: 'incorrect'),
      throwsA(isA<MspDecryptionException>()),
    );
    final tampered = [...encoded];
    tampered[20] ^= 1;
    await expectLater(
      codec.decode(tampered, password: 'test-password'),
      throwsA(anyOf(isA<MspDecryptionException>(), isA<MspFormatException>())),
    );
  });
}
