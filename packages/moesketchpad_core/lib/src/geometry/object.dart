// SPDX-License-Identifier: GPL-3.0-only
/// Serialisable geometry objects, annotations and document-level state.
library;

import 'dart:math' as math;

import 'point.dart';

enum GeometryKind {
  point,
  segment,
  line,
  ray,
  circle,
  arc,
  triangle,
  polygon,
  conic,
  function,
  vector,
  coordinate,
  solid;

  static GeometryKind parse(String value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    throw FormatException('Unsupported geometry kind "$value".');
  }

  /// Kinds whose visual bounds are unbounded and therefore cannot be indexed
  /// as a finite box. Queries always return these as candidates.
  bool get isUnbounded =>
      this == GeometryKind.line ||
      this == GeometryKind.function ||
      this == GeometryKind.coordinate;
}

enum ConicType {
  ellipse,
  parabola,
  hyperbola;

  static ConicType parse(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unsupported conic type "$value".');
  }
}

enum FunctionKind {
  explicit,
  parametric,
  polar,
  implicit;

  static FunctionKind parse(String value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    throw FormatException('Unsupported function kind "$value".');
  }
}

class ObjectStyle {
  const ObjectStyle({
    this.strokeColor = 0xff296fa8,
    this.fillColor,
    this.strokeWidth = 1.6,
    this.dash = const <double>[],
    this.opacity = 1,
  });

  final int strokeColor;
  final int? fillColor;
  final double strokeWidth;
  final List<double> dash;
  final double opacity;

  Map<String, Object?> toJson() => {
    'strokeColor': strokeColor,
    if (fillColor != null) 'fillColor': fillColor,
    'strokeWidth': strokeWidth,
    if (dash.isNotEmpty) 'dash': dash,
    'opacity': opacity,
  };

  factory ObjectStyle.fromJson(Object? value) {
    if (value == null) return const ObjectStyle();
    if (value is! Map) throw const FormatException('Invalid object style.');
    final strokeWidth = value['strokeWidth'];
    final opacity = value['opacity'];
    final strokeColor = value['strokeColor'];
    final fillColor = value['fillColor'];
    final dash = value['dash'];
    if (strokeColor is! num ||
        strokeColor < 0 ||
        strokeColor > 0xffffffff ||
        (fillColor != null &&
            (fillColor is! num || fillColor < 0 || fillColor > 0xffffffff)) ||
        strokeWidth is! num ||
        !strokeWidth.isFinite ||
        strokeWidth <= 0 ||
        opacity is! num ||
        !opacity.isFinite ||
        opacity < 0 ||
        opacity > 1 ||
        (dash != null && dash is! List)) {
      throw const FormatException('Invalid style values.');
    }
    return ObjectStyle(
      strokeColor: strokeColor.toInt(),
      fillColor: fillColor is num ? fillColor.toInt() : null,
      strokeWidth: strokeWidth.toDouble(),
      opacity: opacity.toDouble(),
      dash: dash is List
          ? dash
                .map((item) {
                  if (item is! num || !item.isFinite || item <= 0) {
                    throw const FormatException('Invalid dash pattern.');
                  }
                  return item.toDouble();
                })
                .toList(growable: false)
          : const <double>[],
    );
  }
}

class LabelStyle {
  const LabelStyle({
    this.fontSize = 14,
    this.italic = true,
    this.bold = false,
    this.color = 0xff213547,
    this.offsetX = 8,
    this.offsetY = -22,
  });

