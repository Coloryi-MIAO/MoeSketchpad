// SPDX-License-Identifier: GPL-3.0-only
/// Entry point for the `msp` command line interface.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

import 'src/cli_support.dart';
import 'src/commands.dart';

class MspCli {
  const MspCli();

  Future<int> run(List<String> rawArgs) async {
    CliGlobals? globals;
    try {
      final extracted = extractGlobals(rawArgs);
      globals = extracted.globals;
      final args = _normalizeTriangleShorthand(extracted.args);
      if (args.isEmpty || args.first == 'help') {
        return _help(globals, args.skip(1).toList());
      }
      if (args.contains('--help') || args.contains('-h')) {
        final commandName = args.firstWhere(
          (value) => !value.startsWith('-'),
          orElse: () => '',
        );
        return _help(globals, commandName.isEmpty ? [] : [commandName]);
      }
      if (args.first == '--version' || args.first == '-v') {
        if (globals.json) {
          stdout.writeln(
            jsonEncode({
              'name': 'msp',
              'version': '0.1.0',
              'mspFormat': MspCodec.currentVersion,
            }),
          );
        } else {
          stdout.writeln('msp 0.1.0 (MSP format v${MspCodec.currentVersion})');
        }
        return exitSuccess;
      }
      final runner = MspCommandRunner(globals);
      final result = await runner.run(args);
      return result ?? exitSuccess;
    } on CliFailure catch (error) {
      stderr.writeln(localizeError(error, globals));
      return error.exitCode;
    } on UsageException catch (error) {
      stderr
        ..writeln(error.message)
        ..writeln(error.usage);
      return exitUsage;
    } on TriangleSolveException catch (error) {
      final failure = CliFailure(exitUnsatisfied, error.message);
      stderr.writeln(localizeError(failure, globals));
      return failure.exitCode;
    } on FileSystemException catch (error) {
      final failure = CliFailure(
        exitGeneric,
        'File operation failed: ${error.message}',
      );
      stderr.writeln(localizeError(failure, globals));
      return failure.exitCode;
    } on FormatException catch (error) {
      final failure = CliFailure(exitUsage, error.message);
      stderr.writeln(localizeError(failure, globals));
      return failure.exitCode;
    } on Object catch (error) {
      final failure = CliFailure(
        exitGeneric,
        globals?.english == true
            ? 'Unexpected error (${error.runtimeType}).'
            : '发生未预期错误（${error.runtimeType}）。',
      );
      stderr.writeln(localizeError(failure, globals));
      return failure.exitCode;
    }
  }

  List<String> _normalizeTriangleShorthand(List<String> args) {
    final createIndex = args.indexOf('create');
    if (createIndex < 0) return args;
    final shorthandIndex = args.indexWhere(isTriangleShorthand);
    if (shorthandIndex < 0) return args;
    final solution = parseTriangleShorthand(args[shorthandIndex]);
    final normalized = [...args];
    normalized.removeAt(shorthandIndex);
    final spec = solution.spec;
    normalized.insertAll(createIndex + 1, [
      'triangle',
      '--type=${spec.type}',
      '--sides=${spec.sides.map(_formatNumber).join(',')}',
      '--hypotenuse=${_formatNumber(spec.hypotenuse)}',
      '--rotation=${_formatNumber(spec.rotationDegrees)}',
    ]);
    return normalized;
  }

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  int _help(CliGlobals globals, List<String> args) {
    final runner = MspCommandRunner(globals);
    if (args.isEmpty) {
      if (globals.json) {
        stdout.writeln(
          jsonEncode({
            'name': 'msp',
            'usage': runner.usage,
            'commands': [
              for (final entry in runner.commands.entries)
                {'name': entry.key, 'description': entry.value.description},
            ],
          }),
        );
      } else {
        stdout
          ..writeln(globals.t('萌板 / MoeSketchpad 命令行工具', 'MoeSketchpad CLI'))
          ..writeln(runner.usage)
          ..writeln()
          ..writeln(globals.t('命令：', 'Commands:'))
          ..writeln('  help [command]');
        for (final entry in runner.commands.entries) {
          stdout.writeln(
            '  ${entry.key.padRight(14)} ${entry.value.description}',
          );
        }
        stdout
          ..writeln()
          ..writeln(globals.t('全局选项：', 'Global options:'))
          ..writeln('  --lang zh|en       --json')
          ..writeln('  --file <path.moesp>  --password-env MSP_PASSWORD')
          ..writeln('  --workspace <dir>  --audit-log <path>')
          ..writeln()
          ..writeln(
            globals.t(
              '退出码：0 成功，1 通用错误，2 参数错误，3 文件格式错误，'
                  '4 解密/密码错误，5 约束无解，6 权限或安全拒绝。',
              'Exit codes: 0 success, 1 generic, 2 usage, 3 document format, '
                  '4 decryption/password, 5 unsatisfiable, 6 security denial.',
            ),
          );
      }
      return exitSuccess;
    }
    final command = runner.commands[args.first];
    if (command == null) {
      stderr.writeln(
        globals.t(
          '未知命令 "${args.first}"。运行 msp help 查看命令列表。',
          'Unknown command "${args.first}". Run msp help.',
        ),
      );
      return exitUsage;
    }
    if (globals.json) {
      stdout.writeln(
        jsonEncode({
          'name': command.name,
          'description': command.description,
          'usage': command.usage,
        }),
      );
    } else {
      stdout
        ..writeln(command.description)
        ..writeln(command.usage);
    }
    return exitSuccess;
  }
}
