// SPDX-License-Identifier: GPL-3.0-only
import 'package:moesketchpad_core/moesketchpad_core.dart';

class DocumentCommandResult {
  const DocumentCommandResult({required this.document, required this.message});

  final GeometryDocument document;
  final String message;
}

class DocumentCommandExecutor {
  const DocumentCommandExecutor();

  DocumentCommandResult execute(String source, GeometryDocument document) {
    final tokens = _tokenize(source);
    if (tokens.isEmpty) throw const FormatException('Enter a moesp command.');
    if (tokens.first == 'moesp') tokens.removeAt(0);
    if (tokens.isEmpty) throw const FormatException('Command is missing.');
    switch (tokens.first) {
      case 'help':
        return DocumentCommandResult(
          document: document,
          message:
              'Commands: create point|segment|circle, label <id>, '
              'constraint tangent-line-circle|tangent-circle-circle, '
              'measure <id>, calc <expression>.',
        );
      case 'create':
        return _create(tokens.skip(1).toList(), document);
      case 'label':
        return _label(tokens.skip(1).toList(), document);
      case 'constraint':
        return _constraint(tokens.skip(1).toList(), document);
      case 'measure':
        return _measure(tokens.skip(1).toList(), document);
      case 'calc':
        return _calculate(tokens.skip(1).join(' '), document);
      default:
        throw FormatException('Unsupported command "${tokens.first}".');
    }
  }

  DocumentCommandResult _create(
    List<String> arguments,
    GeometryDocument document,
  ) {
    if (arguments.isEmpty) {
      throw const FormatException('Usage: moesp create point|segment|circle');
    }
    final kind = arguments.removeAt(0);
    final options = _options(arguments);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    late GeometryObject object;
    switch (kind) {
      case 'point':
        _rejectUnknown(options, {'x', 'y', 'label'});
        final point = Point2(_number(options, 'x'), _number(options, 'y'));
        object = GeometryObject(
          id: 'point-$timestamp',
          kind: GeometryKind.point,
          points: [point],
          label: options['label'],
        );
      case 'segment':
        _rejectUnknown(options, {'x1', 'y1', 'x2', 'y2'});
        object = GeometryObject(
          id: 'segment-$timestamp',
          kind: GeometryKind.segment,
          points: [
            Point2(_number(options, 'x1'), _number(options, 'y1')),
            Point2(_number(options, 'x2'), _number(options, 'y2')),
          ],
        );
      case 'circle':
        _rejectUnknown(options, {'x', 'y', 'radius'});
        final center = Point2(_number(options, 'x'), _number(options, 'y'));
        final radius = _number(options, 'radius');
        if (radius <= 0) {
          throw const FormatException('--radius must be positive.');
        }
        object = GeometryObject(
          id: 'circle-$timestamp',
          kind: GeometryKind.circle,
          points: [center, Point2(center.x + radius, center.y)],
        );
      default:
        throw FormatException('Unsupported create primitive "$kind".');
    }
    final updated = document.withObject(object);
    return DocumentCommandResult(
      document: updated,
      message: 'Created ${object.kind.name} ${object.id}.',
    );
  }

  DocumentCommandResult _label(
    List<String> arguments,
    GeometryDocument document,
  ) {
    if (arguments.length != 2 || !arguments[1].startsWith('--text=')) {
      throw const FormatException('Usage: moesp label <id> --text=<label>');
    }
    final id = arguments.first;
    final text = arguments[1].substring('--text='.length).trim();
    if (text.isEmpty || text.length > 128) {
      throw const FormatException('Label must contain 1 to 128 characters.');
    }
    final object = document.objectById(id);
    if (object == null) throw FormatException('Unknown object "$id".');
    final updated = document.withObject(object.copyWith(label: text));
    return DocumentCommandResult(
      document: updated,
      message: 'Updated label for $id.',
    );
  }

