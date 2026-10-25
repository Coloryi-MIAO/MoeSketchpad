// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

import '../../bloc/animation_bloc.dart';
import '../../bloc/canvas_bloc.dart';
import '../../bloc/document_bloc.dart';
import '../../bloc/measure_bloc.dart';
import '../../bloc/selection_bloc.dart';
import '../../bloc/theme_bloc.dart';
import '../../bloc/tool_bloc.dart';
import '../../l10n/app_localizations.dart';
import 'canvas_painters.dart';
import 'geometry_construction.dart';

class SketchpadCanvas extends StatefulWidget {
  const SketchpadCanvas({super.key});

  @override
  SketchpadCanvasState createState() => SketchpadCanvasState();
}

class SketchpadCanvasState extends State<SketchpadCanvas> {
  final GlobalKey _canvasKey = GlobalKey();
  final FocusNode _focusNode = FocusNode(debugLabel: 'canvas');
  final List<Point2> _draftPoints = <Point2>[];
  final List<Point2> _freehandPoints = <Point2>[];
  Offset? _freehandScreen;
  Offset? _rubberStart;
  Offset? _rubberCurrent;
  Offset? _shapeDragStart;
  Offset? _shapeDragCurrent;
  GeometryDocument? _dragBefore;
  GeometryDocument? _dragDocument;
  Map<int, Point2>? _dragOriginalPoints;
  String? _dragObjectId;
  Point2? _lastSnap;
  SpatialIndex? _index;
  GeometryDocument? _indexedDocument;