  final double fontSize;
  final bool italic;
  final bool bold;
  final int color;
  final double offsetX;
  final double offsetY;

  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    'italic': italic,
    'bold': bold,
    'color': color,
    'offsetX': offsetX,
    'offsetY': offsetY,
  };

  factory LabelStyle.fromJson(Object? value) {
    if (value == null) return const LabelStyle();
    if (value is! Map) throw const FormatException('Invalid label style.');
    final fontSize = value['fontSize'];
    final color = value['color'];
    final offsetX = value['offsetX'];
    final offsetY = value['offsetY'];
    if (fontSize is! num ||
        !fontSize.isFinite ||
        fontSize <= 0 ||
        fontSize > 500 ||
        color is! num ||
        color < 0 ||
        color > 0xffffffff ||
        offsetX is! num ||
        offsetY is! num ||
        !offsetX.isFinite ||
        !offsetY.isFinite) {
      throw const FormatException('Invalid label style values.');
    }
    return LabelStyle(
      fontSize: fontSize.toDouble(),
      italic: value['italic'] == true,
      bold: value['bold'] == true,
      color: color.toInt(),
      offsetX: offsetX.toDouble(),
      offsetY: offsetY.toDouble(),
    );
  }
}

/// A dynamic geometry object.
///
/// `points` are construction points. For an explicit function and some conics
/// the parameters carry the analytic definition instead; renderers sample
/// those in the current viewport.
class GeometryObject {
  const GeometryObject({
    required this.id,
    required this.kind,
    required this.points,
    this.label,
    this.labelStyle = const LabelStyle(),
    this.style = const ObjectStyle(),
    this.layerId = 'layer-1',
    this.visible = true,
    this.locked = false,
    this.params = const <String, Object?>{},
  });

  final String id;
  final GeometryKind kind;
  final List<Point2> points;
  final String? label;
  final LabelStyle labelStyle;
  final ObjectStyle style;
  final String layerId;
  final bool visible;
  final bool locked;
  final Map<String, Object?> params;

  bool get isBounded {
    if (kind.isUnbounded) return false;
    return points.isNotEmpty;
  }

  /// Finite bounds for R-tree entries, or `null` for unbounded geometry.
  Bounds2? get bounds {
    if (!isBounded) return null;
    return Bounds2.fromPoints(points);
  }

  bool get isPointLike =>
      kind == GeometryKind.point || kind == GeometryKind.vector;

  GeometryObject copyWith({
    String? id,
    GeometryKind? kind,
    List<Point2>? points,
    String? label,
    bool clearLabel = false,
    LabelStyle? labelStyle,
    ObjectStyle? style,
    String? layerId,
    bool? visible,
    bool? locked,
    Map<String, Object?>? params,
  }) => GeometryObject(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    points: points ?? this.points,
    label: clearLabel ? null : (label ?? this.label),
    labelStyle: labelStyle ?? this.labelStyle,
    style: style ?? this.style,
    layerId: layerId ?? this.layerId,
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    params: params ?? this.params,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'points': [for (final point in points) point.toJson()],
    if (label != null) 'label': label,
    'labelStyle': labelStyle.toJson(),
    'style': style.toJson(),
    'layerId': layerId,
    'visible': visible,
    'locked': locked,
    if (params.isNotEmpty) 'params': params,
  };

  factory GeometryObject.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Geometry object expected.');
    final id = value['id'];
    final kind = value['kind'];
    final rawPoints = value['points'];
    final label = value['label'];
    final layerId = value['layerId'];
    final params = value['params'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(id)) {
      throw const FormatException('Object id is missing or invalid.');
    }
    if (kind is! String || rawPoints is! List) {
      throw const FormatException('Object kind or points missing.');
    }
    if (rawPoints.length > 100000) {
      throw const FormatException('Too many construction points.');
    }
    if (label != null && (label is! String || label.length > 128)) {
      throw const FormatException('Object label is invalid.');
    }
    if (layerId != null && (layerId is! String || layerId.isEmpty)) {
      throw const FormatException('Object layer is invalid.');
    }
    if (params != null && params is! Map) {
      throw const FormatException('Object params must be an object.');
    }
    return GeometryObject(
      id: id,
      kind: GeometryKind.parse(kind),
      points: [for (final point in rawPoints) Point2.fromJson(point)],
      label: label as String?,
      labelStyle: LabelStyle.fromJson(value['labelStyle']),
      style: ObjectStyle.fromJson(value['style']),
      layerId: layerId is String ? layerId : 'layer-1',
      visible: value['visible'] != false,
      locked: value['locked'] == true,
      params: params is Map
          ? _safeJsonMap(Map<String, Object?>.from(params))
          : const <String, Object?>{},
    );
  }

  @override
  String toString() => '${kind.name}($id)';
}

