// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:moesketchpad/services/animated_apng_exporter.dart';

void main() {
  test('exports valid APNG frame and animation control chunks', () {
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

    final bytes = const AnimatedApngExporter().export(
      document: document,
      animation: animation,
      viewport: const Bounds2(-5, -3, 5, 3),
      width: 64,
      height: 48,
      frameCount: 4,
      frameDurationMs: 100,
    );
    final chunks = _readChunks(bytes);
    final controls = chunks.where((chunk) => chunk == 'fcTL').length;
    final frameData = chunks.where((chunk) => chunk == 'fdAT').length;

    expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR');
    expect(controls, 4);
    expect(frameData, 3);
    expect(chunks.first, 'IHDR');
    expect(chunks.last, 'IEND');
    final firstFrame = img.decodePng(bytes);
    expect(firstFrame, isNotNull);
    expect(firstFrame!.width, 64);
    expect(firstFrame.height, 48);
  });

  test('rejects invalid APNG limits before rendering', () {
    final animation = AnimationSpec(
      id: 'move',
      targetId: 'P',
      pathObjectId: 'path',
      pathKind: 'segment',
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
          points: const [Point2(0, 0), Point2(1, 0)],
        ),
      ],
      animations: [animation],
    );
    expect(
      () => const AnimatedApngExporter().export(
        document: document,
        animation: animation,
        viewport: const Bounds2(0, 0, 10, 10),
        frameCount: 121,
      ),
      throwsArgumentError,
    );
  });
}

List<String> _readChunks(List<int> bytes) {
  final chunks = <String>[];
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final size =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    chunks.add(String.fromCharCodes(bytes.sublist(offset + 4, offset + 8)));
    offset += 12 + size;
  }
  return chunks;
}
