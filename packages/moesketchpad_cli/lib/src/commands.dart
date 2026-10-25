// SPDX-License-Identifier: GPL-3.0-only
/// The `moesp` command set (`msp` remains a compatibility executable).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:path/path.dart' as p;

import 'animated_exporter.dart';
import 'cli_support.dart';
import 'mcp_server.dart';
import 'primitives.dart';

class MspCommandRunner extends CommandRunner<int> {
  MspCommandRunner(this.globals)
    : super(
        'moesp',
        globals.t('萌板动态几何文档工具', 'MoeSketchpad dynamic geometry document tool'),
      ) {
    addCommand(CreateCommand(globals));
    addCommand(ConstraintCommand(globals));
    addCommand(LabelCommand(globals));
    addCommand(MeasureCommand(globals));
    addCommand(AnimateCommand(globals));
    addCommand(CalcCommand(globals));
    addCommand(ViewCommand(globals));
    addCommand(ValidateCommand(globals));
    addCommand(InspectCommand(globals));
    addCommand(ConvertCommand(globals));
    addCommand(ExportCommand(globals));
    addCommand(McpServeCommand(globals));
  }

  final CliGlobals globals;
}

Map<String, String> collectStringOptions(
  ArgResults results,
  Iterable<String> names,
) {
  final map = <String, String>{};
  for (final name in names) {
    if (!results.wasParsed(name)) continue;
    final value = results[name];
    if (value is String) map[name] = value;
  }
  return map;
}

class CreateCommand extends Command<int> {
  CreateCommand(this.globals) {
    for (final option in [
      'x',
      'y',
      'x1',
      'y1',
      'x2',
      'y2',
      'points',
      'center',
      'cx',
      'cy',
      'radius',
      'r',
      'start',
      'end',
      'a',
      'b',
      'rotation',
      'type',
      'sides',
      'hypotenuse',
      'kind',
      'expr',
      'expression',
      'x-expr',
      'y-expr',
      'r-expr',
      'x-min',
      'x-max',
      't-min',
      't-max',
      'label',
      'id',
      'edges',
    ]) {
      argParser.addOption(option);
    }
  }

  final CliGlobals globals;

  @override
  String get name => 'create';

  @override
  String get description => globals.t('创建几何图元', 'Create a geometry primitive');

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw CliFailure(
        exitUsage,
        globals.t(
          '用法：moesp create <primitive> [options] [--file doc.moesp]',
          'Usage: moesp create <primitive> [options] [--file doc.moesp]',
        ),
      );
    }
    final primitive = argResults!.rest.single;
    final options = collectStringOptions(argResults!, argParser.options.keys);
    try {
      final hasFile = globals.file != null;
      final document = hasFile
          ? await loadDocument(globals, allowMissing: true)
          : GeometryDocument(objects: []);
      final object = const PrimitiveFactory().build(
        primitive,
        options,
        document,
      );
      GeometryDocument result;
      if (hasFile) {
        result = document.withObject(object);
        await saveDocument(globals, result);
      } else {
        result = document.withObject(object);
      }
      emit(
        globals,
        jsonValue: {
          'ok': true,
          'primitive': primitive,
          'object': object.toJson(),
          if (hasFile) 'file': globals.file,
        },
        text: globals.t(
          '已创建 ${object.kind.name} ${object.id}'
              '${object.label == null || object.label!.isEmpty ? '' : ' (${object.label})'}'
              '${hasFile ? ' → ${globals.file}' : ''}',
          'Created ${object.kind.name} ${object.id}'
              '${object.label == null || object.label!.isEmpty ? '' : ' (${object.label})'}'
              '${hasFile ? ' → ${globals.file}' : ''}',
        ),
      );
      return exitSuccess;
    } on TriangleSolveException catch (error) {
      throw CliFailure(exitUnsatisfied, error.message);
    } on PrimitiveException catch (error) {
      throw CliFailure(exitUsage, error.message);
    } on FormatException catch (error) {
      throw CliFailure(exitUsage, error.message);
    }
  }
}

class ConstraintCommand extends Command<int> {
  ConstraintCommand(this.globals) {
    argParser
      ..addOption('value')
      ..addMultiOption('target')
      ..addFlag('internal', defaultsTo: false);
  }

  final CliGlobals globals;

  @override
  String get name => 'constraint';