class Layer {
  const Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
  });

  final String id;
  final String name;
  final bool visible;
  final bool locked;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'visible': visible,
    'locked': locked,
  };

  factory Layer.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid layer.');
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.length > 128) {
      throw const FormatException('Invalid layer identity.');
    }
    return Layer(
      id: id,
      name: name,
      visible: value['visible'] != false,
      locked: value['locked'] == true,
    );
  }
}

enum MeasurementType {
  length,
  arcLength,
  angle,
  area,
  slope,
  functionValue;

  static MeasurementType parse(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unsupported measurement type "$value".');
  }
}

enum MeasureUnit {
  unitless,
  cm,
  mm,
  px,
  custom;

  static MeasureUnit parse(String value) {
    for (final unit in values) {
      if (unit.name == value) return unit;
    }
    throw FormatException('Unsupported unit "$value".');
  }
}

class Measurement {
  const Measurement({
    required this.id,
    required this.type,
    required this.targetIds,
    this.unit = MeasureUnit.unitless,
    this.customScale = 1,
    this.decimals = 2,
    this.visible = true,
    this.offsetX = 10,
    this.offsetY = 10,
  });

  final String id;
  final MeasurementType type;
  final List<String> targetIds;
  final MeasureUnit unit;
  final double customScale;
  final int decimals;
  final bool visible;
  final double offsetX;
  final double offsetY;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'targetIds': targetIds,
    'unit': unit.name,
    'customScale': customScale,
    'decimals': decimals,
    'visible': visible,
    'offsetX': offsetX,
    'offsetY': offsetY,
  };

  factory Measurement.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid measurement.');
    final id = value['id'];
    final type = value['type'];
    final targets = value['targetIds'];
    final unit = value['unit'] ?? 'unitless';
    final customScale = value['customScale'] ?? 1;
    final decimals = value['decimals'] ?? 2;
    if (id is! String ||
        type is! String ||
        targets is! List ||
        targets.isEmpty ||
        targets.any((target) => target is! String) ||
        unit is! String ||
        customScale is! num ||
        !customScale.isFinite ||
        customScale <= 0 ||
        decimals is! int ||
        decimals < 0 ||
        decimals > 12) {
      throw const FormatException('Invalid measurement fields.');
    }
    return Measurement(
      id: id,
      type: MeasurementType.parse(type),
      targetIds: targets.cast<String>(),
      unit: MeasureUnit.parse(unit),
      customScale: customScale.toDouble(),
      decimals: decimals,
      visible: value['visible'] != false,
      offsetX: (value['offsetX'] as num?)?.toDouble() ?? 10,
      offsetY: (value['offsetY'] as num?)?.toDouble() ?? 10,
    );
  }
}

enum ConstraintType {
  coincident,
  pointOnLine,
  pointOnCircle,
  distance,
  horizontal,
  vertical,
  parallel,
  perpendicular,
  equalLength,
  angle,
  tangent;

  static ConstraintType parse(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unsupported constraint "$value".');
  }
}

class Constraint {
  const Constraint({
    required this.id,
    required this.type,
    required this.targetIds,
    this.value,
  });

  final String id;
  final ConstraintType type;
  final List<String> targetIds;
  final double? value;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'targetIds': targetIds,
    if (value != null) 'value': value,
  };

  factory Constraint.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid constraint.');
    final id = value['id'];
    final type = value['type'];
    final targets = value['targetIds'];
    final numericValue = value['value'];
    if (id is! String ||
        type is! String ||
        targets is! List ||
        targets.isEmpty ||
        targets.any((target) => target is! String) ||
        (numericValue != null &&
            (numericValue is! num || !numericValue.isFinite))) {
      throw const FormatException('Invalid constraint fields.');
    }
    return Constraint(
      id: id,
      type: ConstraintType.parse(type),
      targetIds: targets.cast<String>(),
      value: numericValue is num ? numericValue.toDouble() : null,
    );
  }
}

