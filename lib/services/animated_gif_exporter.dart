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
    final frames = renderFrames(
      document: document,
      animation: animation,
      viewport: viewport,
      width: width,
      height: height,
      frameCount: frameCount,
      frameDurationMs: frameDurationMs,
    );
    final encoder = img.GifEncoder(repeat: animation.loop ? 0 : -1);
    final frameMs = math.max(10, ((frameDurationMs + 5) ~/ 10) * 10);
    for (final image in frames) {
      encoder.addFrame(image, duration: frameMs ~/ 10);
    }
    final bytes = encoder.finish();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('GIF encoder returned no output.');
    }
    return bytes;
  }

  List<img.Image> renderFrames({
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
      throw ArgumentError(
        'Animation export dimensions or viewport are invalid.',
      );
    }
    if (!document.animations.any((item) => item.id == animation.id)) {
      throw ArgumentError.value(animation.id, 'animation', 'Not in document.');
    }

    final frames = <img.Image>[];
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
      frames.add(image);
    }
    return frames;
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
      case GeometryKind.conic:
        if (object.params['conicType'] == 'ellipse' &&
            object.points.isNotEmpty) {
          final center = object.points.first;
          final a = (object.params['a'] as num?)?.toDouble() ?? 0;
          final b = (object.params['b'] as num?)?.toDouble() ?? 0;
          final rotation =
              ((object.params['rotation'] as num?)?.toDouble() ?? 0) *
              math.pi /
              180;
          const samples = 128;
          var previous = Point2(
            center.x + a * math.cos(rotation),
            center.y + a * math.sin(rotation),
          );
          for (var index = 1; index <= samples; index++) {
            final angle = 2 * math.pi * index / samples;
            final localX = a * math.cos(angle);
            final localY = b * math.sin(angle);
            final current = Point2(
              center.x +
                  localX * math.cos(rotation) -
                  localY * math.sin(rotation),
              center.y +
                  localX * math.sin(rotation) +
                  localY * math.cos(rotation),
            );
            line(previous, current);
            previous = current;
          }
        }
      case GeometryKind.arc:
        final points = object.points;
        if (points.length >= 3) {
          final a = points[0];
          final b = points[1];
          final c = points[2];
          final determinant =
              2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
          if (determinant.abs() > 1e-12) {
            final aa = a.x * a.x + a.y * a.y;
            final bb = b.x * b.x + b.y * b.y;
            final cc = c.x * c.x + c.y * c.y;
            final center = Point2(
              (aa * (b.y - c.y) + bb * (c.y - a.y) + cc * (a.y - b.y)) /
                  determinant,
              (aa * (c.x - b.x) + bb * (a.x - c.x) + cc * (b.x - a.x)) /
                  determinant,
            );
            final radius = center.distanceTo(a);
            final start = math.atan2(a.y - center.y, a.x - center.x);
            final middle = math.atan2(b.y - center.y, b.x - center.x);
            var end = math.atan2(c.y - center.y, c.x - center.x);
            double ccwDistance(double from, double to) {
              var distance = to - from;
              if (distance < 0) distance += 2 * math.pi;
              return distance;
            }

            final ccwSpan = ccwDistance(start, end);
            final middleSpan = ccwDistance(start, middle);
            if (middleSpan > ccwSpan) end = end - 2 * math.pi;
            final span = end - start;
            const samples = 96;
            var previous = a;
            for (var index = 1; index <= samples; index++) {
              final angle = start + span * index / samples;
              final current = Point2(
                center.x + radius * math.cos(angle),
                center.y + radius * math.sin(angle),
              );
              line(previous, current);
              previous = current;
            }
          }
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