  @override
  String get description =>
      globals.t('添加并求解几何约束', 'Add and solve a geometric constraint');

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw CliFailure(
        exitUsage,
        globals.t(
          '用法：moesp constraint <type> <target...> [--value=n] --file doc.moesp',
          'Usage: moesp constraint <type> <target...> [--value=n] --file doc.moesp',
        ),
      );
    }
    final rawType = rest.first;
    final typeName = rawType.replaceAll('-', '');
    final type = ConstraintType.values.where((value) {
      return value.name.toLowerCase() == typeName.toLowerCase();
    }).firstOrNull;
    if (type == null) {
      throw CliFailure(
        exitUsage,
        globals.t(
          '未知约束 "$rawType"。可用：coincident, point-on-line, '
              'point-on-circle, distance, horizontal, vertical, parallel, '
              'perpendicular, equal-length, angle, tangent-line-circle, '
              'tangent-circle-circle。',
          'Unknown constraint "$rawType". Supported: coincident, point-on-line, '
              'point-on-circle, distance, horizontal, vertical, parallel, '
              'perpendicular, equal-length, angle, tangent-line-circle, '
              'tangent-circle-circle.',
        ),
      );
    }
    final targets = <String>[
      ...argResults!['target'] as List<String>,
      ...rest.skip(1).expand((value) => value.split(',')),
    ].where((value) => value.trim().isNotEmpty).toList();
    if (targets.isEmpty) {
      throw CliFailure(exitUsage, 'Constraint targets are required.');
    }
    final value = argResults!['value'] == null
        ? null
        : double.tryParse(argResults!['value'] as String);
    if ((type == ConstraintType.distance || type == ConstraintType.angle) &&
        (value == null || !value.isFinite)) {
      throw CliFailure(exitUsage, 'This constraint requires a finite --value.');
    }
    if (argResults!['internal'] == true &&
        type != ConstraintType.tangentCircleCircle) {
      throw CliFailure(
        exitUsage,
        '--internal is only valid for tangent-circle-circle.',
      );
    }
    final document = await loadDocument(globals);
    final id = _nextConstraintId(document);
    final constraint = Constraint(
      id: id,
      type: type,
      targetIds: targets,
      value: value,
      internalTangency: argResults!['internal'] == true,
    );
    late GeometryDocument updated;
    try {
      updated = document.copyWith(
        constraints: [...document.constraints, constraint],
      );
    } on FormatException catch (error) {
      throw CliFailure(exitUnsatisfied, error.message);
    }
    final solve = ConstraintSolver(
      tolerance: document.view.geometryTolerance,
    ).solve(updated);
    if (!solve.converged) {
      throw CliFailure(
        exitUnsatisfied,
        globals.t(
          '约束无解或无法在容差内收敛（残差 ${solve.residual.toStringAsExponential(3)}）：'
              '${solve.message ?? ''}',
          'Constraint is unsatisfiable or did not converge within tolerance '
              '(residual ${solve.residual.toStringAsExponential(3)}): '
              '${solve.message ?? ''}',
        ),
      );
    }
    await saveDocument(globals, solve.document);
    emit(
      globals,
      jsonValue: {
        'ok': true,
        'constraint': constraint.toJson(),
        'solved': solve.converged,
        'iterations': solve.iterations,
        'residual': solve.residual,
        'file': globals.file,
      },
      text: globals.t(
        '已添加约束 $id，迭代 ${solve.iterations} 次，残差 ${solve.residual.toStringAsExponential(2)}。',
        'Added constraint $id; ${solve.iterations} iterations, residual '
            '${solve.residual.toStringAsExponential(2)}.',
      ),
    );
    return exitSuccess;
  }

  String _nextConstraintId(GeometryDocument document) {
    var index = 1;
    final ids = document.constraints.map((constraint) => constraint.id).toSet();
    while (ids.contains('constraint-$index')) {
      index++;
    }
    return 'constraint-$index';
  }
}

class LabelCommand extends Command<int> {
  LabelCommand(this.globals) {
    argParser
      ..addOption('text')
      ..addOption('offset')
      ..addOption('font-size')
      ..addFlag('italic', defaultsTo: true)
      ..addFlag('bold', defaultsTo: false)
      ..addOption('color')
      ..addFlag('auto', defaultsTo: false)
      ..addFlag('upper', defaultsTo: false)
      ..addFlag('lower', defaultsTo: false)
      ..addFlag('greek', defaultsTo: false);
  }

  final CliGlobals globals;

  @override
  String get name => 'label';

  @override
  String get description =>
      globals.t('为对象添加或自动补全字母标注', 'Label objects or auto-fill labels');

