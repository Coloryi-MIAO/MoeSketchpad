// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

import '../../bloc/canvas_bloc.dart';
import '../../bloc/measure_bloc.dart';

const Color _professionalBlue = Color(0xff2d6fa7);
const Color _cutePink = Color(0xffd77c9c);

class CanvasBackgroundPainter extends CustomPainter {
  CanvasBackgroundPainter({required this.canvasState, required this.cute});

  final CanvasState canvasState;
  final bool cute;

  @override
  void paint(Canvas canvas, Size size) {
    final state = canvasState;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = cute ? const Color(0xffeef1f6) : const Color(0xffd9dde2),
    );
    if (state.showGrid) _paintGrid(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final spacing = canvasState.gridSpacing * canvasState.zoom;
    if (spacing < 5 || !spacing.isFinite) return;
    final origin = canvasState.worldToScreen(canvasState.origin);
    final paint = Paint()
      ..color = (cute ? const Color(0x146d7d99) : const Color(0x26707b88))
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = (cute ? const Color(0x226d7d99) : const Color(0x3d707b88))
      ..strokeWidth = 0.8;
    final firstX = ((0 - origin.dx) / spacing).floor();
    final lastX = ((size.width - origin.dx) / spacing).ceil();
    for (var i = firstX; i <= lastX; i++) {
      final x = origin.dx + i * spacing;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i % 5 == 0 ? major : paint,
      );
    }
    final firstY = ((0 - origin.dy) / spacing).floor();
    final lastY = ((size.height - origin.dy) / spacing).ceil();
    for (var i = firstY; i <= lastY; i++) {
      final y = origin.dy + i * spacing;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i % 5 == 0 ? major : paint,
      );
    }
  }

  @override
  bool shouldRepaint(CanvasBackgroundPainter oldDelegate) =>
      oldDelegate.canvasState != canvasState || oldDelegate.cute != cute;
}

class GeometryPainter extends CustomPainter {
  GeometryPainter({
    required this.canvasState,
    required this.document,
    required this.spatialIndex,
    required this.measurements,
    required this.cute,
    required this.theme,
  });

