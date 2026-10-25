// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:moesketchpad/services/animated_gif_exporter.dart';

void main() {
  test('exports animated document frames as a valid GIF', () {
    final animation = AnimationSpec(
      id: 'move',
      targetId: 'P',
      pathObjectId: 'path',
      pathKind: 'segment',
      loop: true,
    );
    final document = GeometryDocument(
      objects: [
        GeometryObject(
          id: 'P',
          kind: GeometryKind.point,
          points: const [Point2(0, 0)],
        ),
        GeometryObject(
          id: 'path',
          kind: GeometryKind.segment,
          points: const [Point2(-4, 0), Point2(4, 0)],
        ),
      ],
      animations: [animation],
    );

    final bytes = const AnimatedGifExporter().export(
      document: document,
      animation: animation,
      viewport: const Bounds2(-5, -3, 5, 3),
      width: 160,
      height: 96,
      frameCount: 4,
    );

    final decoded = img.decodeGif(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 160);
    expect(decoded.height, 96);
    expect(decoded.numFrames, 4);
  });
}