  @override
  Future<int> run() async {
    final document = await loadDocument(globals);
    final auto = argResults!['auto'] == true;
    final target = argResults!.rest.isEmpty ? null : argResults!.rest.first;
    if (!auto && target == null) {
      throw CliFailure(
        exitUsage,
        'Usage: moesp label <target> --text=A --file doc.moesp',
      );
    }
    var font = 14.0;
    if (argResults!['font-size'] != null) {
      final parsed = double.tryParse(argResults!['font-size'] as String);
      if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > 500) {
        throw CliFailure(exitUsage, '--font-size must be in (0, 500].');
      }
      font = parsed;
    }
    var offsetX = 8.0;
    var offsetY = -22.0;
    if (argResults!['offset'] != null) {
      final parts = (argResults!['offset'] as String).split(',');
      final x = parts.length == 2 ? double.tryParse(parts[0]) : null;
      final y = parts.length == 2 ? double.tryParse(parts[1]) : null;
      if (x == null || y == null) {
        throw CliFailure(exitUsage, '--offset must be x,y.');
      }
      offsetX = x;
      offsetY = y;
    }
    final color = argResults!['color'] == null
        ? 0xff213547
        : int.tryParse(argResults!['color'] as String);
    if (color == null || color < 0 || color > 0xffffffff) {
      throw CliFailure(exitUsage, '--color must be a 32-bit integer.');
    }
    final labels = <String, String>{};
    final objects = [...document.objects];
    if (auto) {
      var index = 0; // labels advance only for newly named points
      for (var i = 0; i < objects.length; i++) {
        final object = objects[i];
        if (object.kind != GeometryKind.point) continue;
        if (object.label == null || object.label!.isEmpty) {
          var text = autoLabel(index++);
          if (argResults!['upper'] == true) text = text.toUpperCase();
          if (argResults!['lower'] == true) text = text.toLowerCase();
          objects[i] = object.copyWith(
            label: text,
            labelStyle: LabelStyle(
              fontSize: font,
              offsetX: offsetX,
              offsetY: offsetY,
            ),
          );
          labels[object.id] = text;
        }
      }
    } else {
      final objectIndex = objects.indexWhere((object) => object.id == target);
      if (objectIndex < 0) {
        throw CliFailure(exitFormat, 'Target "$target" does not exist.');
      }
      var text = argResults!['text'] as String?;
      if (text == null || text.isEmpty) {
        throw CliFailure(
          exitUsage,
          '--text is required unless --auto is used.',
        );
      }
      if (argResults!['greek'] == true) {
        final greek = [
          'α',
          'β',
          'γ',
          'δ',
          'ε',
          'θ',
          'λ',
          'μ',
          'π',
          'σ',
          'φ',
          'ω',
        ];
        text = greek[(text.codeUnitAt(0) + text.length) % greek.length];
      }
      if (argResults!['upper'] == true) text = text.toUpperCase();
      if (argResults!['lower'] == true) text = text.toLowerCase();
      objects[objectIndex] = objects[objectIndex].copyWith(
        label: text,
        labelStyle: LabelStyle(
          fontSize: font,
          italic: argResults!['italic'] == true,
          bold: argResults!['bold'] == true,
          color: color,
          offsetX: offsetX,
          offsetY: offsetY,
        ),
      );
      labels[target!] = text;
    }
    final updated = document.copyWith(objects: objects);
    await saveDocument(globals, updated);
    emit(
      globals,
      jsonValue: {'ok': true, 'labels': labels, 'file': globals.file},
      text: globals.t(
        '已更新 ${labels.length} 个标注。',
        'Updated ${labels.length} label(s).',
      ),
    );
    return exitSuccess;
  }
}

class MeasureCommand extends Command<int> {
  MeasureCommand(this.globals) {
    argParser
      ..addOption('type', defaultsTo: 'length')
      ..addOption('unit', defaultsTo: 'unitless')
      ..addOption('custom-scale')
      ..addOption('decimals', defaultsTo: '2')
      ..addOption('offset')
      ..addMultiOption('target');
  }

  final CliGlobals globals;

  @override
  String get name => 'measure';

