// SPDX-License-Identifier: GPL-3.0-only
/// Minimal, dependency-free SVG export for printable pages.
library;

import 'dart:math' as math;

import 'geometry/object.dart';
import 'geometry/point.dart';
import 'functions.dart';
import 'measurement.dart';

class SvgExporter {
  String export(GeometryDocument document) {
    final page = document.view.page;
    final scale = document.view.unitScaleMm;
    final pageWidth = page.effectiveWidth / scale;
    final pageHeight = page.effectiveHeight / scale;
    final margin = math.max(pageWidth, pageHeight) * 0.04;
    final left = -pageWidth / 2 - margin;
    final top = -pageHeight / 2 - margin;
    final viewWidth = pageWidth + margin * 2;
    final viewHeight = pageHeight + margin * 2;
    final body = StringBuffer()..writeln('<g clip-path="url(#pageClip)">');
    final viewport = Bounds2(
      -pageWidth / 2,
      -pageHeight / 2,
      pageWidth / 2,
      pageHeight / 2,
    );
    final ordered = [...document.objects]..sort((a, b) => a.id.compareTo(b.id));
    for (final object in ordered) {
      if (!object.visible) continue;
      body.write(_objectSvg(object, document, viewport));
    }
    body.writeln('</g>');
    for (final measurement in document.measurements) {
      if (!measurement.visible) continue;
      final target = document.objectById(measurement.targetIds.first);
      if (target == null || target.points.isEmpty) continue;
      try {
        final value = const MeasurementEngine().measure(measurement, document);
        final anchor = target.points.first;
        body.writeln(
          '<text x="${_n(anchor.x + measurement.offsetX)}" '
          'y="${_n(anchor.y + measurement.offsetY)}" fill="#536878" '
          'font-family="Microsoft YaHei, PingFang SC, sans-serif" '
          'font-size="10">${_escape(value.display)}</text>',
        );
      } on FormatException {
        continue;
      }
    }
    return '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${_n(page.effectiveWidth)}mm" height="${_n(page.effectiveHeight)}mm" viewBox="${_n(left)} ${_n(top)} ${_n(viewWidth)} ${_n(viewHeight)}">
<defs><clipPath id="pageClip"><rect x="${_n(-pageWidth / 2)}" y="${_n(-pageHeight / 2)}" width="${_n(pageWidth)}" height="${_n(pageHeight)}"/></clipPath></defs>
<rect x="${_n(left)}" y="${_n(top)}" width="${_n(viewWidth)}" height="${_n(viewHeight)}" fill="#dfe3e8"/>
<rect x="${_n(-pageWidth / 2)}" y="${_n(-pageHeight / 2)}" width="${_n(pageWidth)}" height="${_n(pageHeight)}" fill="#ffffff" stroke="#c4cbd3"/>
$body</svg>
''';
  }

  String _objectSvg(
    GeometryObject object,
    GeometryDocument document,
    Bounds2 viewport,
  ) {
    final color = _color(object.style.strokeColor);
    final fill = object.style.fillColor == null
        ? 'none'
        : _color(object.style.fillColor!);
    final stroke =
        'stroke="$color" stroke-width="${_n(object.style.strokeWidth)}" '
        'fill="$fill" opacity="${_n(object.style.opacity)}"';
    final label = object.label;
    final buffer = StringBuffer();
    switch (object.kind) {
      case GeometryKind.point:
        final p = object.points.first;
        buffer
          ..writeln(
            '<circle cx="${_n(p.x)}" cy="${_n(p.y)}" r="4" fill="$color"/>',
          )
          ..write(_labelSvg(object, p, label));
      case GeometryKind.segment:
      case GeometryKind.vector:
        final a = object.points[0];
        final b = object.points[1];
        buffer.writeln(
          '<line x1="${_n(a.x)}" y1="${_n(a.y)}" x2="${_n(b.x)}" '
          'y2="${_n(b.y)}" $stroke/>',
        );
        if (object.kind == GeometryKind.vector) {
          final direction = (b - a).normalized();
          final normal = Point2(-direction.y, direction.x);
          final tipA = b - direction * 10 + normal * 4;
          final tipB = b - direction * 10 - normal * 4;
          buffer.writeln(
            '<polygon points="${_n(b.x)},${_n(b.y)} ${_n(tipA.x)},${_n(tipA.y)} '
            '${_n(tipB.x)},${_n(tipB.y)}" fill="$color"/>',
          );
        }
        buffer.write(_labelSvg(object, segmentMidpoint(a, b), label));
      case GeometryKind.line:
      case GeometryKind.ray:
        final a = object.points[0];
        final b = object.points[1];
        final direction = (b - a).normalized();
        final far = math.max(viewport.width, viewport.height) * 2;
        final from = object.kind == GeometryKind.ray ? a : a - direction * far;
        final to = a + direction * far;
        buffer.writeln(
          '<line x1="${_n(from.x)}" y1="${_n(from.y)}" x2="${_n(to.x)}" '
          'y2="${_n(to.y)}" $stroke/>',
        );
        buffer.write(_labelSvg(object, b, label));
      case GeometryKind.circle:
        final center = object.points[0];
        final radius = center.distanceTo(object.points[1]);
        buffer
          ..writeln(
            '<circle cx="${_n(center.x)}" cy="${_n(center.y)}" '
            'r="${_n(radius)}" $stroke/>',
          )
          ..write(_labelSvg(object, center + Point2(radius, 0), label));
      case GeometryKind.arc:
        final center = object.points[0];
        final radius = center.distanceTo(object.points[1]);
        final start = math.atan2(
          object.points[1].y - center.y,
          object.points[1].x - center.x,
        );
        final end = math.atan2(
          object.points[2].y - center.y,
          object.points[2].x - center.x,
        );
        var sweep = end - start;
        while (sweep < 0) {
          sweep += 2 * math.pi;
        }
        final startPoint =
            center + Point2(math.cos(start), math.sin(start)) * radius;
        final endPoint =
            center +
            Point2(math.cos(start + sweep), math.sin(start + sweep)) * radius;
        final large = sweep > math.pi ? 1 : 0;
        buffer.writeln(
          '<path d="M ${_n(startPoint.x)} ${_n(startPoint.y)} '
          'A ${_n(radius)} ${_n(radius)} 0 $large 1 ${_n(endPoint.x)} '
          '${_n(endPoint.y)}" fill="none" stroke="$color" '
          'stroke-width="${_n(object.style.strokeWidth)}"/>',
        );
        buffer.write(_labelSvg(object, endPoint, label));
      case GeometryKind.triangle:
      case GeometryKind.polygon:
        final points = object.points
            .map((point) => '${_n(point.x)},${_n(point.y)}')
            .join(' ');
        buffer.writeln('<polygon points="$points" $stroke/>');
        if (label != null && label.isNotEmpty) {
          buffer.write(_labelSvg(object, object.points.first, label));
        }
      case GeometryKind.conic:
        final center = object.points[0];
        final a = (object.params['a'] as num?)?.toDouble() ?? 2;
        final b = (object.params['b'] as num?)?.toDouble() ?? 1;
        final type = object.params['conicType'] as String? ?? 'ellipse';
        if (type == 'ellipse') {
          buffer.writeln(
            '<ellipse cx="${_n(center.x)}" cy="${_n(center.y)}" '
            'rx="${_n(a)}" ry="${_n(b)}" $stroke '
            'transform="rotate(${(object.params['rotation'] as num?) ?? 0} '
            '${_n(center.x)} ${_n(center.y)})"/>',
          );
        } else {
          buffer.writeln(
            '<text x="${_n(center.x)}" y="${_n(center.y)}" fill="#8a5a44" '
            'font-size="10">${_escape(type)} conic '
            '(parametric SVG export pending)</text>',
          );
        }
      case GeometryKind.function:
        try {
          final curve = FunctionCurve.fromObject(object);
          final lines = curve.sample(viewport, resolution: 256);
          for (final line in lines) {
            if (line.length < 2) continue;
            final pathData = StringBuffer(
              'M ${_n(line.first.x)} ${_n(line.first.y)}',
            );
            for (final point in line.skip(1)) {
              pathData.write(' L ${_n(point.x)} ${_n(point.y)}');
            }
            buffer.writeln(
              '<path d="$pathData" fill="none" stroke="$color" '
              'stroke-width="${_n(object.style.strokeWidth)}"/>',
            );
          }
        } on FormatException {
          // Invalid or missing expression: skip rather than emitting a false
          // curve.
        }
      case GeometryKind.coordinate:
        buffer
          ..writeln(
            '<line x1="${_n(viewport.left)}" y1="0" x2="${_n(viewport.right)}" '
            'y2="0" stroke="#8495a6" stroke-width="1"/>',
          )
          ..writeln(
            '<line x1="0" y1="${_n(viewport.top)}" x2="0" '
            'y2="${_n(viewport.bottom)}" stroke="#8495a6" stroke-width="1"/>',
          );
      case GeometryKind.solid:
        final edgeSpec = object.params['edges'] as String? ?? '';
        final edges = edgeSpec.isEmpty
            ? [
                for (var i = 0; i < object.points.length; i++)
                  (i, (i + 1) % object.points.length),
              ]
            : edgeSpec.split(',').map((edge) {
                final parts = edge.split('-');
                if (parts.length != 2) return (-1, -1);
                return (
                  int.tryParse(parts[0]) ?? -1,
                  int.tryParse(parts[1]) ?? -1,
                );
              });
        for (final edge in edges) {
          if (edge.$1 < 0 ||
              edge.$2 < 0 ||
              edge.$1 >= object.points.length ||
              edge.$2 >= object.points.length) {
            continue;
          }
          final a = object.points[edge.$1];
          final b = object.points[edge.$2];
          buffer.writeln(
            '<line x1="${_n(a.x)}" y1="${_n(a.y)}" x2="${_n(b.x)}" '
            'y2="${_n(b.y)}" stroke="$color" stroke-width="1.3" '
            'stroke-dasharray="3 2"/>',
          );
        }
    }
    return buffer.toString();
  }

  String _labelSvg(GeometryObject object, Point2 anchor, String? label) {
    if (label == null || label.isEmpty) return '';
    return '<text x="${_n(anchor.x + object.labelStyle.offsetX)}" '
        'y="${_n(anchor.y + object.labelStyle.offsetY)}" '
        'fill="${_color(object.labelStyle.color)}" '
        'font-family="Microsoft YaHei, PingFang SC, sans-serif" '
        'font-size="${_n(object.labelStyle.fontSize)}" '
        'font-style="${object.labelStyle.italic ? 'italic' : 'normal'}" '
        'font-weight="${object.labelStyle.bold ? 'bold' : 'normal'}">'
        '${_escape(label)}</text>';
  }

  static String _n(double value) {
    if (value.abs() < 1e-10) return '0';
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _color(int argb) =>
      '#${(argb & 0xffffff).toRadixString(16).padLeft(6, '0')}';

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