class AnimationSpec {
  const AnimationSpec({
    required this.id,
    required this.targetId,
    this.pathObjectId,
    this.pathKind = 'segment',
    this.t0 = 0,
    this.t1 = 1,
    this.speed = 1,
    this.loop = false,
    this.pingPong = false,
    this.trail = 0,
  });

  final String id;
  final String targetId;
  final String? pathObjectId;
  final String pathKind;
  final double t0;
  final double t1;
  final double speed;
  final bool loop;
  final bool pingPong;
  final int trail;

  Map<String, Object?> toJson() => {
    'id': id,
    'targetId': targetId,
    if (pathObjectId != null) 'pathObjectId': pathObjectId,
    'pathKind': pathKind,
    't0': t0,
    't1': t1,
    'speed': speed,
    'loop': loop,
    'pingPong': pingPong,
    'trail': trail,
  };

  factory AnimationSpec.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid animation.');
    final id = value['id'];
    final targetId = value['targetId'];
    final pathKind = value['pathKind'] ?? 'segment';
    final t0 = value['t0'];
    final t1 = value['t1'];
    final speed = value['speed'];
    final trail = value['trail'] ?? 0;
    final rawPathObjectId = value['pathObjectId'];
    if (id is! String ||
        targetId is! String ||
        (rawPathObjectId != null && rawPathObjectId is! String) ||
        pathKind is! String ||
        t0 is! num ||
        t1 is! num ||
        speed is! num ||
        !t0.isFinite ||
        !t1.isFinite ||
        !speed.isFinite ||
        trail is! int ||
        trail < 0 ||
        trail > 10000) {
      throw const FormatException('Invalid animation fields.');
    }
    return AnimationSpec(
      id: id,
      targetId: targetId,
      pathObjectId: rawPathObjectId as String?,
      pathKind: pathKind,
      t0: t0.toDouble(),
      t1: t1.toDouble(),
      speed: speed.toDouble(),
      loop: value['loop'] == true,
      pingPong: value['pingPong'] == true,
      trail: trail,
    );
  }
}

class PageSettings {
  const PageSettings({
    this.width = 210,
    this.height = 297,
    this.unit = 'mm',
    this.landscape = false,
  });

  final double width;
  final double height;
  final String unit;
  final bool landscape;

  double get effectiveWidth => landscape ? height : width;
  double get effectiveHeight => landscape ? width : height;

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'unit': unit,
    'landscape': landscape,
  };

  factory PageSettings.fromJson(Object? value) {
    if (value == null) return const PageSettings();
    if (value is! Map) throw const FormatException('Invalid page settings.');
    final width = value['width'];
    final height = value['height'];
    final unit = value['unit'];
    if (width is! num ||
        height is! num ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        unit is! String) {
      throw const FormatException('Invalid page dimensions.');
    }
    return PageSettings(
      width: width.toDouble(),
      height: height.toDouble(),
      unit: unit,
      landscape: value['landscape'] == true,
    );
  }
}

class ViewState {
  const ViewState({
    this.transform = const ViewTransform(center: Point2.zero, zoom: 1),
    this.page = const PageSettings(),
    this.showGrid = true,
    this.snapGrid = true,
    this.snapObjects = true,
    this.gridBaseSpacing = 24,
    this.snapTolerancePx = 9,
    this.geometryTolerance = const GeometryTolerance(
      relative: 1e-9,
      absolute: 1e-9,
    ),
    this.origin = Point2.zero,
    this.unit = 'mm',
    this.unitScaleMm = 25.4 / 96,
  });

  final ViewTransform transform;
  final PageSettings page;
  final bool showGrid;
  final bool snapGrid;
  final bool snapObjects;
  final double gridBaseSpacing;
  final double snapTolerancePx;
  final GeometryTolerance geometryTolerance;
  final Point2 origin;
  final String unit;
  final double unitScaleMm;