  final CanvasState canvasState;
  final GeometryDocument document;
  final SpatialIndex spatialIndex;
  final List<MeasurementView> measurements;
  final bool cute;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final viewport = canvasState.visibleBounds;
    final objects = spatialIndex.query(viewport);
    for (final object in objects) {
      _paintObject(canvas, object, viewport, size);
    }
    if (canvasState.zoom >= 0.004) {
      for (final view in measurements) {
        _paintMeasurement(canvas, view);
      }
    }
    canvas.restore();
  }

  void _paintObject(
    Canvas canvas,
    GeometryObject object,
    Bounds2 viewport,
    Size size,
  ) {
    final color = Color(object.style.strokeColor);
    final paint = Paint()
      ..color = color.withValues(alpha: object.style.opacity.clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, object.style.strokeWidth)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color =
          (object.style.fillColor == null
                  ? color.withValues(alpha: 0.1)
                  : Color(object.style.fillColor!))
              .withValues(alpha: object.style.opacity.clamp(0, 1))
      ..style = PaintingStyle.fill;
    switch (object.kind) {
      case GeometryKind.point:
        if (object.params['hideMarker'] != true) {
          _paintPoint(canvas, object.points.first, color);
        }
      case GeometryKind.segment:
      case GeometryKind.vector:
        final a = canvasState.worldToScreen(object.points[0]);
        final b = canvasState.worldToScreen(object.points[1]);
        canvas.drawLine(a, b, paint);
        if (object.kind == GeometryKind.vector) {
          _paintArrow(canvas, a, b, color);
        }
      case GeometryKind.line:
        final points = _clipInfiniteLine(
          object.points[0],
          object.points[1],
          viewport,
        );
        if (points != null) {
          canvas.drawLine(
            canvasState.worldToScreen(points.$1),
            canvasState.worldToScreen(points.$2),
            paint,
          );
        }
      case GeometryKind.ray:
        final points = _clipRay(object.points[0], object.points[1], viewport);
        if (points != null) {
          canvas.drawLine(
            canvasState.worldToScreen(points.$1),
            canvasState.worldToScreen(points.$2),
            paint,
          );
        }
      case GeometryKind.circle:
        final center = canvasState.worldToScreen(object.points[0]);
        final rim = canvasState.worldToScreen(object.points[1]);
        final radius = (rim - center).distance;
        if (object.style.fillColor != null) {
          canvas.drawCircle(center, radius, fill);
        }
        canvas.drawCircle(center, radius, paint);
      case GeometryKind.arc:
        final center = object.points[0];
        final rim = object.points[1];
        final radiusWorld = center.distanceTo(rim);
        final start = math.atan2(rim.y - center.y, rim.x - center.x);
        final end = math.atan2(
          object.points[2].y - center.y,
          object.points[2].x - center.x,
        );
        var sweep = end - start;
        while (sweep < 0) {
          sweep += 2 * math.pi;
        }
        final centerScreen = canvasState.worldToScreen(center);
        final rect = Rect.fromCircle(
          center: centerScreen,
          radius: radiusWorld * canvasState.zoom,
        );
        canvas.drawArc(rect, start, sweep, false, paint);
      case GeometryKind.triangle:
      case GeometryKind.polygon:
        final path = Path();
        for (var i = 0; i < object.points.length; i++) {
          final point = canvasState.worldToScreen(object.points[i]);
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        if (object.style.fillColor != null) canvas.drawPath(path, fill);
        canvas.drawPath(path, paint);
      case GeometryKind.conic:
        _paintConic(canvas, object, paint, viewport);
      case GeometryKind.function:
        _paintFunction(canvas, object, paint, viewport);
      case GeometryKind.coordinate:
        _paintAxes(canvas, size);
      case GeometryKind.solid:
        _paintSolid(canvas, object, paint);
    }
    if (canvasState.zoom >= 0.08) {
      _paintLabel(canvas, object);
    }
  }

  void _paintPoint(Canvas canvas, Point2 point, Color color) {
    final screen = canvasState.worldToScreen(point);
    if (!screen.dx.isFinite || !screen.dy.isFinite) return;
    canvas.drawCircle(screen, 4.2, Paint()..color = color);
    canvas.drawCircle(
      screen,
      4.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 1.2,
    );
  }

  void _paintArrow(Canvas canvas, Offset a, Offset b, Color color) {
    final direction = b - a;
    if (direction.distance < 1) return;
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final tip = b;
    final back = b - unit * 12;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + normal.dx * 5, back.dy + normal.dy * 5)
      ..lineTo(back.dx - normal.dx * 5, back.dy - normal.dy * 5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintConic(
    Canvas canvas,
    GeometryObject object,
    Paint paint,
    Bounds2 viewport,
  ) {
    final center = object.points[0];
    final a = (object.params['a'] as num?)?.toDouble() ?? 2;
    final b = (object.params['b'] as num?)?.toDouble() ?? 1;
    final rotation =
        ((object.params['rotation'] as num?)?.toDouble() ?? 0) * math.pi / 180;
    final type = object.params['conicType'] as String? ?? 'ellipse';
    if (type == 'ellipse') {
      final centerScreen = canvasState.worldToScreen(center);
      canvas.save();
      canvas.translate(centerScreen.dx, centerScreen.dy);
      canvas.rotate(rotation);
      final oval = Rect.fromCenter(
        center: Offset.zero,
        width: a * 2 * canvasState.zoom,
        height: b * 2 * canvasState.zoom,
      );
      if (object.style.fillColor != null) {
        canvas.drawOval(
          oval,
          Paint()
            ..color = Color(
              object.style.fillColor!,
            ).withValues(alpha: object.style.opacity.clamp(0, 1))
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawOval(oval, paint);
      canvas.restore();
      return;
    }
    // Hyperbola/parabola: draw a sampled conic instead of a misleading box.
    final points = <Offset>[];
    final samples = 400;
    for (var i = 0; i <= samples; i++) {
      final t = -math.pi + 2 * math.pi * i / samples;
      double x;
      double y;
      if (type == 'hyperbola') {
        final cosh = (math.exp(t) + math.exp(-t)) / 2;
        final sinh = (math.exp(t) - math.exp(-t)) / 2;
        x = a * cosh;
        y = b * sinh;
      } else {
        x = a * t * t * 0.1;
        y = b * t;
      }
      final rotated = Point2(
        center.x + x * math.cos(rotation) - y * math.sin(rotation),
        center.y + x * math.sin(rotation) + y * math.cos(rotation),
      );
      if (rotated.isFinite()) points.add(canvasState.worldToScreen(rotated));
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintFunction(
    Canvas canvas,
    GeometryObject object,
    Paint paint,
    Bounds2 viewport,
  ) {
    if (canvasState.zoom < 0.002) return;
    try {
      final curve = FunctionCurve.fromObject(object);
      final lines = curve.sample(
        viewport,
        resolution: canvasState.zoom < 0.1 ? 160 : 480,
      );
      for (final line in lines) {
        if (line.length < 2) continue;
        final path = Path();
        for (var i = 0; i < line.length; i++) {
          final screen = canvasState.worldToScreen(line[i]);
          if (!screen.dx.isFinite || !screen.dy.isFinite) continue;
          if (i == 0) {
            path.moveTo(screen.dx, screen.dy);
          } else {
            path.lineTo(screen.dx, screen.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    } on FormatException {
      // Never draw a curve when its expression cannot be evaluated safely.
    }
  }

  void _paintAxes(Canvas canvas, Size size) {
    final origin = canvasState.worldToScreen(canvasState.origin);
    final paint = Paint()
      ..color = const Color(0x99627a90)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, origin.dy), Offset(size.width, origin.dy), paint);
    canvas.drawLine(
      Offset(origin.dx, 0),
      Offset(origin.dx, size.height),
      paint,
    );
    _drawText(
      canvas,
      'x',
      Offset(size.width - 14, origin.dy - 18),
      const TextStyle(
        fontSize: 12,
        color: Color(0xff627a90),
        fontStyle: FontStyle.italic,
      ),
    );
    _drawText(
      canvas,
      'y',
      Offset(origin.dx + 8, 4),
      const TextStyle(
        fontSize: 12,
        color: Color(0xff627a90),
        fontStyle: FontStyle.italic,
      ),
    );
  }

  void _paintSolid(Canvas canvas, GeometryObject object, Paint paint) {
    final edges = <(int, int)>[];
    final spec = object.params['edges'];
    if (spec is String && spec.isNotEmpty) {
      for (final edge in spec.split(',')) {
        final parts = edge.split('-');
        if (parts.length == 2) {
          final a = int.tryParse(parts[0]);
          final b = int.tryParse(parts[1]);
          if (a != null &&
              b != null &&
              a >= 0 &&
              b >= 0 &&
              a < object.points.length &&
              b < object.points.length) {
            edges.add((a, b));
          }
        }
      }
    } else {
      for (var i = 0; i < object.points.length; i++) {
        edges.add((i, (i + 1) % object.points.length));
      }
    }
    for (final edge in edges) {
      canvas.drawLine(
        canvasState.worldToScreen(object.points[edge.$1]),
        canvasState.worldToScreen(object.points[edge.$2]),
        paint,
      );
    }
  }

  void _paintLabel(Canvas canvas, GeometryObject object) {
    final label = object.label;
    if (label == null || label.isEmpty) return;
    if (object.points.isEmpty) return;
    final anchor = canvasState.worldToScreen(object.points.first);
    final style = TextStyle(
      color: Color(object.labelStyle.color),
      fontSize: object.labelStyle.fontSize,
      fontStyle: object.labelStyle.italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: object.labelStyle.bold ? FontWeight.w700 : FontWeight.w400,
    );
    _drawText(
      canvas,
      label,
      anchor + Offset(object.labelStyle.offsetX, object.labelStyle.offsetY),
      style,
    );
  }

  void _paintMeasurement(Canvas canvas, MeasurementView view) {
    if (!view.measurement.visible) return;
    final measurement = view.measurement;
    final target = document.objectById(measurement.targetIds.first);
    if (target == null || target.points.isEmpty) return;
    final anchor = canvasState.worldToScreen(target.points.first);
    final text = view.value?.display ?? '—';
    _drawText(
      canvas,
      text,
      anchor + Offset(measurement.offsetX, measurement.offsetY),
      TextStyle(
        color: cute ? const Color(0xff9b5c75) : const Color(0xff536878),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      background: Colors.white.withValues(alpha: 0.78),
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    Color? background,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (background != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            offset.dx - 2,
            offset.dy - 1,
            painter.width + 4,
            painter.height + 2,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = background,
      );
    }
    painter.paint(canvas, offset);
  }

  (Point2, Point2)? _clipInfiniteLine(Point2 a, Point2 b, Bounds2 viewport) {
    final direction = b - a;
    if (direction.length <= 1e-12) return null;
    final candidates = <Point2>[];
    final bounds = [
      (viewport.left, true),
      (viewport.right, true),
      (viewport.top, false),
      (viewport.bottom, false),
    ];
    for (final bound in bounds) {
      if (direction.x.abs() > 1e-12 && bound.$2) {
        final t = (bound.$1 - a.x) / direction.x;
        final y = a.y + direction.y * t;
        if (y >= viewport.top - 1e-9 && y <= viewport.bottom + 1e-9) {
          candidates.add(Point2(bound.$1, y));
        }
      }
      if (direction.y.abs() > 1e-12 && !bound.$2) {
        final t = (bound.$1 - a.y) / direction.y;
        final x = a.x + direction.x * t;
        if (x >= viewport.left - 1e-9 && x <= viewport.right + 1e-9) {
          candidates.add(Point2(x, bound.$1));
        }
      }
    }
    if (candidates.length < 2) return null;
    candidates.sort(
      (p, q) => p.x == q.x ? p.y.compareTo(q.y) : p.x.compareTo(q.x),
    );
    return (candidates.first, candidates.last);
  }

  (Point2, Point2)? _clipRay(Point2 a, Point2 b, Bounds2 viewport) {
    final direction = b - a;
    if (direction.length <= 1e-12) return null;
    final far = a + direction.normalized() * 1e7;
    final candidates = <Point2>[a];
    final bounds = [
      (viewport.left, true),
      (viewport.right, true),
      (viewport.top, false),
      (viewport.bottom, false),
    ];
    for (final bound in bounds) {
      if (direction.x.abs() > 1e-12 && bound.$2) {
        final t = (bound.$1 - a.x) / direction.x;
        if (t >= 0) {
          final y = a.y + direction.y * t;
          if (y >= viewport.top - 1e-9 && y <= viewport.bottom + 1e-9) {
            candidates.add(Point2(bound.$1, y));
          }
        }
      }
      if (direction.y.abs() > 1e-12 && !bound.$2) {
        final t = (bound.$1 - a.y) / direction.y;
        if (t >= 0) {
          final x = a.x + direction.x * t;
          if (x >= viewport.left - 1e-9 && x <= viewport.right + 1e-9) {
            candidates.add(Point2(x, bound.$1));
          }
        }
      }
    }
    candidates.sort((p, q) => p.distanceTo(a).compareTo(q.distanceTo(a)));
    if (candidates.length < 2) return (a, far);
    return (candidates.first, candidates.last);
  }

  @override
  bool shouldRepaint(GeometryPainter oldDelegate) =>
      oldDelegate.canvasState != canvasState ||
      !identical(oldDelegate.document, document) ||
      oldDelegate.measurements != measurements ||
      oldDelegate.cute != cute;
}

class CanvasOverlayPainter extends CustomPainter {
  CanvasOverlayPainter({
    required this.canvasState,
    required this.selectedIds,
    required this.document,
    required this.draftPoints,
    required this.cute,
    required this.rubberBand,
    required this.shapePreview,
    required this.shapePreviewEllipse,
    required this.animationSample,
    required this.animatedTargetId,
    required this.showOrigin,
    this.transformObjectId,
    this.transformHandle,
    this.transformMode = 'none',
  });

  final CanvasState canvasState;
  final Set<String> selectedIds;
  final GeometryDocument document;
  final List<Point2> draftPoints;
  final bool cute;
  final Rect? rubberBand;
  final Rect? shapePreview;
  final bool shapePreviewEllipse;
  final AnimationSample? animationSample;
  final String? animatedTargetId;
  final bool showOrigin;
  final String? transformObjectId;
  final String? transformHandle;
  final String transformMode;

  Color get _accent => cute ? _cutePink : _professionalBlue;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final id in selectedIds) {
      final object = document.objectById(id);
      if (object == null) continue;
      final paint = Paint()
        ..color = _accent.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      for (final point in object.points) {
        final screen = canvasState.worldToScreen(point);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: screen, width: 9, height: 9),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
    }
    // Draw transform bounds and handles around a single selectable object.
    if (transformObjectId != null && transformMode != 'none') {
      final transformObject = document.objectById(transformObjectId!);
      if (transformObject != null && transformObject.bounds != null) {
        final bounds = transformObject.bounds!;
        final tl = canvasState.worldToScreen(Point2(bounds.left, bounds.top));
        final br = canvasState.worldToScreen(
          Point2(bounds.right, bounds.bottom),
        );
        final boundsRect = Rect.fromPoints(tl, br);
        final handlePaint = Paint()
          ..color = _accent.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill;
        final borderPaint = Paint()
          ..color = _accent.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(boundsRect, borderPaint);
        final centerX = (tl.dx + br.dx) / 2;
        final centerY = (tl.dy + br.dy) / 2;
        const handleSize = 7.0;
        final handles = <String, Offset>{
          'nw': tl,
          'n': Offset(centerX, tl.dy),
          'ne': Offset(br.dx, tl.dy),
          'w': Offset(tl.dx, centerY),
          'e': Offset(br.dx, centerY),
          'sw': Offset(tl.dx, br.dy),
          's': Offset(centerX, br.dy),
          'se': br,
        };
        for (final entry in handles.entries) {
          final isActive = transformHandle == entry.key;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: entry.value,
                width: handleSize + (isActive ? 4 : 0),
                height: handleSize + (isActive ? 4 : 0),
              ),
              const Radius.circular(2),
            ),
            handlePaint..color = _accent.withValues(alpha: isActive ? 1 : 0.85),
          );
        }
        // Rotation handle above the top-middle.
        final rotate = Offset(centerX, tl.dy - 20);
        final isRotateActive = transformHandle == 'rotate';
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: rotate,
              width: handleSize + (isRotateActive ? 4 : 0),
              height: handleSize + (isRotateActive ? 4 : 0),
            ),
            const Radius.circular(2),
          ),
          handlePaint
            ..color = _accent.withValues(alpha: isRotateActive ? 1 : 0.85),
        );
      }
    }
    for (final guide in canvasState.guides) {
      final paint = Paint()
        ..color = const Color(0xff58a4d8)
        ..strokeWidth = 0.9
        ..style = PaintingStyle.stroke;
      if (guide.vertical) {
        final x = canvasState.worldToScreen(Point2(guide.position, 0)).dx;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      } else {
        final y = canvasState.worldToScreen(Point2(0, guide.position)).dy;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
    if (draftPoints.isNotEmpty) {
      final paint = Paint()
        ..color = _accent.withValues(alpha: 0.8)
        ..strokeWidth = 1.3
        ..style = PaintingStyle.stroke;
      final points = [
        for (final point in draftPoints) canvasState.worldToScreen(point),
      ];
      for (var i = 0; i + 1 < points.length; i++) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
      for (final point in points) {
        canvas.drawCircle(point, 3.5, Paint()..color = _accent);
      }
    }
    if (rubberBand != null) {
      canvas.drawRect(
        rubberBand!,
        Paint()
          ..color = _accent.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rubberBand!,
        Paint()
          ..color = _accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if (shapePreview != null) {
      final paint = Paint()
        ..color = _accent
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      if (shapePreviewEllipse) {
        canvas.drawOval(shapePreview!, paint);
      } else {
        canvas.drawRect(shapePreview!, paint);
      }
    }
    if (animationSample != null && animatedTargetId != null) {
      if (animationSample!.trail.isNotEmpty) {
        final trailPaint = Paint()
          ..color = _accent.withValues(alpha: 0.42)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        final path = Path();
        for (var i = 0; i < animationSample!.trail.length; i++) {
          final screen = canvasState.worldToScreen(animationSample!.trail[i]);
          if (i == 0) {
            path.moveTo(screen.dx, screen.dy);
          } else {
            path.lineTo(screen.dx, screen.dy);
          }
        }
        canvas.drawPath(path, trailPaint);
      }
      final position = animationSample!.position;
      if (position != null) {
        final screen = canvasState.worldToScreen(position);
        canvas.drawCircle(
          screen,
          7,
          Paint()..color = _accent.withValues(alpha: 0.24),
        );
        canvas.drawCircle(screen, 4.5, Paint()..color = _accent);
      }
    }
    if (showOrigin) {
      final origin = canvasState.worldToScreen(canvasState.origin);
      final paint = Paint()
        ..color = const Color(0xffd9685e)
        ..strokeWidth = 1;
      canvas.drawLine(
        origin - const Offset(7, 0),
        origin + const Offset(7, 0),
        paint,
      );
      canvas.drawLine(
        origin - const Offset(0, 7),
        origin + const Offset(0, 7),
        paint,
      );
      canvas.drawCircle(
        origin,
        3.5,
        Paint()
          ..color = const Color(0xffd9685e)
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CanvasOverlayPainter oldDelegate) => true;
}

Future<void> drawTextOnCanvas(
  Canvas canvas,
  String text,
  Offset offset,
  TextStyle style,
) async {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  painter.paint(canvas, offset);
}
