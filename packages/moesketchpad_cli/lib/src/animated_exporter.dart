// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:moesketchpad_core/moesketchpad_core.dart';

class CliAnimatedExporter {
  const CliAnimatedExporter();

  Uint8List exportGif({
    required GeometryDocument document,
    required AnimationSpec animation,
    required Bounds2 viewport,
    int width = 640,
    int height = 360,
    int frameCount = 24,
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
        viewport.width <= 0 ||
        viewport.height <= 0 ||
        !viewport.left.isFinite ||
        !viewport.right.isFinite ||
        !viewport.top.isFinite ||
        !viewport.bottom.isFinite) {
      throw ArgumentError('GIF export dimensions or viewport are invalid.');
    }
    if (!document.animations.any((item) => item.id == animation.id)) {
      throw ArgumentError.value(animation.id, 'animation', 'Not in document.');
    }

    final encoder = img.GifEncoder(repeat: animation.loop ? 0 : -1);
    final frameDelay = math.max(2, ((frameDurationMs + 5) ~/ 10));
    for (var frame = 0; frame < frameCount; frame++) {
      final current = const AnimationEvaluator().targetAt(
        document,
        animation,
        frame * frameDurationMs / 1000,
      );
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      for (final object in document.objects) {
        if (object.visible)
          _draw(image, object.id == current.id ? current : object, viewport);
      }
      encoder.addFrame(image, duration: frameDelay);
    }
    final result = encoder.finish();
    if (result == null || result.isEmpty) {
      throw StateError('GIF encoder returned no output.');
    }
    return Uint8List.fromList(result);
  }

  void _draw(img.Image image, GeometryObject object, Bounds2 viewport) {
    final colorValue = object.style.strokeColor;
    final color = img.ColorRgba8(
      colorValue >> 16 & 0xff,
      colorValue >> 8 & 0xff,
      colorValue & 0xff,
      ((colorValue >> 24 & 0xff) * object.style.opacity).round().clamp(0, 255),
    );
    final thickness = math.max(1, object.style.strokeWidth.round());

    (int, int) pixel(Point2 point) => (
      ((point.x - viewport.left) / viewport.width * image.width).round(),
      ((viewport.bottom - point.y) / viewport.height * image.height).round(),
    );

    void line(Point2 first, Point2 second) {
      final a = pixel(first);
      final b = pixel(second);
      img.drawLine(
        image,
        x1: a.$1,
        y1: a.$2,
        x2: b.$1,
        y2: b.$2,
        color: color,
        thickness: thickness,
      );
    }

    void drawEllipse(Point2 center, double a, double b, double rotation) {
      var previous = Point2(
        center.x + a * math.cos(rotation),
        center.y + a * math.sin(rotation),
      );
      for (var i = 1; i <= 96; i++) {
        final angle = 2 * math.pi * i / 96;
        final x = a * math.cos(angle);
        final y = b * math.sin(angle);
        final current = Point2(
          center.x + x * math.cos(rotation) - y * math.sin(rotation),
          center.y + x * math.sin(rotation) + y * math.cos(rotation),
        );
        line(previous, current);
        previous = current;
      }
    }

    void drawArc(List<Point2> points) {
      if (points.length < 3) return;
      final a = points[0];
      final b = points[1];
      final c = points[2];
      final determinant =
          2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
      if (determinant.abs() <= 1e-12) {
        line(a, b);
        line(b, c);
        return;
      }
      final aa = a.x * a.x + a.y * a.y;
      final bb = b.x * b.x + b.y * b.y;
      final cc = c.x * c.x + c.y * c.y;
      final center = Point2(
        (aa * (b.y - c.y) + bb * (c.y - a.y) + cc * (a.y - b.y)) / determinant,
        (aa * (c.x - b.x) + bb * (a.x - c.x) + cc * (b.x - a.x)) / determinant,
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

      if (ccwDistance(start, middle) > ccwDistance(start, end)) {
        end -= 2 * math.pi;
      }
      final span = end - start;
      var previous = a;
      for (var i = 1; i <= 72; i++) {
        final angle = start + span * i / 72;
        final current = Point2(
          center.x + radius * math.cos(angle),
          center.y + radius * math.sin(angle),
        );
        line(previous, current);
        previous = current;
      }
    }

    switch (object.kind) {
      case GeometryKind.point:
      case GeometryKind.vector:
        if (object.points.isNotEmpty) {
          final p = pixel(object.points.first);
          img.drawCircle(
            image,
            x: p.$1,
            y: p.$2,
            radius: math.max(2, thickness + 1),
            color: color,
          );
          if (object.kind == GeometryKind.vector && object.points.length > 1) {
            line(object.points.first, object.points[1]);
          }
        }
      case GeometryKind.segment:
      case GeometryKind.line:
      case GeometryKind.ray:
        if (object.points.length > 1) {
          var a = object.points[0];
          var b = object.points[1];
          if (object.kind != GeometryKind.segment) {
            final direction = b - a;
            if (direction.length > 0) {
              final scale = math.max(viewport.width, viewport.height) * 2;
              a = a - direction * (scale / direction.length);
              b = b + direction * (scale / direction.length);
            }
          }
          line(a, b);
        }
      case GeometryKind.circle:
        if (object.points.length > 1) {
          final center = object.points.first;
          final radius = object.points.first.distanceTo(object.points[1]);
          drawEllipse(center, radius, radius, 0);
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
      case GeometryKind.arc:
        drawArc(object.points);
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
          drawEllipse(center, a, b, rotation);
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
    }
  }
}