  ViewState copyWith({
    ViewTransform? transform,
    PageSettings? page,
    bool? showGrid,
    bool? snapGrid,
    bool? snapObjects,
    double? gridBaseSpacing,
    double? snapTolerancePx,
    GeometryTolerance? geometryTolerance,
    Point2? origin,
    String? unit,
    double? unitScaleMm,
  }) => ViewState(
    transform: transform ?? this.transform,
    page: page ?? this.page,
    showGrid: showGrid ?? this.showGrid,
    snapGrid: snapGrid ?? this.snapGrid,
    snapObjects: snapObjects ?? this.snapObjects,
    gridBaseSpacing: gridBaseSpacing ?? this.gridBaseSpacing,
    snapTolerancePx: snapTolerancePx ?? this.snapTolerancePx,
    geometryTolerance: geometryTolerance ?? this.geometryTolerance,
    origin: origin ?? this.origin,
    unit: unit ?? this.unit,
    unitScaleMm: unitScaleMm ?? this.unitScaleMm,
  );

  Map<String, Object?> toJson() => {
    'transform': transform.toJson(),
    'page': page.toJson(),
    'showGrid': showGrid,
    'snapGrid': snapGrid,
    'snapObjects': snapObjects,
    'gridBaseSpacing': gridBaseSpacing,
    'snapTolerancePx': snapTolerancePx,
    'geometryTolerance': geometryTolerance.toJson(),
    'origin': origin.toJson(),
    'unit': unit,
    'unitScaleMm': unitScaleMm,
  };

  factory ViewState.fromJson(Object? value) {
    if (value == null) return const ViewState();
    if (value is! Map) throw const FormatException('Invalid view state.');
    final unitScaleMm = value['unitScaleMm'] ?? 25.4 / 96;
    final unit = value['unit'] ?? 'mm';
    final gridBaseSpacing = value['gridBaseSpacing'] ?? 24;
    final snapTolerancePx = value['snapTolerancePx'] ?? 9;
    if (unitScaleMm is! num ||
        !unitScaleMm.isFinite ||
        unitScaleMm <= 0 ||
        unit is! String ||
        gridBaseSpacing is! num ||
        !gridBaseSpacing.isFinite ||
        gridBaseSpacing <= 0 ||
        gridBaseSpacing > 1e9 ||
        snapTolerancePx is! num ||
        !snapTolerancePx.isFinite ||
        snapTolerancePx < 1 ||
        snapTolerancePx > 64) {
      throw const FormatException('Invalid view units.');
    }
    return ViewState(
      transform: ViewTransform.fromJson(value['transform']),
      page: PageSettings.fromJson(value['page']),
      showGrid: value['showGrid'] != false,
      snapGrid: value['snapGrid'] != false,
      snapObjects: value['snapObjects'] != false,
      gridBaseSpacing: gridBaseSpacing.toDouble(),
      snapTolerancePx: snapTolerancePx.toDouble(),
      geometryTolerance: GeometryTolerance.fromJson(value['geometryTolerance']),
      origin: value['origin'] == null
          ? Point2.zero
          : Point2.fromJson(value['origin']),
      unit: unit,
      unitScaleMm: unitScaleMm.toDouble(),
    );
  }
}

class GeometryDocument {
  GeometryDocument({
    required this.objects,
    this.constraints = const <Constraint>[],
    this.measurements = const <Measurement>[],
    this.animations = const <AnimationSpec>[],
    this.layers = const [Layer(id: 'layer-1', name: 'Layer 1')],
    this.view = const ViewState(),
    this.metadata = const <String, Object?>{},
    this.schemaVersion = currentSchemaVersion,
    this.title = 'Untitled-1',
  }) {
    _validate();
  }

  static const int currentSchemaVersion = 2;
  static const int maxObjects = 200000;
  static const int maxMeasurements = 20000;

