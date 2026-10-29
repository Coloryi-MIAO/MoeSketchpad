// SPDX-License-Identifier: GPL-3.0-only
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:moesketchpad_core/moesketchpad_core.dart';

import 'animated_gif_exporter.dart';

class AnimatedApngExporter {
  const AnimatedApngExporter();

  static const _signature = [137, 80, 78, 71, 13, 10, 26, 10];

  Uint8List export({
    required GeometryDocument document,
    required AnimationSpec animation,
    required Bounds2 viewport,
    int width = 960,
    int height = 540,
    int frameCount = 36,
    int frameDurationMs = 80,
  }) {
    final frames = const AnimatedGifExporter().renderFrames(
      document: document,
      animation: animation,
      viewport: viewport,
      width: width,
      height: height,
      frameCount: frameCount,
      frameDurationMs: frameDurationMs,
    );
    final output = BytesBuilder(copy: false)..add(_signature);
    final firstPng = img.encodePng(frames.first);
    final chunks = _readPngChunks(firstPng);
    final header = chunks.firstWhere((chunk) => chunk.type == 'IHDR').data;
    output.add(_chunk('IHDR', header));
    output.add(
      _chunk('acTL', [
        ..._uint32(frames.length),
        ..._uint32(animation.loop ? 0 : 1),
      ]),
    );

    var sequence = 0;
    for (var index = 0; index < frames.length; index++) {
      final png = index == 0
          ? chunks
          : _readPngChunks(img.encodePng(frames[index]));
      final controls = <int>[
        ..._uint32(sequence++),
        ..._uint32(width),
        ..._uint32(height),
        ..._uint32(0),
        ..._uint32(0),
        ..._uint16(frameDurationMs),
        ..._uint16(1000),
        0,
        0,
      ];
      output.add(_chunk('fcTL', controls));
      final compressed = <int>[
        for (final chunk in png)
          if (chunk.type == 'IDAT') ...chunk.data,
      ];
      if (compressed.isEmpty) {
        throw const FormatException('PNG frame has no image data.');
      }
      if (index == 0) {
        output.add(_chunk('IDAT', compressed));
      } else {
        output.add(_chunk('fdAT', [..._uint32(sequence++), ...compressed]));
      }
    }
    output.add(_chunk('IEND', const []));
    return output.takeBytes();
  }

  List<_PngChunk> _readPngChunks(List<int> png) {
    if (png.length < _signature.length ||
        !_signature.every((byte) => png[_signature.indexOf(byte)] == byte)) {
      throw const FormatException('PNG encoder returned an invalid signature.');
    }
    final result = <_PngChunk>[];
    var offset = _signature.length;
    while (offset + 12 <= png.length) {
      final length =
          (png[offset] << 24) |
          (png[offset + 1] << 16) |
          (png[offset + 2] << 8) |
          png[offset + 3];
      final end = offset + 12 + length;
      if (length < 0 || end > png.length) {
        throw const FormatException('PNG encoder returned a truncated chunk.');
      }
      final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
      result.add(_PngChunk(type, png.sublist(offset + 8, offset + 8 + length)));
      offset = end;
      if (type == 'IEND') break;
    }
    if (result.isEmpty || result.last.type != 'IEND') {
      throw const FormatException('PNG encoder returned no IEND chunk.');
    }
    return result;
  }

  List<int> _chunk(String type, List<int> data) {
    final name = type.codeUnits;
    final body = [...name, ...data];
    return [..._uint32(data.length), ...body, ..._uint32(_crc32(body))];
  }

  List<int> _uint16(int value) => [(value >> 8) & 0xff, value & 0xff];

  List<int> _uint32(int value) => [
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];

  int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}

class _PngChunk {
  const _PngChunk(this.type, this.data);
  final String type;
  final List<int> data;
}