  DocumentCommandResult _constraint(
    List<String> arguments,
    GeometryDocument document,
  ) {
    if (arguments.length < 3) {
      throw const FormatException(
        'Usage: moesp constraint tangent-line-circle|'
        'tangent-circle-circle <id> <id> [--internal]',
      );
    }
    final type = switch (arguments.removeAt(0)) {
      'tangent-line-circle' => ConstraintType.tangentLineCircle,
      'tangent-circle-circle' => ConstraintType.tangentCircleCircle,
      final name => throw FormatException('Unsupported constraint "$name".'),
    };
    final internal = arguments.remove('--internal');
    if (arguments.length != 2) {
      throw const FormatException('Tangency requires exactly two object ids.');
    }
    final constraint = Constraint(
      id: 'constraint-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      targetIds: arguments,
      internalTangency: internal,
    );
    final candidate = document.copyWith(
      constraints: [...document.constraints, constraint],
    );
    final solved = ConstraintSolver(
      tolerance: document.view.geometryTolerance,
    ).solve(candidate);
    if (!solved.converged) {
      throw FormatException(solved.message ?? 'Constraint did not converge.');
    }
    return DocumentCommandResult(
      document: solved.document,
      message: 'Added tangency constraint ${constraint.id}.',
    );
  }

  DocumentCommandResult _measure(
    List<String> arguments,
    GeometryDocument document,
  ) {
    if (arguments.length != 1) {
      throw const FormatException('Usage: moesp measure <object-id>');
    }
    final target = document.objectById(arguments.single);
    if (target == null) {
      throw FormatException('Unknown object "${arguments.single}".');
    }
    final measurement = Measurement(
      id: 'measure-${DateTime.now().microsecondsSinceEpoch}',
      type: MeasurementType.length,
      targetIds: [target.id],
      unit: switch (document.view.unit) {
        'mm' => MeasureUnit.mm,
        'cm' => MeasureUnit.cm,
        'px' => MeasureUnit.px,
        _ => MeasureUnit.unitless,
      },
    );
    final value = const MeasurementEngine().measure(measurement, document);
    final updated = document.copyWith(
      measurements: [...document.measurements, measurement],
    );
    return DocumentCommandResult(
      document: updated,
      message: '${measurement.id}: ${value.display}',
    );
  }

  DocumentCommandResult _calculate(
    String expression,
    GeometryDocument document,
  ) {
    if (expression.isEmpty) {
      throw const FormatException('Usage: moesp calc <expression>');
    }
    final value = Expression.parse(expression).evaluate(const {});
    return DocumentCommandResult(document: document, message: value.toString());
  }

  Map<String, String> _options(List<String> arguments) {
    final result = <String, String>{};
    for (final argument in arguments) {
      if (!argument.startsWith('--') || !argument.contains('=')) {
        throw FormatException('Invalid option "$argument". Use --name=value.');
      }
      final separator = argument.indexOf('=');
      final name = argument.substring(2, separator);
      final value = argument.substring(separator + 1);
      if (name.isEmpty || value.isEmpty || result.containsKey(name)) {
        throw FormatException('Invalid or duplicate option "$name".');
      }
      result[name] = value;
    }
    return result;
  }

  double _number(Map<String, String> options, String name) {
    final value = double.tryParse(options[name] ?? '');
    if (value == null || !value.isFinite) {
      throw FormatException('--$name must be a finite number.');
    }
    return value;
  }

  void _rejectUnknown(Map<String, String> options, Set<String> allowed) {
    final unknown = options.keys.where((name) => !allowed.contains(name));
    if (unknown.isNotEmpty) {
      throw FormatException('Unsupported option "--${unknown.first}".');
    }
  }

  List<String> _tokenize(String source) {
    if (source.length > 2048) {
      throw const FormatException('Command exceeds the 2048 character limit.');
    }
    final tokens = <String>[];
    final token = StringBuffer();
    var quoted = false;
    var escaped = false;
    for (final character in source.trim().runes.map(String.fromCharCode)) {
      if (escaped) {
        token.write(character);
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        quoted = !quoted;
      } else if (character.trim().isEmpty && !quoted) {
        if (token.isNotEmpty) {
          tokens.add(token.toString());
          token.clear();
        }
      } else {
        token.write(character);
      }
    }
    if (quoted || escaped) {
      throw const FormatException('Unterminated quote or escape.');
    }
    if (token.isNotEmpty) tokens.add(token.toString());
    return tokens;
  }
}