  @override
  String get description => globals.t('添加动态测量', 'Attach a dynamic measurement');

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final targets = <String>[
      ...argResults!['target'] as List<String>,
      ...rest.expand((value) => value.split(',')),
    ].where((value) => value.isNotEmpty).toList();
    if (targets.isEmpty) {
      throw CliFailure(exitUsage, 'Measurement target is required.');
    }
    final typeName = (argResults!['type'] as String).replaceAll('-', '');
    final type = MeasurementType.values
        .where((value) => value.name.toLowerCase() == typeName.toLowerCase())
        .firstOrNull;
    if (type == null) {
      throw CliFailure(exitUsage, 'Unknown measurement type.');
    }
    final unitName = (argResults!['unit'] as String).toLowerCase();
    final unit = MeasureUnit.values
        .where((value) => value.name == unitName)
        .firstOrNull;
    if (unit == null) {
      throw CliFailure(
        exitUsage,
        'Unit must be unitless, cm, mm, px or custom.',
      );
    }
    final decimals = int.tryParse(argResults!['decimals'] as String);
    if (decimals == null || decimals < 0 || decimals > 12) {
      throw CliFailure(exitUsage, '--decimals must be 0..12.');
    }
    final customScale = argResults!['custom-scale'] == null
        ? 1.0
        : double.tryParse(argResults!['custom-scale'] as String);
    if (customScale == null || !customScale.isFinite || customScale <= 0) {
      throw CliFailure(exitUsage, '--custom-scale must be positive.');
    }
    var offsetX = 10.0;
    var offsetY = 10.0;
    if (argResults!['offset'] != null) {
      final parts = (argResults!['offset'] as String).split(',');
      final x = parts.length == 2 ? double.tryParse(parts[0]) : null;
      final y = parts.length == 2 ? double.tryParse(parts[1]) : null;
      if (x == null || y == null) {
        throw CliFailure(exitUsage, '--offset must be x,y.');
      }
      offsetX = x;
      offsetY = y;
    }
    final document = await loadDocument(globals);
    final id = _nextMeasurementId(document);
    final measurement = Measurement(
      id: id,
      type: type,
      targetIds: targets,
      unit: unit,
      customScale: customScale,
      decimals: decimals,
      offsetX: offsetX,
      offsetY: offsetY,
    );
    late MeasurementValue value;
    try {
      value = const MeasurementEngine().measure(measurement, document);
    } on FormatException catch (error) {
      throw CliFailure(exitUnsatisfied, error.message);
    }
    final updated = document.copyWith(
      measurements: [...document.measurements, measurement],
    );
    await saveDocument(globals, updated);
    emit(
      globals,
      jsonValue: {
        'ok': true,
        'measurement': measurement.toJson(),
        'value': value.toJson(),
        'file': globals.file,
      },
      text: '$id: ${value.display}',
    );
    return exitSuccess;
  }

  String _nextMeasurementId(GeometryDocument document) {
    var index = 1;
    final ids = document.measurements.map((item) => item.id).toSet();
    while (ids.contains('measure-$index')) {
      index++;
    }
    return 'measure-$index';
  }
}

class AnimateCommand extends Command<int> {
  AnimateCommand(this.globals) {
    argParser
      ..addOption('path')
      ..addOption('t', defaultsTo: '0..1')
      ..addOption('speed', defaultsTo: '1')
      ..addFlag('loop', defaultsTo: false)
      ..addFlag('pingpong', defaultsTo: false)
      ..addOption('trail', defaultsTo: '0');
  }

  final CliGlobals globals;

  @override
  String get name => 'animate';

  @override
  String get description =>
      globals.t('创建动点动画', 'Create a moving-point animation');

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw CliFailure(
        exitUsage,
        'Usage: moesp animate <point> --path=<obj> --t=0..1 --speed=1 '
        '--loop|--pingpong --trail=20 --file doc.moesp',
      );
    }
    final target = argResults!.rest.single;
    final path = argResults!['path'] as String?;
    final tParts = (argResults!['t'] as String).split('..');
    final t0 = tParts.length == 2 ? double.tryParse(tParts[0]) : null;
    final t1 = tParts.length == 2 ? double.tryParse(tParts[1]) : null;
    final speed = double.tryParse(argResults!['speed'] as String);
    final trail = int.tryParse(argResults!['trail'] as String);
    if (t0 == null ||
        t1 == null ||
        speed == null ||
        trail == null ||
        !t0.isFinite ||
        !t1.isFinite ||
        !speed.isFinite ||
        t0 < 0 ||
        t1 > 1 ||
        t0 >= t1 ||
        speed <= 0 ||
        speed > 100 ||
        trail < 0 ||
        trail > 10000) {
      throw CliFailure(exitUsage, 'Invalid animation t/speed/trail options.');
    }
    final document = await loadDocument(globals);
    final id = _nextAnimationId(document);
    final spec = AnimationSpec(
      id: id,
      targetId: target,
      pathObjectId: path ?? target,
      t0: t0,
      t1: t1,
      speed: speed,
      loop: argResults!['loop'] == true,
      pingPong: argResults!['pingpong'] == true,
      trail: trail,
    );
    final preview = const AnimationEvaluator().sample(document, spec, 0);
    if (preview.error != null) {
      throw CliFailure(exitUnsatisfied, preview.error!);
    }
    final updated = document.copyWith(
      animations: [...document.animations, spec],
    );
    try {
      updated.withoutObject(
        '__validate__',
      ); // Trigger document validation via copy.
    } on FormatException catch (error) {
      throw CliFailure(exitUnsatisfied, error.message);
    }
    await saveDocument(globals, updated);
    emit(
      globals,
      jsonValue: {
        'ok': true,
        'animation': spec.toJson(),
        'preview': {
          'position': preview.position?.toJson(),
          'phase': preview.phase,
        },
        'file': globals.file,
      },
      text: globals.t(
        '已添加动画 $id（起点 ${preview.position}）。',
        'Added animation $id (start ${preview.position}).',
      ),
    );
    return exitSuccess;
  }

  String _nextAnimationId(GeometryDocument document) {
    var index = 1;
    final ids = document.animations.map((item) => item.id).toSet();
    while (ids.contains('animation-$index')) {
      index++;
    }
    return 'animation-$index';
  }
}