  final List<GeometryObject> objects;
  final List<Constraint> constraints;
  final List<Measurement> measurements;
  final List<AnimationSpec> animations;
  final List<Layer> layers;
  final ViewState view;
  final Map<String, Object?> metadata;
  final int schemaVersion;
  final String title;

  GeometryObject? objectById(String id) {
    for (final object in objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  Iterable<Point2> get allPoints sync* {
    for (final object in objects) {
      yield* object.points;
    }
  }

  Bounds2? get contentBounds {
    Bounds2? result;
    for (final object in objects) {
      final bounds = object.bounds;
      if (bounds == null) continue;
      result = result == null ? bounds : result.union(bounds);
    }
    return result;
  }

  GeometryDocument copyWith({
    List<GeometryObject>? objects,
    List<Constraint>? constraints,
    List<Measurement>? measurements,
    List<AnimationSpec>? animations,
    List<Layer>? layers,
    ViewState? view,
    Map<String, Object?>? metadata,
    int? schemaVersion,
    String? title,
  }) => GeometryDocument(
    objects: objects ?? this.objects,
    constraints: constraints ?? this.constraints,
    measurements: measurements ?? this.measurements,
    animations: animations ?? this.animations,
    layers: layers ?? this.layers,
    view: view ?? this.view,
    metadata: metadata ?? this.metadata,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    title: title ?? this.title,
  );

  GeometryDocument withObject(GeometryObject object) {
    final index = objects.indexWhere((item) => item.id == object.id);
    final updated = [...objects];
    if (index >= 0) {
      updated[index] = object;
    } else {
      updated.add(object);
    }
    return copyWith(objects: updated);
  }

  GeometryDocument withoutObject(String id) => copyWith(
    objects: objects.where((object) => object.id != id).toList(growable: false),
    constraints: constraints
        .where((constraint) => !constraint.targetIds.contains(id))
        .toList(growable: false),
    measurements: measurements
        .where((measurement) => !measurement.targetIds.contains(id))
        .toList(growable: false),
    animations: animations
        .where(
          (animation) =>
              animation.targetId != id && animation.pathObjectId != id,
        )
        .toList(growable: false),
  );

  Map<String, Object?> toJson() => {
    'format': 'moesketchpad-document',
    'schemaVersion': schemaVersion,
    'title': title,
    'objects': [for (final object in objects) object.toJson()],
    'constraints': [for (final constraint in constraints) constraint.toJson()],
    'measurements': [for (final item in measurements) item.toJson()],
    'animations': [for (final animation in animations) animation.toJson()],
    'layers': [for (final layer in layers) layer.toJson()],
    'view': view.toJson(),
    'metadata': _safeJsonMap(metadata),
  };

  factory GeometryDocument.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Document must be an object.');
    }
    final format = value['format'];
    final schemaVersion = value['schemaVersion'];
    if (format != 'moesketchpad-document' ||
        schemaVersion is! int ||
        schemaVersion < 1 ||
        schemaVersion > currentSchemaVersion) {
      throw const FormatException('Unsupported document schema.');
    }
    final rawObjects = value['objects'];
    if (rawObjects is! List) throw const FormatException('Objects missing.');
    if (rawObjects.length > maxObjects) {
      throw const FormatException('Document contains too many objects.');
    }
    final objects = [
      for (final object in rawObjects) GeometryObject.fromJson(object),
    ];
    final rawConstraints = value['constraints'];
    final constraints = rawConstraints is List
        ? [
            for (final constraint in rawConstraints)
              Constraint.fromJson(constraint),
          ]
        : const <Constraint>[];
    final rawMeasurements = value['measurements'];
    if (rawMeasurements is List && rawMeasurements.length > maxMeasurements) {
      throw const FormatException('Too many measurements.');
    }
    final measurements = rawMeasurements is List
        ? [
            for (final measurement in rawMeasurements)
              Measurement.fromJson(measurement),
          ]
        : const <Measurement>[];
    final rawAnimations = value['animations'];
    final animations = rawAnimations is List
        ? [
            for (final animation in rawAnimations)
              AnimationSpec.fromJson(animation),
          ]
        : const <AnimationSpec>[];
    final rawLayers = value['layers'];
    final layers = rawLayers is List && rawLayers.isNotEmpty
        ? [for (final layer in rawLayers) Layer.fromJson(layer)]
        : const [Layer(id: 'layer-1', name: 'Layer 1')];
    final metadata = value['metadata'];
    if (metadata != null && metadata is! Map) {
      throw const FormatException('Metadata must be an object.');
    }
    final title = value['title'];
    if (title != null && title is! String) {
      throw const FormatException('Document title is invalid.');
    }
    return GeometryDocument(
      objects: objects,
      constraints: constraints,
      measurements: measurements,
      animations: animations,
      layers: layers,
      view: ViewState.fromJson(value['view']),
      metadata: metadata is Map
          ? _safeJsonMap(Map<String, Object?>.from(metadata))
          : const <String, Object?>{},
      schemaVersion: schemaVersion,
      title: (title as String?) ?? 'Untitled-1',
    );
  }

