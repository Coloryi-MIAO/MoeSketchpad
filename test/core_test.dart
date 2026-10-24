// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/core/geometry.dart';
import 'package:moesketchpad/core/msp_codec.dart';

void main() {
  group('ExpressionEvaluator', () {
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

    test('rejects invalid and unsafe expressions', () {
      expect(() => evaluator.evaluate('1 / 0'), throwsFormatException);
      expect(() => evaluator.evaluate('unknown(2)'), throwsFormatException);
      expect(() => evaluator.evaluate('1; print(2)'), throwsFormatException);
    });
  });

  group('TriangleSolution', () {
    test('accepts a right triangle and rotation', () {
      final value = TriangleSolution.right(
        sides: [3, 4, 5],
        hypotenuse: 5,
        rotationDegrees: 180,
      );
      expect(value.toJson()['rotationDegrees'], 180);
    });

    test('rejects impossible right-triangle sides', () {
      expect(
        () => TriangleSolution.right(sides: [2, 3, 4], hypotenuse: 4),
        throwsFormatException,
      );
    });
  });

  test('encrypted MSP round-trips and rejects wrong passwords', () async {
    final codec = MspCodec();
    final document = GeometryDocument(
      objects: [
        const GeometryObject(
          id: 'A',
          kind: 'point',
          points: [Point2(1.5, -2)],
          label: 'A',
        ),
      ],
    );
    final encoded = await codec.encode(document, password: 'test-password');
    expect(String.fromCharCodes(encoded.take(4)), 'MSP1');
    expect(codec.validate(encoded)['authenticated'], isFalse);
    final decoded = await codec.decode(encoded, password: 'test-password');
    expect(decoded.objects.single.points.single.x, 1.5);
    await expectLater(
      codec.decode(encoded, password: 'incorrect'),
      throwsA(isA<MspDecryptionException>()),
    );
  });
}
