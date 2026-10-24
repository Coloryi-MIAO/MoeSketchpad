// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:test/test.dart';

void main() {
  test('view geometry settings roundtrip and validate', () {
    const view = ViewState(
      gridBaseSpacing: 10,
      snapTolerancePx: 14,
      geometryTolerance: GeometryTolerance(relative: 1e-6, absolute: 1e-6),
      unit: 'cm',
    );
    final decoded = ViewState.fromJson(view.toJson());
    expect(decoded.gridBaseSpacing, 10);
    expect(decoded.snapTolerancePx, 14);
    expect(decoded.geometryTolerance.relative, 1e-6);
    expect(decoded.geometryTolerance.absolute, 1e-6);
    expect(decoded.unit, 'cm');
    expect(
      () => ViewState.fromJson({...view.toJson(), 'snapTolerancePx': 100}),
      throwsFormatException,
    );
  });

  group('expression', () {
    const evaluator = ExpressionEvaluator();
    test('evaluates safely and respects variables', () {
      expect(evaluator.evaluate('sqrt(3^2+4^2)'), 5);
      expect(evaluator.evaluate('2^3^2'), 512);
      expect(evaluator.evaluate('x+1', variables: {'x': 2}), 3);
    });
    test('rejects code and domain errors', () {
      expect(
        () => evaluator.evaluate('1/0'),
        throwsA(isA<EvaluationException>()),
      );
      expect(() => evaluator.evaluate('print(1)'), throwsFormatException);
      expect(
        () => evaluator.evaluate('sqrt(-1)'),
        throwsA(isA<EvaluationException>()),
      );
    });
    test('enforces source length, parser depth and finite results', () {
      expect(
        () => const ExpressionEvaluator(maxLength: 4).evaluate('1+2+3'),
        throwsFormatException,
      );
      expect(
        () => evaluator.evaluate('${'(' * 70}1${')' * 70}'),
        throwsFormatException,
      );
      expect(
        () => evaluator.evaluate('1e308*1e308'),
        throwsA(isA<EvaluationException>()),
      );
    });
  });

  group('predicates', () {
    test('handles crossing, parallel and degenerate intersections', () {
      final crossing = intersectLines(
        const Point2(0, 0),
        const Point2(2, 2),
        const Point2(0, 2),
        const Point2(2, 0),
      );
      expect(crossing.kind, IntersectionKind.one);
      final parallel = intersectLines(
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(0, 1),
        const Point2(1, 1),
      );
      expect(parallel.kind, IntersectionKind.none);
      final coincident = intersectLines(
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(2, 0),
        const Point2(3, 0),
      );
      expect(coincident.kind, IntersectionKind.degenerate);
    });

    test('computes circle intersections and polygon containment', () {
      final result = intersectCircles(
        const Point2(0, 0),
        2,
        const Point2(3, 0),
        2,
      );
      expect(result.points.length, 2);
      expect(
        pointInPolygon(const Point2(0.5, 0.5), const [
          Point2(0, 0),
          Point2(1, 0),
          Point2(1, 1),
          Point2(0, 1),
        ]),
        isTrue,
      );
    });

    test(
      'handles tangency, coincident circles, degenerate lines and scale',
      () {
        final tangent = intersectLineCircle(
          const Point2(-2, 1),
          const Point2(2, 1),
          const Point2(0, 0),
          1,
        );
        expect(tangent.kind, IntersectionKind.one);
        final coincident = intersectCircles(
          const Point2(0, 0),
          2,
          const Point2(1e-12, 0),
          2,
        );
        expect(coincident.kind, IntersectionKind.degenerate);
        expect(
          intersectLines(
            const Point2(1, 1),
            const Point2(1, 1),
            const Point2(0, 0),
            const Point2(2, 2),
          ).kind,
          IntersectionKind.degenerate,
        );
        final largeScale = intersectLines(
          const Point2(0, 0),
          const Point2(1e120, 1e120),
          const Point2(0, 1e120),
          const Point2(1e120, 0),
        );
        expect(largeScale.kind, IntersectionKind.one);
        expect(largeScale.points.single.x, closeTo(5e119, 1e108));
      },
    );
  });

  group('spatial index', () {
    test('matches brute-force queries and deletes 10000 entries', () {
      final random = math.Random(42);
      final objects = [
        for (var i = 0; i < 10000; i++)
          GeometryObject(
            id: 'p$i',
            kind: GeometryKind.point,
            points: [
              Point2(random.nextDouble() * 1000, random.nextDouble() * 1000),
            ],
          ),
      ];
      final index = SpatialIndex(objects);
      const viewport = Bounds2(200, 250, 450, 600);
      final expected = objects
          .where((object) => object.bounds!.intersects(viewport))
          .map((object) => object.id)
          .toSet();
      expect(
        index.query(viewport).map((object) => object.id).toSet(),
        expected,
      );
      for (var i = 0; i < 10000; i += 2) {
        index.remove('p$i');
      }
      final expectedAfterRemoval = objects
          .where((object) {
            final index = int.parse(object.id.substring(1));
            return index.isOdd && object.bounds!.intersects(viewport);
          })
          .map((object) => object.id)
          .toSet();
      expect(
        index.query(viewport).map((object) => object.id).toSet(),
        expectedAfterRemoval,
      );
      expect(index.length, 5000);
    });
  });

  group('triangle shorthand', () {
    test('solves valid and rejects invalid right triangles', () {
      final solution = parseTriangleShorthand('--triangle-90-3*4*5-5/180');
      expect(solution.sides, [3, 4, 5]);
      expect(solution.vertices.length, 3);
      expect(
        () => parseTriangleShorthand('--triangle-90-2*3*4-4/0'),
        throwsA(isA<TriangleSolveException>()),
      );
    });
  });

  test('codec roundtrip and tamper detection', () async {
    final codec = MspCodec();
    final document = GeometryDocument(
      objects: const [
        GeometryObject(
          id: 'A',
          kind: GeometryKind.point,
          points: [Point2(1, 2)],
          label: 'A',
        ),
      ],
      view: const ViewState(
        gridBaseSpacing: 10,
        snapTolerancePx: 14,
        geometryTolerance: GeometryTolerance(relative: 1e-6, absolute: 1e-6),
        unit: 'cm',
      ),
    );
    final bytes = await codec.encode(document, password: 'secret');
    final header = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 12)), 'MOESKETCHPAD');
    expect(header.getUint16(12, Endian.big), 2);
    expect(header.getUint16(14, Endian.big) & 1, 1);
    expect(header.getUint8(26), 16);
    expect(header.getUint8(43), 12);
    expect(bytes.length, 72 + header.getUint64(64, Endian.big) + 16);
    expect(codec.validate(bytes).compressed, isTrue);
    final decoded = await codec.decode(bytes, password: 'secret');
    expect(decoded.objects.single.label, 'A');
    expect(decoded.view.gridBaseSpacing, 10);
    expect(decoded.view.snapTolerancePx, 14);
    expect(decoded.view.geometryTolerance.relative, 1e-6);
    expect(decoded.view.unit, 'cm');
    await expectLater(
      codec.decode(bytes, password: 'wrong'),
      throwsA(isA<MspDecryptionException>()),
    );
    final changedAad = Uint8List.fromList(bytes)..[27] ^= 1;
    await expectLater(
      codec.decode(changedAad, password: 'secret'),
      throwsA(isA<MspDecryptionException>()),
    );
    expect(
      () => codec.validate(bytes.sublist(0, bytes.length - 1)),
      throwsA(isA<MspFormatException>()),
    );
    final badNonceLength = Uint8List.fromList(bytes)..[43] = 11;
    expect(
      () => codec.validate(badNonceLength),
      throwsA(isA<MspFormatException>()),
    );
    final oversizedPlaintext = Uint8List.fromList(bytes);
    ByteData.sublistView(
      oversizedPlaintext,
    ).setUint64(56, 64 * 1024 * 1024, Endian.big);
    expect(
      () => codec.validate(oversizedPlaintext),
      throwsA(isA<MspFormatException>()),
    );
    final unsafeJavascriptLength = Uint8List.fromList(bytes)..[56] = 0x20;
    expect(
      () => codec.validate(unsafeJavascriptLength),
      throwsA(isA<MspFormatException>()),
    );
  });

  test('codec enforces decompressed payload limit before inflation', () async {
    final document = GeometryDocument(
      objects: const [],
      metadata: {'padding': List.filled(100000, 'x').join()},
    );
    final encoded = await MspCodec(
      maxPayloadBytes: 200000,
    ).encode(document, password: 'secret');
    expect(
      () => MspCodec(maxPayloadBytes: 1024).validate(encoded),
      throwsA(isA<MspFormatException>()),
    );
  });

  test('JSON migration roundtrips schema v2 documents', () {
    final codec = MspCodec();
    final document = GeometryDocument(objects: const []);
    final json = codec.exportJson(document);
    expect(codec.importJson(json).toJson(), document.toJson());
    expect(codec.migrate(document.toJson()).objects, isEmpty);
  });

  test('SVG exporter escapes document labels', () {
    final document = GeometryDocument(
      objects: const [
        GeometryObject(
          id: 'A',
          kind: GeometryKind.point,
          points: [Point2(0, 0)],
          label: '<script>&',
        ),
      ],
    );
    final svg = SvgExporter().export(document);
    expect(svg, contains('&lt;script&gt;&amp;'));
    expect(svg, isNot(contains('<script>')));
  });

  test('measurements support units and geometry', () {
    final document = GeometryDocument(
      objects: const [
        GeometryObject(
          id: 's',
          kind: GeometryKind.segment,
          points: [Point2(0, 0), Point2(96, 0)],
        ),
      ],
    );
    final value = const MeasurementEngine().measure(
      const Measurement(
        id: 'm',
        type: MeasurementType.length,
        targetIds: ['s'],
        unit: MeasureUnit.mm,
      ),
      document,
    );
    expect(value.display, endsWith('mm'));
    expect(value.rawValue, 96);
  });
}
