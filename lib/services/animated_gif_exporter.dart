// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:moesketchpad_core/moesketchpad_core.dart';

class AnimatedGifExporter {
  const AnimatedGifExporter();

  Uint8List export({
    required GeometryDocument document,
    required AnimationSpec animation,
    required Bounds2 viewport,
    int width = 960,
    int height = 540,
    int frameCount = 36,
    int frameDurationMs = 80,
  }) {
    if (width < 16 ||
        height < 16 ||
        width > 2048 ||
        height > 2048 ||
        frameCount < 2 ||
        frameCount > 120 ||
        width * height * frameCount > 32 * 1024 * 1024 ||
        frameDurationMs < 20 ||
        frameDurationMs > 2000 ||
        !viewport.left.isFinite ||
        !viewport.right.isFinite ||
        !viewport.top.isFinite ||
        !viewport.bottom.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      throw ArgumentError('GIF export dimensions or viewport are invalid.');
    }
    if (!document.animations.any((item) => item.id == animation.id)) {
      throw ArgumentError.value(animation.id, 'animation', 'Not in document.');
    }

    final encoder = img.GifEncoder(repeat: animation.loop ? 0 : -1);
    final frameMs = math.max(10, ((frameDurationMs + 5) ~/ 10) * 10);
    for (var frame = 0; frame < frameCount; frame++) {
      final elapsed = frame * frameDurationMs / 1000;
      final animated = const AnimationEvaluator().targetAt(
        document,
        animation,
        elapsed,
      );
      final objects = [
        for (final object in document.objects)
          object.id == animated.id ? animated : object,
      ];
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      for (final object in objects) {
        if (!object.visible) continue;
        _drawObject(image, object, viewport);
      }
      encoder.addFrame(image, duration: frameMs ~/ 10);
    }
    final bytes = encoder.finish();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('GIF encoder returned no output.');
    }
    return bytes;
  }

  void _drawObject(img.Image image, GeometryObject object, Bounds2 viewport) {
    final colorValue = object.style.strokeColor;
    final alpha = ((colorValue >> 24) & 0xff) * object.style.opacity;
    final color = img.ColorRgba8(
      (colorValue >> 16) & 0xff,
      (colorValue >> 8) & 0xff,
      colorValue & 0xff,
      alpha.round().clamp(0, 255),
    );
    final thickness = math.max(1, object.style.strokeWidth.round());

    void line(Point2 first, Point2 second) {
      final a = _pixel(first, viewport, image.width, image.height);
      final b = _pixel(second, viewport, image.width, image.height);
      img.drawLine(
        image,
        x1: a.x,
        y1: a.y,
        x2: b.x,
        y2: b.y,
        color: color,
        thickness: thickness,
      );
    }

    switch (object.kind) {
      case GeometryKind.point:
      case GeometryKind.vector:
        if (object.points.isNotEmpty) {
          final point = _pixel(
            object.points.first,
            viewport,
            image.width,
            image.height,
          );
          img.drawCircle(
            image,
            x: point.x,
            y: point.y,
            radius: math.max(2, thickness + 1),
            color: color,
          );
          if (object.kind == GeometryKind.vector && object.points.length > 1) {
            line(object.points.first, object.points[1]);
          }
        }
      case GeometryKind.circle:
        if (object.points.length > 1) {
          final center = object.points.first;
          final radius = center.distanceTo(object.points[1]);
          final centerPx = _pixel(center, viewport, image.width, image.height);
          final radiusPx = (radius / viewport.width * image.width).round();
          img.drawCircle(
            image,
            x: centerPx.x,
            y: centerPx.y,
            radius: radiusPx,
            color: color,
          );
        }
      case GeometryKind.function:
        try {
          for (final segment in FunctionCurve.fromObject(
            object,
          ).sample(viewport, resolution: math.min(image.width, 1024))) {
            for (var i = 1; i < segment.length; i++) {
              line(segment[i - 1], segment[i]);
            }
          }
        } on FormatException {
          return;
        }
      case GeometryKind.segment:
      case GeometryKind.line:
      case GeometryKind.ray:
        if (object.points.length > 1) {
          var first = object.points.first;
          var second = object.points[1];
          if (object.kind != GeometryKind.segment) {
            final direction = second - first;
            if (direction.length > 0) {
              final scale = math.max(viewport.width, viewport.height) * 2;
              first = first - direction * (scale / direction.length);
              second = second + direction * (scale / direction.length);
            }
          }
          line(first, second);
        }
      case GeometryKind.triangle:
      case GeometryKind.polygon:
      case GeometryKind.arc:
      case GeometryKind.conic:
      case GeometryKind.coordinate:
      case GeometryKind.solid:
        if (object.points.length > 1) {
          for (var i = 1; i < object.points.length; i++) {
            line(object.points[i - 1], object.points[i]);
          }
          if (object.kind == GeometryKind.triangle ||
              object.kind == GeometryKind.polygon) {
            line(object.points.last, object.points.first);
          }
        }
    }
  }

  ({int x, int y}) _pixel(
    Point2 point,
    Bounds2 bounds,
    int width,
    int height,
  ) => (
    x: ((point.x - bounds.left) / bounds.width * width).round(),
    y: ((bounds.bottom - point.y) / bounds.height * height).round(),
  );
}