class CalcCommand extends Command<int> {
  CalcCommand(this.globals) {
    argParser.addMultiOption('var');
  }

  final CliGlobals globals;

  @override
  String get name => 'calc';

  @override
  String get description =>
      globals.t('安全计算数学表达式', 'Safely evaluate an expression');

  @override
  Future<int> run() async {
    final expression = argResults!.rest.join(' ').trim();
    if (expression.isEmpty) {
      throw CliFailure(exitUsage, 'Usage: moesp calc <expression>');
    }
    final variables = <String, double>{};
    for (final variable in argResults!['var'] as List<String>) {
      final parts = variable.split('=');
      final name = parts.length == 2 ? parts[0].trim() : '';
      final value = parts.length == 2 ? double.tryParse(parts[1].trim()) : null;
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name) ||
          value == null ||
          !value.isFinite) {
        throw CliFailure(exitUsage, '--var must be name=finite-number.');
      }
      variables[name] = value;
    }
    try {
      final value = const ExpressionEvaluator().evaluate(
        expression,
        variables: variables,
      );
      emit(
        globals,
        jsonValue: {'ok': true, 'expression': expression, 'value': value},
        text: '$value',
      );
      return exitSuccess;
    } on FormatException catch (error) {
      throw CliFailure(exitUsage, error.message);
    } on EvaluationException catch (error) {
      throw CliFailure(exitUsage, error.message);
    }
  }
}

class ViewCommand extends Command<int> {
  ViewCommand(this.globals) {
    argParser
      ..addOption('zoom')
      ..addOption('pan-x')
      ..addOption('pan-y')
      ..addOption('origin-x')
      ..addOption('origin-y')
      ..addOption('page')
      ..addOption('page-width')
      ..addOption('page-height')
      ..addOption('unit')
      ..addFlag('landscape', defaultsTo: false)
      ..addFlag('show-grid', defaultsTo: true)
      ..addFlag('snap-grid', defaultsTo: true)
      ..addFlag('snap-objects', defaultsTo: true);
  }

  final CliGlobals globals;

  @override
  String get name => 'view';

  @override
  String get description =>
      globals.t('修改画布视图与页面设置', 'Change canvas view and page settings');

  @override
  Future<int> run() async {
    final document = await loadDocument(globals);
    var view = document.view;
    double? parse(String key) {
      if (argResults![key] == null) return null;
      final value = double.tryParse(argResults![key] as String);
      if (value == null || !value.isFinite) {
        throw CliFailure(exitUsage, '--$key must be finite.');
      }
      return value;
    }

    final zoom = parse('zoom');
    final panX = parse('pan-x');
    final panY = parse('pan-y');
    final originX = parse('origin-x');
    final originY = parse('origin-y');
    if (zoom != null && (zoom <= 0 || zoom > 1e9)) {
      throw CliFailure(exitUsage, '--zoom must be positive and bounded.');
    }
    final oldTransform = view.transform;
    final String? pageUnit = argResults!['page'] as String?;
    final page = PageSettings(
      width: parse('page-width') ?? view.page.width,
      height: parse('page-height') ?? view.page.height,
      unit: pageUnit ?? view.page.unit,
      landscape: argResults!['landscape'] == true,
    );
    view = view.copyWith(
      transform: ViewTransform(
        center: Point2(
          oldTransform.center.x + (panX ?? 0),
          oldTransform.center.y + (panY ?? 0),
        ),
        zoom: zoom ?? oldTransform.zoom,
        origin: Point2(originX ?? view.origin.x, originY ?? view.origin.y),
      ),
      page: page,
      showGrid: argResults!['show-grid'] == true,
      snapGrid: argResults!['snap-grid'] == true,
      snapObjects: argResults!['snap-objects'] == true,
      unit: argResults!['unit'] as String? ?? view.unit,
    );
    final updated = document.copyWith(view: view);
    await saveDocument(globals, updated);
    emit(
      globals,
      jsonValue: {'ok': true, 'view': view.toJson(), 'file': globals.file},
      text: globals.t('视图已更新。', 'View updated.'),
    );
    return exitSuccess;
  }
}

