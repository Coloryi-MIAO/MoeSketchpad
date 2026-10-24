// SPDX-License-Identifier: GPL-3.0-only
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

class GuideLine {
  const GuideLine({required this.vertical, required this.position});
  final bool vertical;
  final double position;
}

class CanvasState {
  const CanvasState({
    this.pan = Offset.zero,
    this.zoom = 0.55,
    this.origin = Point2.zero,
    this.viewport = const Size(800, 600),
    this.showGrid = true,
    this.snapGrid = true,
    this.snapObjects = true,
    this.gridBaseSpacing = 24,
    this.snapTolerancePx = 9,
    this.geometryTolerance = const GeometryTolerance(
      relative: 1e-9,
      absolute: 1e-9,
    ),
    this.page = const PageSettings(),
    this.unit = 'mm',
    this.unitScaleMm = 25.4 / 96,
    this.cursorWorld,
    this.guides = const <GuideLine>[],
    this.spacePressed = false,
  });

  final Offset pan;
  final double zoom;
  final Point2 origin;
  final Size viewport;
  final bool showGrid;
  final bool snapGrid;
  final bool snapObjects;
  final double gridBaseSpacing;
  final double snapTolerancePx;
  final GeometryTolerance geometryTolerance;
  final PageSettings page;
  final String unit;
  final double unitScaleMm;
  final Point2? cursorWorld;
  final List<GuideLine> guides;
  final bool spacePressed;

  Offset get viewportCenter => Offset(viewport.width / 2, viewport.height / 2);

  Offset worldToScreen(Point2 point) => Offset(
    viewportCenter.dx + pan.dx + (point.x - origin.x) * zoom,
    viewportCenter.dy + pan.dy + (point.y - origin.y) * zoom,
  );

  Point2 screenToWorld(Offset screen) => Point2(
    (screen.dx - viewportCenter.dx - pan.dx) / zoom + origin.x,
    (screen.dy - viewportCenter.dy - pan.dy) / zoom + origin.y,
  );

  Bounds2 get visibleBounds {
    final topLeft = screenToWorld(Offset.zero);
    final bottomRight = screenToWorld(Offset(viewport.width, viewport.height));
    return Bounds2(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y);
  }

  double get gridSpacing {
    var spacing = gridBaseSpacing;
    while (spacing * zoom < 16) {
      spacing *= 2;
    }
    while (spacing * zoom > 80) {
      spacing /= 2;
    }
    return spacing;
  }

  Point2 get pageTopLeft => Point2(
    -page.effectiveWidth / unitScaleMm / 2,
    -page.effectiveHeight / unitScaleMm / 2,
  );

  Point2 get pageBottomRight => Point2(
    page.effectiveWidth / unitScaleMm / 2,
    page.effectiveHeight / unitScaleMm / 2,
  );

  CanvasState copyWith({
    Offset? pan,
    double? zoom,
    Point2? origin,
    Size? viewport,
    bool? showGrid,
    bool? snapGrid,
    bool? snapObjects,
    double? gridBaseSpacing,
    double? snapTolerancePx,
    GeometryTolerance? geometryTolerance,
    PageSettings? page,
    String? unit,
    double? unitScaleMm,
    Point2? cursorWorld,
    bool clearCursor = false,
    List<GuideLine>? guides,
    bool? spacePressed,
  }) => CanvasState(
    pan: pan ?? this.pan,
    zoom: zoom ?? this.zoom,
    origin: origin ?? this.origin,
    viewport: viewport ?? this.viewport,
    showGrid: showGrid ?? this.showGrid,
    snapGrid: snapGrid ?? this.snapGrid,
    snapObjects: snapObjects ?? this.snapObjects,
    gridBaseSpacing: gridBaseSpacing ?? this.gridBaseSpacing,
    snapTolerancePx: snapTolerancePx ?? this.snapTolerancePx,
    geometryTolerance: geometryTolerance ?? this.geometryTolerance,
    page: page ?? this.page,
    unit: unit ?? this.unit,
    unitScaleMm: unitScaleMm ?? this.unitScaleMm,
    cursorWorld: clearCursor ? null : (cursorWorld ?? this.cursorWorld),
    guides: guides ?? this.guides,
    spacePressed: spacePressed ?? this.spacePressed,
  );
}

class CanvasBloc extends Cubit<CanvasState> {
  CanvasBloc() : super(const CanvasState());

  void setViewport(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if ((state.viewport.width - size.width).abs() < 0.5 &&
        (state.viewport.height - size.height).abs() < 0.5) {
      return;
    }
    emit(state.copyWith(viewport: size));
  }