  void _validate() {
    if (objects.length > maxObjects) {
      throw const FormatException('Document contains too many objects.');
    }
    if (title.isEmpty || title.length > 256) {
      throw const FormatException('Document title is invalid.');
    }
    final ids = <String>{};
    for (final object in objects) {
      if (!ids.add(object.id)) {
        throw FormatException('Duplicate object id "${object.id}".');
      }
      for (final point in object.points) {
        if (!point.isFinite()) {
          throw FormatException(
            'Object "${object.id}" has a non-finite point.',
          );
        }
      }
      switch (object.kind) {
        case GeometryKind.point:
          if (object.points.length != 1) {
            throw FormatException('Point "${object.id}" needs one coordinate.');
          }
        case GeometryKind.segment:
        case GeometryKind.line:
        case GeometryKind.ray:
        case GeometryKind.vector:
          if (object.points.length != 2) {
            throw FormatException(
              '${object.kind.name} "${object.id}" needs two points.',
            );
          }
        case GeometryKind.circle:
          if (object.points.length < 2) {
            throw FormatException(
              'Circle "${object.id}" needs center and rim.',
            );
          }
        case GeometryKind.arc:
          if (object.points.length < 3) {
            throw FormatException('Arc "${object.id}" needs three points.');
          }
        case GeometryKind.triangle:
          if (object.points.length != 3) {
            throw FormatException(
              'Triangle "${object.id}" needs three points.',
            );
          }
        case GeometryKind.polygon:
          if (object.points.length < 3) {
            throw FormatException('Polygon "${object.id}" needs three points.');
          }
        case GeometryKind.conic:
          if (object.points.length < 3 || object.points.length > 5) {
            throw FormatException(
              'Conic "${object.id}" needs three to five points.',
            );
          }
        case GeometryKind.function:
          if (!object.params.containsKey('kind')) {
            throw FormatException(
              'Function "${object.id}" has no function kind.',
            );
          }
          if (!object.params.containsKey('expression') &&
              !object.params.containsKey('expressions')) {
            throw FormatException('Function "${object.id}" has no expression.');
          }
        case GeometryKind.coordinate:
          break;
        case GeometryKind.solid:
          if (object.points.length < 4) {
            throw FormatException('Solid "${object.id}" needs four points.');
          }
      }
    }
    final layerIds = layers.map((layer) => layer.id).toSet();
    if (layerIds.length != layers.length) {
      throw const FormatException('Duplicate layer id.');
    }
    for (final object in objects) {
      if (!layerIds.contains(object.layerId)) {
        throw FormatException(
          'Object "${object.id}" references a missing layer.',
        );
      }
    }
    final constraintIds = <String>{};
    for (final constraint in constraints) {
      if (!constraintIds.add(constraint.id)) {
        throw FormatException('Duplicate constraint id "${constraint.id}".');
      }
      for (final target in constraint.targetIds) {
        if (!ids.contains(target)) {
          throw FormatException('Constraint references unknown "$target".');
        }
      }
      if (constraint.type == ConstraintType.distance ||
          constraint.type == ConstraintType.angle) {
        if (constraint.value == null) {
          throw FormatException('Constraint "${constraint.id}" needs a value.');
        }
      }
      if (constraint.type == ConstraintType.tangent) {
        throw const FormatException(
          'Tangent constraint is reserved and not yet solvable in this build.',
        );
      }
    }
    for (final measurement in measurements) {
      for (final target in measurement.targetIds) {
        if (!ids.contains(target)) {
          throw FormatException('Measurement references unknown "$target".');
        }
      }
    }
    for (final animation in animations) {
      final target = objectById(animation.targetId);
      if (target == null || !target.isPointLike) {
        throw FormatException(
          'Animation "${animation.id}" needs a point/vector target.',
        );
      }
      if (animation.pathObjectId != null &&
          objectById(animation.pathObjectId!) == null) {
        throw FormatException('Animation path does not exist.');
      }
    }
    if (measurements.length > maxMeasurements) {
      throw const FormatException('Too many measurements.');
    }
    if (constraints.length > maxObjects || animations.length > maxObjects) {
      throw const FormatException('Too many annotations.');
    }
  }
}