  Bounds2? get viewportWorldBounds {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final canvas = context.read<CanvasBloc>().state;
    final first = canvas.screenToWorld(Offset.zero);
    final second = canvas.screenToWorld(
      Offset(box.size.width, box.size.height),
    );
    return Bounds2(
      math.min(first.x, second.x),
      math.min(first.y, second.y),
      math.max(first.x, second.x),
      math.max(first.y, second.y),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  SpatialIndex _spatialIndex(GeometryDocument document) {
    if (!identical(_indexedDocument, document) || _index == null) {
      _indexedDocument = document;
      _index = SpatialIndex(document.objects);
    }
    return _index!;
  }

  Point2 _snap(Point2 raw, GeometryDocument document, SpatialIndex index) {
    final canvas = context.read<CanvasBloc>().state;
    final tolerance = canvas.snapTolerancePx / canvas.zoom;
    var best = raw;
    var bestDistance = double.infinity;
    void consider(Point2 candidate) {
      final distance = candidate.distanceTo(raw);
      if (distance < bestDistance && distance <= tolerance) {
        bestDistance = distance;
        best = candidate;
      }
    }

    final objects = index.query(
      Bounds2(
        raw.x - tolerance,
        raw.y - tolerance,
        raw.x + tolerance,
        raw.y + tolerance,
      ),
    );
    if (canvas.snapObjects) {
      for (final object in objects) {
        if (!object.visible) continue;
        for (final point in object.points) {
          consider(point);
        }
        if (object.points.length == 2) {
          consider(segmentMidpoint(object.points[0], object.points[1]));
        }
        switch (object.kind) {
          case GeometryKind.segment:
          case GeometryKind.vector:
            consider(
              _projectToSegment(raw, object.points[0], object.points[1]),
            );
          case GeometryKind.line:
            consider(_projectToLine(raw, object.points[0], object.points[1]));
          case GeometryKind.circle:
            final center = object.points[0];
            final radius = center.distanceTo(object.points[1]);
            if (radius > 1e-12) {
              final direction = raw - center;
              consider(center + direction.normalized() * radius);
            }
          default:
            break;
        }
      }
      final tolerancePolicy = context
          .read<CanvasBloc>()
          .state
          .geometryTolerance;
      for (var firstIndex = 0; firstIndex < objects.length; firstIndex++) {
        final first = objects[firstIndex];
        for (
          var secondIndex = firstIndex + 1;
          secondIndex < objects.length;
          secondIndex++
        ) {
          final second = objects[secondIndex];
          final intersections = switch ((first.kind, second.kind)) {
            (GeometryKind.segment, GeometryKind.segment) => intersectLines(
              first.points[0],
              first.points[1],
              second.points[0],
              second.points[1],
              segments: true,
              tolerance: tolerancePolicy,
            ),
            (GeometryKind.segment, GeometryKind.circle) => intersectLineCircle(
              first.points[0],
              first.points[1],
              second.points[0],
              second.points[0].distanceTo(second.points[1]),
              segment: true,
              tolerance: tolerancePolicy,
            ),
            (GeometryKind.circle, GeometryKind.segment) => intersectLineCircle(
              second.points[0],
              second.points[1],
              first.points[0],
              first.points[0].distanceTo(first.points[1]),
              segment: true,
              tolerance: tolerancePolicy,
            ),
            _ => const IntersectionResult.none(),
          };
          for (final point in intersections.points) {
            consider(point);
          }
        }
      }
    }
    for (final guide in canvas.guides) {
      if (guide.vertical) {
        consider(Point2(guide.position, raw.y));
      } else {
        consider(Point2(raw.x, guide.position));
      }
    }
    if (canvas.snapGrid && canvas.gridSpacing > 0) {
      final spacing = canvas.gridSpacing;
      final candidate = Point2(
        ((raw.x - canvas.origin.x) / spacing).round() * spacing +
            canvas.origin.x,
        ((raw.y - canvas.origin.y) / spacing).round() * spacing +
            canvas.origin.y,
      );
      consider(candidate);
    }
    _lastSnap = best == raw ? null : best;
    return best;
  }

  Point2 _projectToSegment(Point2 point, Point2 a, Point2 b) {
    final ab = b - a;
    final length = ab.dot(ab);
    if (length <= 1e-15) return a;
    final t = ((point - a).dot(ab) / length).clamp(0.0, 1.0);
    return a + ab * t;
  }

  Point2 _projectToLine(Point2 point, Point2 a, Point2 b) {
    final ab = b - a;
    final length = ab.dot(ab);
    if (length <= 1e-15) return a;
    final t = (point - a).dot(ab) / length;
    return a + ab * t;
  }

  void _handleTapUp(TapUpDetails details) {
    _focusNode.requestFocus();
    final tool = context.read<ToolBloc>().state.active;
    final canvas = context.read<CanvasBloc>().state;
    final world = canvas.screenToWorld(details.localPosition);
    final document = context.read<DocumentBloc>().state.active.document;
    final snapped = _snap(world, document, _spatialIndex(document));
    switch (tool) {
      case MoeTool.select:
        final hit = _spatialIndex(document).hitTest(
          world,
          tolerance: canvas.snapTolerancePx / canvas.zoom,
          filter: (object) => object.visible && !object.locked,
        );
        final selection = context.read<SelectionBloc>();
        if (hit == null) {
          selection.clear();
        } else if (HardwareKeyboard.instance.isShiftPressed) {
          selection.toggle(hit.id);
        } else {
          selection.replace(hit.id);
        }
      case MoeTool.point:
        _addObject(
          GeometryObject(
            id: 'point-${DateTime.now().microsecondsSinceEpoch}',
            kind: GeometryKind.point,
            points: [snapped],
            label: autoLabel(_pointCount(document)),
          ),
        );
      case MoeTool.segment:
      case MoeTool.line:
      case MoeTool.ray:
      case MoeTool.vector:
        _draftPoints.add(snapped);
        if (_draftPoints.length == 2) {
          if (_isDegeneratePair(_draftPoints[0], _draftPoints[1], canvas)) {
            _draftPoints.clear();
            _showDegenerateGeometry();
            setState(() {});
            return;
          }
          final kind = switch (tool) {
            MoeTool.segment => GeometryKind.segment,
            MoeTool.line => GeometryKind.line,
            MoeTool.ray => GeometryKind.ray,
            MoeTool.vector => GeometryKind.vector,
            _ => throw StateError('Unexpected two-point construction tool.'),
          };
          _addObject(
            GeometryConstruction.twoPoint(
              id: '${kind.name}-${DateTime.now().microsecondsSinceEpoch}',
              kind: kind,
              first: _draftPoints[0],
              second: _draftPoints[1],
            ),
          );
          _draftPoints.clear();
        }
        setState(() {});
      case MoeTool.arc:
        _draftPoints.add(snapped);
        if (_draftPoints.length == 3) {
          final tolerance = canvas.geometryTolerance.forScale(
            _draftPoints[0].length,
          );
          try {
            _addObject(
              GeometryConstruction.arc(
                id: 'arc-${DateTime.now().microsecondsSinceEpoch}',
                center: _draftPoints[0],
                start: _draftPoints[1],
                endDirection: _draftPoints[2],
                tolerance: tolerance,
              ),
            );
          } on FormatException {
            _draftPoints.clear();
            _showDegenerateGeometry();
            setState(() {});
            return;
          }
          _draftPoints.clear();
        }
        setState(() {});
      case MoeTool.circle:
        _draftPoints.add(snapped);
        if (_draftPoints.length == 2) {
          if (_isDegeneratePair(_draftPoints[0], _draftPoints[1], canvas)) {
            _draftPoints.clear();
            _showDegenerateGeometry();
            setState(() {});
            return;
          }
          _addObject(
            GeometryObject(
              id: 'circle-${DateTime.now().microsecondsSinceEpoch}',
              kind: GeometryKind.circle,
              points: List.of(_draftPoints),
            ),
          );
          _draftPoints.clear();
        }
        setState(() {});
      case MoeTool.triangle:
        _draftPoints.add(snapped);
        if (_draftPoints.length == 3) {
          _addObject(
            GeometryObject(
              id: 'triangle-${DateTime.now().microsecondsSinceEpoch}',
              kind: GeometryKind.triangle,
              points: List.of(_draftPoints),
              params: const {'triangleType': 'free'},
            ),
          );
          _draftPoints.clear();
        }
        setState(() {});
      case MoeTool.polygon:
        if (_draftPoints.length >= 3 &&
            details.localPosition.dx.isFinite &&
            _screenDistance(snapped, _draftPoints.first, canvas) < 12) {
          _finishPolygon();
          return;
        }
        _draftPoints.add(snapped);
        setState(() {});
      case MoeTool.function:
        _showFunctionDialog(snapped);
      case MoeTool.pan:
        break;
      case MoeTool.zoom:
        context.read<CanvasBloc>().zoomAt(details.localPosition, 1.35);
      case MoeTool.rectangle:
      case MoeTool.ellipse:
        // Rectangle and ellipse tools use press-drag-release like CDR.
        break;
      case MoeTool.text:
        _showTextDialog(snapped);
      case MoeTool.freehand:
        break;
      case MoeTool.fill:
        _applyFill(world);
      case MoeTool.transparency:
        _editOpacity(world);
      case MoeTool.eyedropper:
        _sampleStroke(world);
      case MoeTool.outline:
        _editOutline(world);
    }
  }

  double _screenDistance(Point2 a, Point2 b, CanvasState canvas) =>
      (canvas.worldToScreen(a) - canvas.worldToScreen(b)).distance;

  bool _isDegeneratePair(Point2 a, Point2 b, CanvasState canvas) {
    final scale = math.max(a.length, b.length);
    return a.distanceTo(b) <= canvas.geometryTolerance.forScale(scale);
  }

  void _showDegenerateGeometry() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).geometryDegenerate)),
    );
  }

  List<GeometryObject> _styleTargets(GeometryDocument document, Point2 world) {
    final selection = context.read<SelectionBloc>().state.ids;
    if (selection.isNotEmpty) {
      return [for (final id in selection) ?document.objectById(id)];
    }
    final hit = _spatialIndex(document).hitTest(
      world,
      tolerance:
          context.read<CanvasBloc>().state.snapTolerancePx /
          context.read<CanvasBloc>().state.zoom,
      filter: (object) => object.visible && !object.locked,
    );
    if (hit == null) return const [];
    context.read<SelectionBloc>().replace(hit.id);
    return [hit];
  }

  void _updateStyles(
    List<GeometryObject> targets,
    ObjectStyle Function(ObjectStyle style) update,
  ) {
    if (targets.isEmpty) return;
    var document = context.read<DocumentBloc>().state.active.document;
    for (final object in targets) {
      document = document.withObject(
        object.copyWith(style: update(object.style)),
      );
    }
    context.read<DocumentBloc>().commitDocument(document);
  }

  Future<void> _applyFill(Point2 world) async {
    final document = context.read<DocumentBloc>().state.active.document;
    final targets = _styleTargets(document, world);
    if (targets.isEmpty) return;
    const colors = <int>[
      0xffdcecf8,
      0xffffe1ed,
      0xffffefc2,
      0xffdff2df,
      0xffe9e0fa,
      0xffffffff,
    ];
    final selectedColor = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).toolFill),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in colors)
              InkWell(
                key: ValueKey('fill-color-$color'),
                onTap: () => Navigator.of(dialogContext).pop(color),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(color),
                    border: Border.all(color: const Color(0xff536878)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
        ],
      ),
    );
    if (!mounted || selectedColor == null) return;
    _updateStyles(targets, (style) => style.copyWith(fillColor: selectedColor));
  }

  Future<void> _editOpacity(Point2 world) async {
    final document = context.read<DocumentBloc>().state.active.document;
    final targets = _styleTargets(document, world);
    if (targets.isEmpty) return;
    var opacity = targets.first.style.opacity;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).toolTransparency),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                key: const ValueKey('tool-opacity-slider'),
                value: opacity,
                onChanged: (value) => setDialogState(() => opacity = value),
              ),
              Text('${(opacity * 100).round()}%'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(opacity),
              child: Text(AppLocalizations.of(context).save),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    _updateStyles(targets, (style) => style.copyWith(opacity: result));
  }

  void _sampleStroke(Point2 world) {
    final document = context.read<DocumentBloc>().state.active.document;
    final hit = _spatialIndex(document).hitTest(
      world,
      tolerance:
          context.read<CanvasBloc>().state.snapTolerancePx /
          context.read<CanvasBloc>().state.zoom,
      filter: (object) => object.visible,
    );
    if (hit == null) return;
    final targets = _styleTargets(document, world);
    if (targets.length == 1 && targets.first.id == hit.id) return;
    _updateStyles(
      targets,
      (style) => style.copyWith(strokeColor: hit.style.strokeColor),
    );
  }

  Future<void> _editOutline(Point2 world) async {
    final document = context.read<DocumentBloc>().state.active.document;
    final targets = _styleTargets(document, world);
    if (targets.isEmpty) return;
    var width = targets.first.style.strokeWidth.clamp(0.5, 12.0);
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).toolOutline),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                key: const ValueKey('tool-outline-slider'),
                min: 0.5,
                max: 12,
                value: width,
                onChanged: (value) => setDialogState(() => width = value),
              ),
              Text('${width.toStringAsFixed(1)} px'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(width),
              child: Text(AppLocalizations.of(context).save),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    _updateStyles(targets, (style) => style.copyWith(strokeWidth: result));
  }

  Future<void> _showTextDialog(Point2 at) async {
    final documentBloc = context.read<DocumentBloc>();
    final selection = context.read<SelectionBloc>().state;
    final selected = selection.primary == null
        ? null
        : documentBloc.state.active.document.objectById(selection.primary!);
    final controller = TextEditingController(text: selected?.label ?? '');
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocalizations.of(context).toolText),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 512,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'A',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(AppLocalizations.of(context).save),
            ),
          ],
        ),
      );
      if (!mounted || value == null || value.trim().isEmpty) return;
      if (selected != null) {
        documentBloc.setLabel(selected.id, value.trim());
      } else {
        documentBloc.addObject(
          GeometryObject(
            id: 'text-${DateTime.now().microsecondsSinceEpoch}',
            kind: GeometryKind.point,
            points: [at],
            label: value.trim(),
            labelStyle: const LabelStyle(italic: false, fontSize: 18),
            style: const ObjectStyle(strokeColor: 0xff203548),
            params: const {'hideMarker': true},
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  int _pointCount(GeometryDocument document) => document.objects
      .where((object) => object.kind == GeometryKind.point)
      .length;

  void _addObject(GeometryObject object) {
    context.read<DocumentBloc>().addObject(object);
    _lastSnap = null;
  }

  void _finishPolygon() {
    if (_draftPoints.length < 3) return;
    _addObject(
      GeometryObject(
        id: 'polygon-${DateTime.now().microsecondsSinceEpoch}',
        kind: GeometryKind.polygon,
        points: List.of(_draftPoints),
      ),
    );
    setState(_draftPoints.clear);
  }

  void _handlePanStart(DragStartDetails details) {
    _focusNode.requestFocus();
    final tool = context.read<ToolBloc>().state.active;
    final canvas = context.read<CanvasBloc>().state;
    final document = context.read<DocumentBloc>().state.active.document;
    if (tool == MoeTool.freehand) {
      _freehandPoints
        ..clear()
        ..add(canvas.screenToWorld(details.localPosition));
      _freehandScreen = details.localPosition;
      setState(() {});
      return;
    }
    if (tool == MoeTool.rectangle || tool == MoeTool.ellipse) {
      _shapeDragStart = details.localPosition;
      _shapeDragCurrent = details.localPosition;
      setState(() {});
      return;
    }
    if (tool == MoeTool.pan ||
        tool == MoeTool.select &&
            HardwareKeyboard.instance.logicalKeysPressed.contains(
              LogicalKeyboardKey.space,
            )) {
      _dragBefore = null;
      return;
    }
    if (tool != MoeTool.select) return;
    final world = canvas.screenToWorld(details.localPosition);
    final hit = _spatialIndex(document).hitTest(
      world,
      tolerance: 10 / canvas.zoom,
      filter: (object) => object.visible && !object.locked,
    );
    if (hit != null) {
      context.read<SelectionBloc>().replace(hit.id);
      _dragObjectId = hit.id;
      _dragBefore = document;
      _dragDocument = document;
      _dragOriginalPoints = {
        for (var i = 0; i < hit.points.length; i++) i: hit.points[i],
      };
      _dragStartWorld = world;
    } else {
      _rubberStart = details.localPosition;
      _rubberCurrent = details.localPosition;
      setState(() {});
    }
  }

  Point2 _dragStartWorld = Point2.zero;

  void _handlePanUpdate(DragUpdateDetails details) {
    final tool = context.read<ToolBloc>().state.active;
    final canvas = context.read<CanvasBloc>().state;
    if (tool == MoeTool.freehand && _freehandPoints.isNotEmpty) {
      final point = canvas.screenToWorld(details.localPosition);
      if (_freehandScreen == null ||
          (details.localPosition - _freehandScreen!).distance >= 2) {
        if (_freehandPoints.length < 512) _freehandPoints.add(point);
        _freehandScreen = details.localPosition;
        setState(() {});
      }
      return;
    }
    if (_shapeDragStart != null) {
      setState(() {
        final current = details.localPosition;
        if (HardwareKeyboard.instance.isShiftPressed) {
          final delta = current - _shapeDragStart!;
          final side = math.max(delta.dx.abs(), delta.dy.abs());
          _shapeDragCurrent =
              _shapeDragStart! +
              Offset(delta.dx < 0 ? -side : side, delta.dy < 0 ? -side : side);
        } else {
          _shapeDragCurrent = current;
        }
      });
      return;
    }
    if (tool == MoeTool.pan ||
        (tool == MoeTool.select &&
            HardwareKeyboard.instance.logicalKeysPressed.contains(
              LogicalKeyboardKey.space,
            ))) {
      context.read<CanvasBloc>().panBy(details.delta);
      return;
    }
    if (_dragObjectId != null && _dragDocument != null) {
      final object = _dragDocument!.objectById(_dragObjectId!);
      if (object == null) return;
      final world = canvas.screenToWorld(details.localPosition);
      final delta = world - _dragStartWorld;
      final moved = <Point2>[];
      final originals = _dragOriginalPoints!;
      for (var i = 0; i < object.points.length; i++) {
        moved.add((originals[i] ?? object.points[i]) + delta);
      }
      setState(() {
        _dragDocument = _dragDocument!.withObject(
          object.copyWith(points: moved),
        );
      });
      return;
    }
    if (_rubberStart != null) {
      setState(() => _rubberCurrent = details.localPosition);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_shapeDragStart != null && _shapeDragCurrent != null) {
      _finishShapeDrag();
    }
    if (_freehandPoints.length > 1) {
      final document = context.read<DocumentBloc>().state.active.document;
      final now = DateTime.now().microsecondsSinceEpoch;
      var updated = document;
      for (var i = 1; i < _freehandPoints.length; i++) {
        updated = updated.withObject(
          GeometryObject(
            id: 'freehand-$now-$i',
            kind: GeometryKind.segment,
            points: [_freehandPoints[i - 1], _freehandPoints[i]],
            params: const {'freehand': true},
            style: const ObjectStyle(strokeColor: 0xff263b4f, strokeWidth: 2),
          ),
        );
      }
      context.read<DocumentBloc>().commitDocument(updated);
    }
    _freehandPoints.clear();
    _freehandScreen = null;
    if (_dragObjectId != null && _dragBefore != null && _dragDocument != null) {
      context.read<DocumentBloc>().commitDrag(_dragBefore!, _dragDocument!);
      _clearDrag();
      return;
    }
    if (_rubberStart != null && _rubberCurrent != null) {
      final canvas = context.read<CanvasBloc>().state;
      final a = canvas.screenToWorld(_rubberStart!);
      final b = canvas.screenToWorld(_rubberCurrent!);
      final selection = Bounds2(
        math.min(a.x, b.x),
        math.min(a.y, b.y),
        math.max(a.x, b.x),
        math.max(a.y, b.y),
      );
      final document = context.read<DocumentBloc>().state.active.document;
      final ids = _spatialIndex(document)
          .query(selection)
          .where((object) => object.visible && !object.locked)
          .map((object) => object.id);
      context.read<SelectionBloc>().replaceAll(ids);
      setState(() {
        _rubberStart = null;
        _rubberCurrent = null;
      });
    }
    _clearDrag();
  }

  void _finishShapeDrag() {
    final start = _shapeDragStart!;
    final current = _shapeDragCurrent!;
    _shapeDragStart = null;
    _shapeDragCurrent = null;
    final tool = context.read<ToolBloc>().state.active;
    final canvas = context.read<CanvasBloc>().state;
    final document = context.read<DocumentBloc>().state.active.document;
    final index = _spatialIndex(document);
    final first = _snap(canvas.screenToWorld(start), document, index);
    final second = _snap(canvas.screenToWorld(current), document, index);
    if (_isDegeneratePair(first, second, canvas)) {
      _showDegenerateGeometry();
      setState(() {});
      return;
    }
    final left = math.min(first.x, second.x);
    final right = math.max(first.x, second.x);
    final top = math.min(first.y, second.y);
    final bottom = math.max(first.y, second.y);
    final id = '${tool.name}-${DateTime.now().microsecondsSinceEpoch}';
    if (tool == MoeTool.rectangle) {
      _addObject(
        GeometryObject(
          id: id,
          kind: GeometryKind.polygon,
          points: [
            Point2(left, top),
            Point2(right, top),
            Point2(right, bottom),
            Point2(left, bottom),
          ],
          params: const {'shape': 'rectangle'},
        ),
      );
    } else {
      _addObject(
        GeometryObject(
          id: id,
          kind: GeometryKind.conic,
          points: [
            Point2((left + right) / 2, (top + bottom) / 2),
            Point2(left, top),
            Point2(right, bottom),
          ],
          params: {
            'conicType': 'ellipse',
            'a': (right - left) / 2,
            'b': (bottom - top) / 2,
            'rotation': 0,
          },
        ),
      );
    }
    setState(() {});
  }

  void _clearDrag() {
    _dragBefore = null;
    _dragDocument = null;
    _dragOriginalPoints = null;
    _dragObjectId = null;
    setState(() {});
  }

  void _showFunctionDialog(Point2 at) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _FunctionDialog(
        onCreated: (params, label) {
          _addObject(
            GeometryObject(
              id: 'function-${DateTime.now().microsecondsSinceEpoch}',
              kind: GeometryKind.function,
              points: const [],
              label: label,
              params: params,
            ),
          );
        },
      ),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final selection = context.read<SelectionBloc>().state.ids;
      if (selection.isNotEmpty) {
        context.read<DocumentBloc>().deleteObjects(selection);
        context.read<SelectionBloc>().clear();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(_draftPoints.clear);
      context.read<SelectionBloc>().clear();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _finishPolygon();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        HardwareKeyboard.instance.isControlPressed) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        context.read<DocumentBloc>().redo();
      } else {
        context.read<DocumentBloc>().undo();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cute = context.select((ThemeBloc bloc) => bloc.state.cute);
    context.watch<ToolBloc>();
    return BlocListener<ToolBloc, ToolState>(
      listenWhen: (previous, current) => previous.active != current.active,
      listener: (context, state) {
        if (_draftPoints.isNotEmpty) setState(_draftPoints.clear);
      },
      child: BlocBuilder<CanvasBloc, CanvasState>(
        builder: (context, canvasState) {
          return BlocBuilder<DocumentBloc, DocumentState>(
            builder: (context, documentState) {
              final document = _dragDocument ?? documentState.active.document;
              final index = _spatialIndex(document);
              final selection = context.watch<SelectionBloc>().state.ids;
              final selectedSegment = selection.length == 1
                  ? document.objectById(selection.single)
                  : null;
              String? segmentLength;
              if (selectedSegment?.kind == GeometryKind.segment) {
                final measurement = Measurement(
                  id: '_selection-length',
                  type: MeasurementType.length,
                  targetIds: [selectedSegment!.id],
                  unit: MeasureUnit.parse(canvasState.unit),
                );
                try {
                  segmentLength = const MeasurementEngine()
                      .measure(measurement, document)
                      .display;
                } on FormatException {
                  segmentLength = null;
                }
              }
              final measureState = context.watch<MeasureBloc>().state;
              final animationState = context.watch<AnimationBloc>().state;
              final animation = _activeAnimation(document, animationState);
              final sample = animation == null
                  ? null
                  : const AnimationEvaluator().sample(
                      document,
                      animation,
                      animationState.elapsedSeconds,
                    );
              return Column(
                children: [
                  SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        _RulerCorner(
                          canvasState: canvasState,
                          onReset: context.read<CanvasBloc>().resetOrigin,
                          onDrag: (delta) {
                            context.read<CanvasBloc>().setOrigin(
                              Point2(
                                canvasState.origin.x -
                                    delta.dx / canvasState.zoom,
                                canvasState.origin.y -
                                    delta.dy / canvasState.zoom,
                              ),
                            );
                          },
                        ),
                        Expanded(
                          child: _Ruler(
                            state: canvasState,
                            horizontal: true,
                            onGuide: (globalPosition) =>
                                _addGuide(globalPosition, horizontal: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: _Ruler(
                            state: canvasState,
                            horizontal: false,
                            onGuide: (globalPosition) =>
                                _addGuide(globalPosition, horizontal: false),
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size = Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (context.mounted) {
                                  context.read<CanvasBloc>().setViewport(size);
                                }
                              });
                              if (canvasState.viewport != size) {
                                // One frame of layout with the old viewport is
                                // acceptable; the next frame is coherent.
                              }
                              return Focus(
                                focusNode: _focusNode,
                                onKeyEvent: _handleKey,
                                child: Listener(
                                  onPointerSignal: (event) {
                                    if (event is PointerScrollEvent) {
                                      context.read<CanvasBloc>().zoomAt(
                                        event.localPosition,
                                        event.scrollDelta.dy < 0
                                            ? 1.12
                                            : 1 / 1.12,
                                      );
                                    }
                                  },
                                  child: MouseRegion(
                                    cursor: _cursor(canvasState, context),
                                    onHover: (event) {
                                      context.read<CanvasBloc>().setCursor(
                                        canvasState.screenToWorld(
                                          event.localPosition,
                                        ),
                                      );
                                    },
                                    onExit: (_) => context
                                        .read<CanvasBloc>()
                                        .clearCursor(),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        GestureDetector(
                                          key: _canvasKey,
                                          behavior: HitTestBehavior.opaque,
                                          onTapUp: _handleTapUp,
                                          onPanStart: _handlePanStart,
                                          onPanUpdate: _handlePanUpdate,
                                          onPanEnd: _handlePanEnd,
                                          onDoubleTap: () {
                                            if (context
                                                    .read<ToolBloc>()
                                                    .state
                                                    .active ==
                                                MoeTool.polygon) {
                                              _finishPolygon();
                                            }
                                          },
                                          child: Stack(
                                            fit: StackFit.expand,
                                            clipBehavior: Clip.hardEdge,
                                            children: [
                                              RepaintBoundary(
                                                child: CustomPaint(
                                                  painter:
                                                      CanvasBackgroundPainter(
                                                        canvasState:
                                                            canvasState,
                                                        cute: cute,
                                                      ),
                                                ),
                                              ),
                                              RepaintBoundary(
                                                child: CustomPaint(
                                                  painter: GeometryPainter(
                                                    canvasState: canvasState,
                                                    document: document,
                                                    spatialIndex: index,
                                                    measurements:
                                                        measureState.items,
                                                    cute: cute,
                                                    theme: Theme.of(context),
                                                  ),
                                                ),
                                              ),
                                              RepaintBoundary(
                                                child: CustomPaint(
                                                  painter: CanvasOverlayPainter(
                                                    canvasState: canvasState,
                                                    selectedIds: selection,
                                                    document: document,
                                                    draftPoints: [
                                                      ..._draftPoints,
                                                      ..._freehandPoints,
                                                    ],
                                                    cute: cute,
                                                    rubberBand:
                                                        _rubberStart != null &&
                                                            _rubberCurrent !=
                                                                null
                                                        ? Rect.fromPoints(
                                                            _rubberStart!,
                                                            _rubberCurrent!,
                                                          )
                                                        : null,
                                                    shapePreview:
                                                        _shapeDragStart !=
                                                                null &&
                                                            _shapeDragCurrent !=
                                                                null
                                                        ? Rect.fromPoints(
                                                            _shapeDragStart!,
                                                            _shapeDragCurrent!,
                                                          )
                                                        : null,
                                                    shapePreviewEllipse:
                                                        context
                                                            .read<ToolBloc>()
                                                            .state
                                                            .active ==
                                                        MoeTool.ellipse,
                                                    animationSample: sample,
                                                    animatedTargetId:
                                                        animation?.targetId,
                                                    showOrigin: true,
                                                  ),
                                                ),
                                              ),
                                              if (_lastSnap != null)
                                                Positioned(
                                                  left:
                                                      canvasState
                                                          .worldToScreen(
                                                            _lastSnap!,
                                                          )
                                                          .dx -
                                                      9,
                                                  top:
                                                      canvasState
                                                          .worldToScreen(
                                                            _lastSnap!,
                                                          )
                                                          .dy -
                                                      9,
                                                  child: IgnorePointer(
                                                    child: Container(
                                                      width: 18,
                                                      height: 18,
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                          color: cute
                                                              ? const Color(
                                                                  0xffd77c9c,
                                                                )
                                                              : const Color(
                                                                  0xff2d6fa7,
                                                                ),
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              9,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (segmentLength != null)
                                                Positioned(
                                                  left: 10,
                                                  top: 10,
                                                  child: IgnorePointer(
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.94,
                                                            ),
                                                        border: Border.all(
                                                          color: const Color(
                                                            0xff6e879b,
                                                          ),
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        boxShadow: const [
                                                          BoxShadow(
                                                            color: Color(
                                                              0x22000000,
                                                            ),
                                                            blurRadius: 3,
                                                            offset: Offset(
                                                              0,
                                                              1,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 5,
                                                            ),
                                                        child: Text(
                                                          '${AppLocalizations.of(context).measureLength}: '
                                                          '$segmentLength',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: Color(
                                                                  0xff203548,
                                                                ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: 22,
                          child: _Ruler(
                            state: canvasState,
                            horizontal: false,
                            rightSide: true,
                            onGuide: (globalPosition) =>
                                _addGuide(globalPosition, horizontal: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        const SizedBox(width: 22),
                        Expanded(
                          child: _Ruler(
                            state: canvasState,
                            horizontal: true,
                            bottomSide: true,
                            onGuide: (globalPosition) =>
                                _addGuide(globalPosition, horizontal: true),
                          ),
                        ),
                        const SizedBox(width: 22),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  AnimationSpec? _activeAnimation(
    GeometryDocument document,
    AnimationState animationState,
  ) {
    if (document.animations.isEmpty) return null;
    final id = animationState.activeAnimationId;
    if (id != null) {
      for (final animation in document.animations) {
        if (animation.id == id) return animation;
      }
    }
    return null;
  }

  MouseCursor _cursor(CanvasState canvas, BuildContext context) {
    final tool = context.read<ToolBloc>().state.active;
    if (tool == MoeTool.pan ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.space,
        )) {
      return SystemMouseCursors.grab;
    }
    if (tool == MoeTool.zoom) return SystemMouseCursors.zoomIn;
    if (tool == MoeTool.select) return SystemMouseCursors.basic;
    return SystemMouseCursors.precise;
  }

  void _addGuide(Offset globalPosition, {required bool horizontal}) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final canvas = context.read<CanvasBloc>().state;
    final world = canvas.screenToWorld(local);
    context.read<CanvasBloc>().addGuide(
      GuideLine(
        vertical: !horizontal,
        position: horizontal ? world.y : world.x,
      ),
    );
  }
}

class _RulerCorner extends StatelessWidget {
  const _RulerCorner({
    required this.canvasState,
    required this.onDrag,
    required this.onReset,
  });

  final CanvasState canvasState;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => onDrag(details.delta),
      onSecondaryTap: onReset,
      child: Tooltip(
        message: AppLocalizations.of(context).rulerOriginReset,
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xffeef1f5),
            border: Border(
              right: BorderSide(color: Color(0xffc8ced6)),
              bottom: BorderSide(color: Color(0xffc8ced6)),
            ),
          ),
          child: const Icon(
            Icons.open_with,
            size: 13,
            color: Color(0xff607286),
          ),
        ),
      ),
    );
  }
}

class _Ruler extends StatelessWidget {
  const _Ruler({
    required this.state,
    required this.horizontal,
    required this.onGuide,
    this.bottomSide = false,
    this.rightSide = false,
  });

  final CanvasState state;
  final bool horizontal;
  final ValueChanged<Offset> onGuide;
  final bool bottomSide;
  final bool rightSide;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanEnd: (details) => onGuide(details.globalPosition),
      child: CustomPaint(
        painter: _RulerPainter(
          state: state,
          horizontal: horizontal,
          reverse: bottomSide || rightSide,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.state,
    required this.horizontal,
    required this.reverse,
  });

  final CanvasState state;
  final bool horizontal;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff2f4f7),
    );
    final linePaint = Paint()
      ..color = const Color(0xffaeb7c2)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      horizontal ? Offset(0, size.height) : Offset(size.width, 0),
      horizontal
          ? Offset(size.width, size.height)
          : Offset(size.width, size.height),
      linePaint,
    );
    final spacing = state.gridSpacing * state.zoom;
    if (spacing < 4 || !spacing.isFinite) return;
    final origin = horizontal
        ? state.worldToScreen(state.origin).dx
        : state.worldToScreen(state.origin).dy;
    final length = horizontal ? size.width : size.height;
    final first = ((-origin) / spacing).floor();
    final last = ((length - origin) / spacing).ceil();
    final tickPaint = Paint()
      ..color = const Color(0xff778594)
      ..strokeWidth = 0.8;
    for (var i = first; i <= last; i++) {
      final position = origin + i * spacing;
      final major = i % 5 == 0;
      final tick = major ? 7.0 : 4.0;
      if (horizontal) {
        final y = reverse ? 0.0 : size.height - tick;
        canvas.drawLine(
          Offset(position, y),
          Offset(position, size.height),
          tickPaint,
        );
        if (major) {
          final label = (i * state.gridSpacing).toStringAsFixed(0);
          final painter = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(fontSize: 8, color: Color(0xff667685)),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(position + 2, reverse ? 2 : 1));
        }
      } else {
        final x = reverse ? size.width - tick : 0.0;
        canvas.drawLine(
          Offset(x, position),
          Offset(size.width, position),
          tickPaint,
        );
        if (major) {
          final label = (i * state.gridSpacing).toStringAsFixed(0);
          final painter = TextPainter(
            text: TextSpan(
              text: label,
              style: const TextStyle(fontSize: 8, color: Color(0xff667685)),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(reverse ? 2 : 2, position + 1));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.horizontal != horizontal ||
      oldDelegate.reverse != reverse;
}

class _FunctionDialog extends StatefulWidget {
  const _FunctionDialog({required this.onCreated});
  final void Function(Map<String, Object?> params, String? label) onCreated;

  @override
  State<_FunctionDialog> createState() => _FunctionDialogState();
}

class _FunctionDialogState extends State<_FunctionDialog> {
  final TextEditingController _expression = TextEditingController(
    text: 'sin(x)',
  );
  final TextEditingController _expression2 = TextEditingController(text: 't');
  final TextEditingController _expression3 = TextEditingController(text: 't');
  final TextEditingController _label = TextEditingController();
  String _kind = 'explicit';
  String? _error;

  @override
  void dispose() {
    _expression.dispose();
    _expression2.dispose();
    _expression3.dispose();
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      late Map<String, Object?> params;
      switch (_kind) {
        case 'parametric':
          final x = Expression.parse(_expression2.text);
          final y = Expression.parse(_expression3.text);
          params = {
            'kind': 'parametric',
            'xExpression': _expression2.text,
            'yExpression': _expression3.text,
          };
          // Validate a sample evaluation.
          x.evaluate({'t': 0});
          y.evaluate({'t': 0});
        case 'polar':
          final r = Expression.parse(_expression.text);
          r.evaluate({'theta': 0});
          params = {'kind': 'polar', 'rExpression': _expression.text};
        case 'implicit':
          final f = Expression.parse(_expression.text);
          f.evaluate({'x': 0, 'y': 0});
          params = {'kind': 'implicit', 'expression': _expression.text};
        default:
          final f = Expression.parse(_expression.text);
          f.evaluate({'x': 0});
          params = {
            'kind': 'explicit',
            'expression': _expression.text,
            'xMin': -10,
            'xMax': 10,
          };
      }
      widget.onCreated(
        params,
        _label.text.trim().isEmpty ? null : _label.text.trim(),
      );
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } on EvaluationException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.toolFunction),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_kind),
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'kind'),
              items: const [
                DropdownMenuItem(value: 'explicit', child: Text('y = f(x)')),
                DropdownMenuItem(
                  value: 'parametric',
                  child: Text('x(t), y(t)'),
                ),
                DropdownMenuItem(value: 'polar', child: Text('r(θ)')),
                DropdownMenuItem(value: 'implicit', child: Text('f(x, y) = 0')),
              ],
              onChanged: (value) => setState(() => _kind = value ?? 'explicit'),
            ),
            const SizedBox(height: 8),
            if (_kind != 'parametric')
              TextField(
                controller: _expression,
                decoration: InputDecoration(
                  labelText: _kind == 'explicit'
                      ? 'f(x)'
                      : _kind == 'polar'
                      ? 'r(θ)'
                      : 'f(x, y)',
                ),
              ),
            if (_kind == 'parametric') ...[
              TextField(
                controller: _expression2,
                decoration: const InputDecoration(labelText: 'x(t)'),
              ),
              TextField(
                controller: _expression3,
                decoration: const InputDecoration(labelText: 'y(t)'),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'label (optional)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Safe AST: sin cos tan sqrt abs ln log10 exp min max pow. No code execution.',
                style: TextStyle(fontSize: 10, color: Color(0xff667788)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.newDocument)),
      ],
    );
  }
}