  void panBy(Offset delta) {
    emit(state.copyWith(pan: state.pan + delta));
  }

  void zoomAt(Offset focalPoint, double factor) {
    final nextZoom = (state.zoom * factor).clamp(0.002, 1e6);
    if (nextZoom == state.zoom) return;
    final world = state.screenToWorld(focalPoint);
    final center = state.viewportCenter;
    final pan = Offset(
      focalPoint.dx - center.dx - (world.x - state.origin.x) * nextZoom,
      focalPoint.dy - center.dy - (world.y - state.origin.y) * nextZoom,
    );
    emit(state.copyWith(zoom: nextZoom, pan: pan));
  }

  void setZoom(double zoom, {Offset? focalPoint}) {
    zoomAt(focalPoint ?? state.viewportCenter, zoom / state.zoom);
  }

  void setOrigin(Point2 origin) => emit(state.copyWith(origin: origin));
  void resetOrigin() => emit(state.copyWith(origin: Point2.zero));
  void setCursor(Point2 world) => emit(state.copyWith(cursorWorld: world));
  void clearCursor() => emit(state.copyWith(clearCursor: true));
  void toggleGrid() => emit(state.copyWith(showGrid: !state.showGrid));
  void setSnapGrid(bool value) => emit(state.copyWith(snapGrid: value));
  void setSnapObjects(bool value) => emit(state.copyWith(snapObjects: value));
  void setGridBaseSpacing(double value) =>
      emit(state.copyWith(gridBaseSpacing: value));
  void setSnapTolerancePx(double value) =>
      emit(state.copyWith(snapTolerancePx: value));
  void setGeometryTolerance(GeometryTolerance value) =>
      emit(state.copyWith(geometryTolerance: value));
  void setUnit(String value) => emit(state.copyWith(unit: value));
  void setPage(PageSettings page) => emit(state.copyWith(page: page));
  void setSpacePressed(bool value) => emit(state.copyWith(spacePressed: value));

  void addGuide(GuideLine guide) =>
      emit(state.copyWith(guides: [...state.guides, guide]));

  void removeGuide(GuideLine guide) {
    final next = [...state.guides]..remove(guide);
    emit(state.copyWith(guides: next));
  }

  void clearGuides() => emit(state.copyWith(guides: const []));

  void fitBounds(Bounds2? bounds) {
    if (bounds == null || bounds.width <= 0 && bounds.height <= 0) {
      emit(state.copyWith(pan: Offset.zero, zoom: 1, origin: Point2.zero));
      return;
    }
    final width = math.max(bounds.width, 1);
    final height = math.max(bounds.height, 1);
    final zoom = math
        .min(state.viewport.width / width, state.viewport.height / height)
        .clamp(0.002, 1000)
        .toDouble();
    final center = bounds.center;
    final pan = Offset(
      -(center.x - state.origin.x) * zoom,
      -(center.y - state.origin.y) * zoom,
    );
    emit(state.copyWith(zoom: zoom, pan: pan));
  }

  void applyView(ViewState view) {
    emit(
      state.copyWith(
        zoom: view.transform.zoom,
        origin: view.transform.origin,
        page: view.page,
        unitScaleMm: view.unitScaleMm,
        showGrid: view.showGrid,
        snapGrid: view.snapGrid,
        snapObjects: view.snapObjects,
        gridBaseSpacing: view.gridBaseSpacing,
        snapTolerancePx: view.snapTolerancePx,
        geometryTolerance: view.geometryTolerance,
        unit: view.unit,
      ),
    );
  }

  ViewState toViewState() => ViewState(
    transform: toViewTransform(),
    page: state.page,
    showGrid: state.showGrid,
    snapGrid: state.snapGrid,
    snapObjects: state.snapObjects,
    gridBaseSpacing: state.gridBaseSpacing,
    snapTolerancePx: state.snapTolerancePx,
    geometryTolerance: state.geometryTolerance,
    origin: state.origin,
    unit: state.unit,
    unitScaleMm: state.unitScaleMm,
  );

  ViewState withCurrentSettings(ViewState base) => base.copyWith(
    page: state.page,
    showGrid: state.showGrid,
    snapGrid: state.snapGrid,
    snapObjects: state.snapObjects,
    gridBaseSpacing: state.gridBaseSpacing,
    snapTolerancePx: state.snapTolerancePx,
    geometryTolerance: state.geometryTolerance,
    origin: state.origin,
    unit: state.unit,
    unitScaleMm: state.unitScaleMm,
  );

  ViewTransform toViewTransform() => ViewTransform(
    center: Point2.zero,
    zoom: state.zoom,
    origin: state.origin,
  );
}