Map<String, Object?> _safeJsonMap(Map<String, Object?> source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    if (entry.key.length > 128) {
      throw const FormatException('Metadata key is too long.');
    }
    result[entry.key] = _sanitizeJson(entry.value, depth: 0);
  }
  return result;
}

Object? _sanitizeJson(Object? value, {required int depth}) {
  if (depth > 16) throw const FormatException('JSON nesting is too deep.');
  if (value == null || value is String || value is bool) {
    if (value is String && value.length > 1000000) {
      throw const FormatException('String value is too large.');
    }
    return value;
  }
  if (value is num) {
    if (!value.isFinite) throw const FormatException('Non-finite number.');
    return value;
  }
  if (value is List) {
    if (value.length > 100000) {
      throw const FormatException('Array value is too large.');
    }
    return [for (final item in value) _sanitizeJson(item, depth: depth + 1)];
  }
  if (value is Map) {
    if (value.length > 10000) {
      throw const FormatException('Object value is too large.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('JSON object keys must be strings.');
      }
      result[entry.key as String] = _sanitizeJson(
        entry.value,
        depth: depth + 1,
      );
    }
    return result;
  }
  throw FormatException('Unsupported JSON value ${value.runtimeType}.');
}

/// Computes an auto label from an index: A..Z, a..z, then Greek letters.
String autoLabel(int index) {
  if (index < 0) throw ArgumentError.value(index, 'index');
  const letters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'q',
    'r',
    's',
    't',
    'u',
    'v',
    'w',
    'x',
    'y',
    'z',
    'α',
    'β',
    'γ',
    'δ',
    'ε',
    'ζ',
    'η',
    'θ',
    'ι',
    'κ',
    'λ',
    'μ',
    'ν',
    'ξ',
    'ο',
    'π',
    'ρ',
    'σ',
    'τ',
    'υ',
    'φ',
    'χ',
    'ψ',
    'ω',
  ];
  if (index < letters.length) return letters[index];
  return '${letters[index % letters.length]}${index ~/ letters.length + 1}';
}

double polygonArea(List<Point2> points) {
  if (points.length < 3) return 0;
  var twice = 0.0;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    twice += a.x * b.y - b.x * a.y;
  }
  return twice.abs() / 2;
}

Point2 segmentMidpoint(Point2 a, Point2 b) =>
    Point2((a.x + b.x) / 2, (a.y + b.y) / 2);

double normalizeDegrees(double degrees) {
  final value = degrees % 360;
  return value < 0 ? value + 360 : value;
}

double degreesToRadians(double degrees) => degrees * math.pi / 180;
double radiansToDegrees(double radians) => radians * 180 / math.pi;