class ValidateCommand extends Command<int> {
  ValidateCommand(this.globals) {
    argParser.addFlag('deep', defaultsTo: false);
  }

  final CliGlobals globals;

  @override
  String get name => 'validate';

  @override
  String get description => globals.t(
    '校验 .moesp 文件结构或完整认证',
    'Validate MSP structure or full authentication',
  );

  @override
  Future<int> run() async {
    final paths = [...argResults!.rest];
    final path = paths.isEmpty ? globals.file : paths.first;
    if (path == null) {
      throw CliFailure(
        exitUsage,
        'Usage: moesp validate <file.moesp> [--deep]',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      throw CliFailure(exitFormat, 'File not found: $path');
    }
    final bytes = await file.readAsBytes();
    try {
      final validation = MspCodec().validate(bytes);
      var authenticated = false;
      Map<String, Object?>? summary;
      if (argResults!['deep'] == true) {
        final document = await MspCodec().decode(
          bytes,
          password: globals.requirePassword(),
        );
        authenticated = true;
        summary = {
          'title': document.title,
          'objects': document.objects.length,
          'constraints': document.constraints.length,
          'measurements': document.measurements.length,
        };
      }
      emit(
        globals,
        jsonValue: {
          'ok': true,
          ...validation.toJson(),
          'authenticated': authenticated,
          'document': ?summary,
        },
        text: authenticated
            ? globals.t(
                'MSP v2 结构有效，GCM 认证通过。',
                'Valid MSP v2 and authenticated by GCM.',
              )
            : globals.t(
                'MSP v2 头部结构有效；未验证密码与认证标签（使用 --deep）。',
                'Valid MSP v2 header; password/GCM tag not checked (use --deep).',
              ),
      );
      return exitSuccess;
    } on MspFormatException catch (error) {
      throw CliFailure(exitFormat, error.message);
    } on MspDecryptionException catch (error) {
      throw CliFailure(exitDecrypt, error.message);
    }
  }
}

class InspectCommand extends Command<int> {
  InspectCommand(this.globals) {
    argParser.addFlag('header', defaultsTo: false);
    argParser.addFlag('full', defaultsTo: false);
  }

  final CliGlobals globals;

  @override
  String get name => 'inspect';

  @override
  String get description => globals.t('检查文档内容摘要', 'Inspect document summary');

  @override
  Future<int> run() async {
    final path = argResults!.rest.isNotEmpty
        ? argResults!.rest.first
        : globals.file;
    if (path == null) {
      throw CliFailure(
        exitUsage,
        'Usage: moesp inspect <file.moesp> [--header]',
      );
    }
    final bytes = await File(path).readAsBytes();
    try {
      if (argResults!['header'] == true) {
        final validation = MspCodec().validate(bytes);
        emit(
          globals,
          jsonValue: {'ok': true, ...validation.toJson()},
          text:
              'MSP v${validation.version} ${validation.encrypted ? 'encrypted' : ''} '
              '${validation.compressed ? 'gzip' : 'plain'} '
              '${validation.cipherLength} bytes',
        );
        return exitSuccess;
      }
      final document = await MspCodec().decode(
        bytes,
        password: globals.requirePassword(),
      );
      final counts = <String, int>{};
      for (final object in document.objects) {
        counts[object.kind.name] = (counts[object.kind.name] ?? 0) + 1;
      }
      final summary = {
        'ok': true,
        'version': MspCodec.currentVersion,
        'title': document.title,
        'schemaVersion': document.schemaVersion,
        'counts': counts,
        'objects': document.objects.length,
        'constraints': document.constraints.length,
        'measurements': document.measurements.length,
        'animations': document.animations.length,
        'layers': document.layers.length,
        'view': document.view.toJson(),
        if (argResults!['full'] == true) 'document': document.toJson(),
      };
      emit(
        globals,
        jsonValue: summary,
        text: globals.t(
          '${document.title}：${document.objects.length} 个对象，'
              '${document.constraints.length} 个约束，'
              '${document.measurements.length} 个测量。',
          '${document.title}: ${document.objects.length} objects, '
              '${document.constraints.length} constraints, '
              '${document.measurements.length} measurements.',
        ),
      );
      return exitSuccess;
    } on MspFormatException catch (error) {
      throw CliFailure(exitFormat, error.message);
    } on MspDecryptionException catch (error) {
      throw CliFailure(exitDecrypt, error.message);
    }
  }
}

class ConvertCommand extends Command<int> {
  ConvertCommand(this.globals) {
    argParser
      ..addOption('to', allowed: ['json', 'msp'])
      ..addOption('output')
      ..addFlag('force', defaultsTo: false)
      ..addFlag('no-compress', defaultsTo: false);
  }

