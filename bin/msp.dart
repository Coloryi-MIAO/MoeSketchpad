// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:moesketchpad/core/geometry.dart';
import 'package:moesketchpad/core/msp_codec.dart';

Future<void> main(List<String> args) async {
  try {
    final normalized = _normalizeArgs(args);
    final code = await MspCommandRunner().run(normalized) ?? 0;
    exitCode = code;
  } on CliFailure catch (error) {
    stderr.writeln(error.message);
    exitCode = error.exitCode;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('File operation failed: ${error.message}');
    exitCode = 1;
  } on UsageException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(error.usage);
    exitCode = 2;
  }
}

List<String> _normalizeArgs(List<String> args) {
  final normalized = <String>[];
  final globalLanguage = <String>[];
  var jsonOutput = false;
  for (var i = 0; i < args.length; i++) {
    final value = args[i];
    if (value == '--json') {
      jsonOutput = true;
    } else if (value == '--lang') {
      if (++i >= args.length || !const {'zh', 'en'}.contains(args[i])) {
        throw const FormatException('--lang must be zh or en.');
      }
      globalLanguage
        ..add(value)
        ..add(args[i]);
    } else if (value.startsWith('--lang=')) {
      if (!const {'zh', 'en'}.contains(value.substring(7))) {
        throw const FormatException('--lang must be zh or en.');
      }
      globalLanguage.add(value);
    } else {
      normalized.add(value);
    }
  }
  if (normalized.isNotEmpty && normalized.first == 'create') {
    final shorthandIndex = normalized.indexWhere(
      (value) => value.startsWith('--triangle-'),
    );
    if (shorthandIndex >= 0) {
      final match = RegExp(
        r'^--triangle-([0-9]+)-([0-9]+(?:\.[0-9]+)?)\*([0-9]+(?:\.[0-9]+)?)\*([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?)/([+-]?[0-9]+(?:\.[0-9]+)?)$',
      ).firstMatch(normalized[shorthandIndex]);
      if (match == null || match[1] != '90') {
        throw const FormatException(
          'Triangle shorthand must be --triangle-90-a*b*c-hypotenuse/rotation.',
        );
      }
      normalized
        ..removeAt(shorthandIndex)
        ..addAll([
          'triangle',
          '--type=right',
          '--sides=${match[2]},${match[3]},${match[4]}',
          '--hypotenuse=${match[5]}',
          '--rotation=${match[6]}',
        ]);
    }
  }
  final isHelp = normalized.isEmpty || normalized.first == 'help';
  if (jsonOutput && isHelp) globalLanguage.add('--json');
  if (jsonOutput && !isHelp) normalized.add('--json');
  return [...globalLanguage, ...normalized];
}

class MspCommandRunner extends CommandRunner<int> {
  MspCommandRunner() : super('msp', 'MoeSketchpad geometry CLI') {
    argParser
      ..addOption('lang', allowed: ['zh', 'en'], defaultsTo: 'zh')
      ..addFlag('json', defaultsTo: false);
    addCommand(CalcCommand());
    addCommand(CreateCommand());
    addCommand(ValidateCommand());
  }
}

class CalcCommand extends Command<int> {
  CalcCommand() {
    argParser.addFlag('json', defaultsTo: false);
  }

  @override
  String get name => 'calc';

  @override
  String get description => 'Evaluate a safe mathematical expression.';

  @override
  Future<int> run() async {
    final expression = argResults!.rest.join(' ');
    if (expression.isEmpty) {
      throw const CliFailure(2, 'Usage: msp calc <expression>');
    }
    final value = const ExpressionEvaluator().evaluate(expression);
    if (argResults!['json'] == true) {
      stdout.writeln(jsonEncode({'expression': expression, 'value': value}));
    } else {
      stdout.writeln(value);
    }
    return 0;
  }
}

class CreateCommand extends Command<int> {
  CreateCommand() {
    argParser
      ..addOption('type', defaultsTo: 'right')
      ..addOption('sides')
      ..addOption('hypotenuse')
      ..addOption('rotation', defaultsTo: '0')
      ..addFlag('json', defaultsTo: false);
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a geometry primitive.';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length != 1 || results.rest.single != 'triangle') {
      throw const CliFailure(
        2,
        'Usage: msp create triangle --type=right --sides=3,4,5 '
        '--hypotenuse=5 --rotation=180',
      );
    }
    if (results['type'] != 'right' || results['sides'] == null) {
      throw const CliFailure(2, 'A right triangle and --sides are required.');
    }
    final sides = (results['sides'] as String)
        .split(',')
        .map((value) => double.tryParse(value.trim()))
        .toList();
    final hypotenuse = double.tryParse(results['hypotenuse'] as String? ?? '');
    final rotation = double.tryParse(results['rotation'] as String);
    if (sides.any((side) => side == null) ||
        hypotenuse == null ||
        rotation == null) {
      throw const CliFailure(2, 'Triangle parameters must be numeric.');
    }
    late TriangleSolution triangle;
    try {
      triangle = TriangleSolution.right(
        sides: sides.cast<double>(),
        hypotenuse: hypotenuse,
        rotationDegrees: rotation,
      );
    } on FormatException catch (error) {
      throw CliFailure(5, '${error.message} Try --sides=3,4,5 --hypotenuse=5.');
    }
    if (results['json'] == true) {
      stdout.writeln(jsonEncode(triangle.toJson()));
    } else {
      stdout.writeln(
        'right triangle sides=${triangle.sides.join(',')} '
        'hypotenuse=${triangle.toJson()['hypotenuse']} '
        'rotation=${triangle.rotationDegrees}°',
      );
    }
    return 0;
  }
}

class ValidateCommand extends Command<int> {
  ValidateCommand() {
    argParser.addFlag('json', defaultsTo: false);
  }

  @override
  String get name => 'validate';

  @override
  String get description => 'Validate the structure of an MSP file.';

  @override
  Future<int> run() async {
    final paths = argResults!.rest;
    if (paths.length != 1) {
      throw const CliFailure(2, 'Usage: msp validate <file.msp>');
    }
    final codec = MspCodec();
    late Map<String, Object> result;
    try {
      result = codec.validate(await File(paths.single).readAsBytes());
    } on MspFormatException catch (error) {
      throw CliFailure(3, error.message);
    }
    if (argResults!['json'] == true) {
      stdout.writeln(jsonEncode(result));
    } else {
      stdout.writeln('Valid MSP header (payload authentication not checked).');
    }
    return 0;
  }
}

class CliFailure implements Exception {
  const CliFailure(this.exitCode, this.message);
  final int exitCode;
  final String message;
}
