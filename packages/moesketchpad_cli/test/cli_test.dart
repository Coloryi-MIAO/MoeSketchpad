// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> msp(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'bin/msp.dart', ...args],
  workingDirectory: Directory.current.path,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

void main() {
  test('help succeeds', () async {
    final result = await msp(['help', '--lang', 'en']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('Usage: msp'));
  });

  test('calc emits JSON and rejects invalid input', () async {
    final ok = await msp(['calc', 'sqrt(3^2+4^2)', '--json']);
    expect(ok.exitCode, 0);
    expect((jsonDecode(ok.stdout as String) as Map)['value'], 5);
    final bad = await msp(['calc', '1/0', '--json']);
    expect(bad.exitCode, 2);
  });

  test('triangle shorthand and canonical forms match', () async {
    final shorthand = await msp([
      'create',
      '--triangle-90-3*4*5-5/180',
      '--json',
    ]);
    final canonical = await msp([
      'create',
      'triangle',
      '--type=right',
      '--sides=3,4,5',
      '--hypotenuse=5',
      '--rotation=180',
      '--json',
    ]);
    expect(shorthand.exitCode, 0);
    expect(canonical.exitCode, 0);
    expect(
      (jsonDecode(shorthand.stdout as String) as Map)['object'],
      (jsonDecode(canonical.stdout as String) as Map)['object'],
    );
  });

  test('unsolvable triangle exits 5 and malformed usage exits 2', () async {
    final unsolvable = await msp([
      'create',
      '--triangle-90-2*3*4-4/0',
      '--json',
    ]);
    expect(unsolvable.exitCode, 5);
    final malformed = await msp(['create', 'nope', '--json']);
    expect(malformed.exitCode, 2);
  });

  test(
    'file writes require an environment password and keep JSON on stdout',
    () async {
      final directory = await Directory.systemTemp.createTemp('msp-cli-');
      addTearDown(() => directory.delete(recursive: true));
      final filePath = '${directory.path}${Platform.pathSeparator}draft.msp';
      final missingPassword = await msp([
        'create',
        'point',
        '--x=1',
        '--y=2',
        '--file',
        filePath,
        '--json',
      ]);
      expect(missingPassword.exitCode, 4);
      expect(missingPassword.stdout, isEmpty);
      expect(missingPassword.stderr, isNot(contains('secret')));

      final saved = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          'bin/msp.dart',
          'create',
          'point',
          '--x=1',
          '--y=2',
          '--file',
          filePath,
          '--json',
        ],
        workingDirectory: Directory.current.path,
        environment: {...Platform.environment, 'MSP_PASSWORD': 'test-secret'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(saved.exitCode, 0);
      expect(jsonDecode(saved.stdout as String), containsPair('ok', true));
      expect(saved.stderr, isEmpty);
      expect(await File(filePath).exists(), isTrue);
    },
  );

  test('MCP stdio restricts tools and workspace file access', () async {
    final directory = await Directory.systemTemp.createTemp('msp-mcp-');
    addTearDown(() => directory.delete(recursive: true));
    final workspace = Directory('${directory.path}/workspace');
    await workspace.create();
    final outsideFile = File('${directory.path}/outside.msp');
    await outsideFile.writeAsString('not a document');

    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/msp.dart',
      'mcp-serve',
      '--workspace',
      workspace.path,
      '--audit-log',
      '.audit.jsonl',
    ], workingDirectory: Directory.current.path);
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();
    for (final request in [
      {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'},
      {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
      {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'run_shell',
          'arguments': {'command': 'whoami'},
        },
      },
      {
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {
          'name': 'msp_validate_file',
          'arguments': {'path': '../outside.msp'},
        },
      },
    ]) {
      process.stdin.writeln(jsonEncode(request));
    }
    await process.stdin.close();
    final responses = (await output)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(await process.exitCode, 0);

    final initialized = responses.singleWhere((item) => item['id'] == 1);
    expect(initialized['result']['protocolVersion'], '2024-11-05');
    final tools =
        responses.singleWhere((item) => item['id'] == 2)['result']['tools']
            as List;
    expect(tools.length, 6);
    final disallowed = responses.singleWhere((item) => item['id'] == 3);
    expect(disallowed['result']['isError'], isTrue);
    final escaped = responses.singleWhere((item) => item['id'] == 4);
    expect(escaped['result']['isError'], isTrue);
    expect(await outsideFile.readAsString(), 'not a document');
    final audit = await File('${workspace.path}/.audit.jsonl').readAsString();
    expect(audit, isNot(contains('whoami')));
    expect(audit, isNot(contains('test-secret')));
    expect(audit, contains('msp_validate_file'));
  });
}