  final CliGlobals globals;

  @override
  String get name => 'convert';

  @override
  String get description => globals.t(
    '在加密 MSP 与明文 JSON 之间转换',
    'Convert between encrypted MSP and plaintext JSON',
  );

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw CliFailure(
        exitUsage,
        'Usage: moesp convert <input> --to=json|msp --output=<path>',
      );
    }
    final input = File(argResults!.rest.single);
    if (!await input.exists()) {
      throw CliFailure(exitFormat, 'File not found: ${input.path}');
    }
    final inputExtension = p.extension(input.path).toLowerCase();
    final to =
        argResults!['to'] as String? ??
        (inputExtension == '.moesp' ? 'json' : 'msp');
    final outputPath = argResults!['output'] as String?;
    if (outputPath == null) {
      throw CliFailure(exitUsage, '--output is required.');
    }
    final output = File(outputPath);
    if (await output.exists() && argResults!['force'] != true) {
      throw CliFailure(
        exitSecurity,
        'Output exists; pass --force to overwrite.',
      );
    }
    final codec = MspCodec();
    GeometryDocument document;
    if (to == 'json') {
      if (inputExtension != '.moesp') {
        throw CliFailure(exitFormat, 'JSON output requires an .moesp input.');
      }
      try {
        document = await codec.decode(
          await input.readAsBytes(),
          password: globals.requirePassword(),
        );
      } on MspFormatException catch (error) {
        throw CliFailure(exitFormat, error.message);
      } on MspDecryptionException catch (error) {
        throw CliFailure(exitDecrypt, error.message);
      }
      await _writeText(
        path: output.path,
        text: codec.exportJson(document),
        force: true,
      );
    } else {
      final String source;
      try {
        source = await input.readAsString();
      } on FileSystemException {
        throw CliFailure(exitFormat, 'Cannot read JSON input.');
      }
      try {
        document = codec.importJson(source);
      } on FormatException catch (error) {
        throw CliFailure(exitFormat, error.message);
      } on MspFormatException catch (error) {
        throw CliFailure(exitFormat, error.message);
      }
      final bytes = await codec.encode(
        document,
        password: globals.requirePassword(),
        compress: argResults!['no-compress'] != true,
      );
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
    }
    emit(
      globals,
      jsonValue: {'ok': true, 'output': output.path, 'format': to},
      text: globals.t('已转换 → ${output.path}', 'Converted → ${output.path}'),
    );
    return exitSuccess;
  }

  Future<void> _writeText({
    required String path,
    required String text,
    required bool force,
  }) async {
    final output = File(path);
    if (!force && await output.exists()) {
      throw CliFailure(exitSecurity, 'Output exists.');
    }
    await output.parent.create(recursive: true);
    final temp = File('$path.tmp-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await temp.writeAsString(text, flush: true);
      await temp.rename(output.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}

class ExportCommand extends Command<int> {
  ExportCommand(this.globals) {
    argParser
      ..addOption(
        'format',
        defaultsTo: 'svg',
        allowed: ['svg', 'json', 'png', 'gif', 'apng'],
      )
      ..addOption('output')
      ..addOption('animation')
      ..addOption('frames', defaultsTo: '24')
      ..addOption('width', defaultsTo: '640')
      ..addOption('height', defaultsTo: '360')
      ..addOption('duration-ms', defaultsTo: '80')
      ..addOption('viewport', help: 'left,top,right,bottom for raster export')
      ..addFlag('force', defaultsTo: false);
  }

  final CliGlobals globals;

  @override
  String get name => 'export';

  @override
  String get description =>
      globals.t(
        '导出 SVG、PNG、JSON、GIF 或 APNG',
        'Export SVG, PNG, JSON, GIF, or APNG',
      );

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw CliFailure(
        exitUsage,
        'Usage: moesp export <file.moesp> --format=svg|json|png|gif|apng '
        '--output=<path> [--animation=id] [--frames=24] '
        '[--width=640 --height=360 --duration-ms=80] '
        '[--viewport=left,top,right,bottom]',
      );
    }
    final format = argResults!['format'] as String;
    final document = await loadDocument(globals, path: argResults!.rest.single);
    final outputPath = argResults!['output'] as String?;
    if (outputPath == null) {
      throw CliFailure(exitUsage, '--output is required.');
    }
    final output = File(outputPath);
    if (await output.exists() && argResults!['force'] != true) {
      throw CliFailure(
        exitSecurity,
        'Output exists; pass --force to overwrite.',
      );
    }
    await output.parent.create(recursive: true);
    if (format == 'gif' || format == 'apng') {
      final id = argResults!['animation'] as String?;
      final animations = document.animations;
      final animation = id == null
          ? animations.length == 1
                ? animations.single
                : null
          : animations.where((item) => item.id == id).firstOrNull;
      if (animation == null) {
        throw CliFailure(
          exitUsage,
          id == null
              ? 'Animated export needs --animation=<id> when the document has zero or multiple animations.'
              : 'Unknown animation "$id".',
        );
      }
      final width = _boundedInt('width', min: 16, max: 2048);
      final height = _boundedInt('height', min: 16, max: 2048);
      final frames = _boundedInt('frames', min: 2, max: 120);
      final duration = _boundedInt('duration-ms', min: 20, max: 2000);
      final viewport = _viewport(document);
      final exporter = const CliAnimatedExporter();
      final bytes = format == 'gif'
          ? exporter.exportGif(
              document: document,
              animation: animation,
              viewport: viewport,
              width: width,
              height: height,
              frameCount: frames,
              frameDurationMs: duration,
            )
          : exporter.exportApng(
              document: document,
              animation: animation,
              viewport: viewport,
              width: width,
              height: height,
              frameCount: frames,
              frameDurationMs: duration,
            );
      await output.writeAsBytes(bytes, flush: true);
    } else if (format == 'png') {
      final viewport = _viewport(document);
      final bytes = const CliAnimatedExporter().exportPng(
        document: document,
        viewport: viewport,
        width: _boundedInt('width', min: 16, max: 2048),
        height: _boundedInt('height', min: 16, max: 2048),
      );
      await output.writeAsBytes(bytes, flush: true);
    } else if (format == 'json') {
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(document.toJson()),
        flush: true,
      );
      stderr.writeln(
        globals.t(
          '注意：JSON 导出为明文，不包含密码保护。',
          'Warning: JSON export is plaintext and not password protected.',
        ),
      );
    } else {
      await output.writeAsString(SvgExporter().export(document), flush: true);
    }
    emit(
      globals,
      jsonValue: {'ok': true, 'output': output.path, 'format': format},
      text: globals.t('已导出 → ${output.path}', 'Exported → ${output.path}'),
    );
    return exitSuccess;
  }

  int _boundedInt(String name, {required int min, required int max}) {
    final value = int.tryParse(argResults![name] as String);
    if (value == null || value < min || value > max) {
      throw CliFailure(exitUsage, '--$name must be between $min and $max.');
    }
    return value;
  }

  Bounds2 _viewport(GeometryDocument document) {
    final raw = argResults!['viewport'] as String?;
    if (raw != null) {
      final values = raw.split(',').map(double.tryParse).toList();
      if (values.length != 4 ||
          values.any((value) => value == null || !value.isFinite)) {
        throw CliFailure(
          exitUsage,
          '--viewport must be left,top,right,bottom using finite numbers.',
        );
      }
      if (values[0]! >= values[2]! || values[1]! >= values[3]!) {
        throw CliFailure(
          exitUsage,
          '--viewport requires left < right and top < bottom.',
        );
      }
      final bounds = Bounds2(values[0]!, values[1]!, values[2]!, values[3]!);
      if (!bounds.isValid) {
        throw CliFailure(
          exitUsage,
          '--viewport must have positive width and height.',
        );
      }
      return bounds;
    }
    final bounds = document.contentBounds;
    if (bounds == null) {
      throw CliFailure(
        exitUsage,
        'Document has no bounded geometry; specify --viewport=left,top,right,bottom.',
      );
    }
    final margin = math.max(bounds.width, bounds.height) * 0.08;
    final safeMargin = margin > 0 ? margin : 1.0;
    final expanded = bounds.inflate(safeMargin);
    if (expanded.width <= 0 || expanded.height <= 0) {
      throw CliFailure(
        exitUsage,
        'Could not infer a non-degenerate GIF viewport.',
      );
    }
    return expanded;
  }
}

class McpServeCommand extends Command<int> {
  McpServeCommand(this.globals);

  final CliGlobals globals;

  @override
  String get name => 'mcp-serve';

  @override
  String get description => globals.t(
    '启动 MCP stdio 白名单服务',
    'Start the allow-listed MCP stdio server',
  );

  @override
  Future<int> run() async {
    // Imported lazily to keep the ordinary CLI free of MCP state.
    final server = await createMcpServer(globals);
    await server.serve();
    return exitSuccess;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
