// SPDX-License-Identifier: GPL-3.0-only
/// Shared CLI infrastructure: exit codes, globals, localized output and
/// crash-resistant encrypted document I/O.
library;

import 'dart:convert';
import 'dart:io';

import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:path/path.dart' as p;

const int exitSuccess = 0;
const int exitGeneric = 1;
const int exitUsage = 2;
const int exitFormat = 3;
const int exitDecrypt = 4;
const int exitUnsatisfied = 5;
const int exitSecurity = 6;

class CliFailure implements Exception {
  const CliFailure(this.exitCode, this.message);
  final int exitCode;
  final String message;
  @override
  String toString() => message;
}

class CliGlobals {
  CliGlobals({
    this.lang = 'zh',
    this.json = false,
    this.file,
    this.passwordEnv = 'MSP_PASSWORD',
    this.workspace,
    this.auditLog,
  });

  final String lang;
  final bool json;
  final String? file;
  final String passwordEnv;
  final String? workspace;
  final String? auditLog;

  bool get english => lang == 'en';
  String t(String zh, String en) => english ? en : zh;

  String? readPassword() {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(passwordEnv)) {
      throw CliFailure(exitUsage, 'Invalid --password-env variable name.');
    }
    final password = Platform.environment[passwordEnv];
    return password == null || password.isEmpty ? null : password;
  }

  String requirePassword() {
    final password = readPassword();
    if (password == null) {
      throw CliFailure(
        exitDecrypt,
        t(
          '需要密码：请通过环境变量 $passwordEnv 提供（不要把密码直接放在命令行）。',
          'Password required: provide it via environment variable $passwordEnv '
              '(never put a password directly on the command line).',
        ),
      );
    }
    return password;
  }
}

({CliGlobals globals, List<String> args}) extractGlobals(List<String> raw) {
  var lang = 'zh';
  var json = false;
  String? file;
  var passwordEnv = 'MSP_PASSWORD';
  String? workspace;
  String? auditLog;
  final args = <String>[];
  String nextValue(int index, String option) {
    if (index + 1 >= raw.length) {
      throw CliFailure(exitUsage, '$option requires a value.');
    }
    return raw[index + 1];
  }

  for (var i = 0; i < raw.length; i++) {
    final value = raw[i];
    if (value == '--json') {
      json = true;
    } else if (value == '--lang') {
      lang = nextValue(i, '--lang');
      i++;
    } else if (value.startsWith('--lang=')) {
      lang = value.substring(7);
    } else if (value == '--file') {
      file = nextValue(i, '--file');
      i++;
    } else if (value.startsWith('--file=')) {
      file = value.substring(7);
    } else if (value == '--password-env') {
      passwordEnv = nextValue(i, '--password-env');
      i++;
    } else if (value.startsWith('--password-env=')) {
      passwordEnv = value.substring(15);
    } else if (value == '--workspace') {
      workspace = nextValue(i, '--workspace');
      i++;
    } else if (value.startsWith('--workspace=')) {
      workspace = value.substring(12);
    } else if (value == '--audit-log') {
      auditLog = nextValue(i, '--audit-log');
      i++;
    } else if (value.startsWith('--audit-log=')) {
      auditLog = value.substring(12);
    } else {
      args.add(value);
    }
  }
  if (lang != 'zh' && lang != 'en') {
    throw const CliFailure(exitUsage, '--lang must be zh or en.');
  }
  if (file != null && file.trim().isEmpty) {
    throw const CliFailure(exitUsage, '--file requires a non-empty path.');
  }
  return (
    globals: CliGlobals(
      lang: lang,
      json: json,
      file: file,
      passwordEnv: passwordEnv,
      workspace: workspace,
      auditLog: auditLog,
    ),
    args: args,
  );
}

String localizeError(CliFailure failure, CliGlobals? globals) {
  if (globals == null || !globals.json) return failure.message;
  return jsonEncode({
    'ok': false,
    'error': {'code': failure.exitCode, 'message': failure.message},
  });
}

void emit(
  CliGlobals globals, {
  required Object? jsonValue,
  required String text,
}) {
  if (globals.json) {
    stdout.writeln(jsonEncode(jsonValue));
  } else {
    stdout.writeln(text);
  }
}

String? resolveFile(CliGlobals globals, {String? override}) =>
    override ?? globals.file;

Future<GeometryDocument> loadDocument(
  CliGlobals globals, {
  String? path,
  bool requireExisting = true,
  bool allowMissing = false,
}) async {
  final rawPath = resolveFile(globals, override: path);
  if (rawPath == null) {
    if (!requireExisting) {
      return GeometryDocument(objects: []);
    }
    throw CliFailure(
      exitUsage,
      globals.t('缺少 --file <path.moesp>。', 'Missing --file <path.moesp>.'),
    );
  }
  if (p.extension(rawPath).toLowerCase() != '.moesp') {
    throw CliFailure(
      exitFormat,
      globals.t(
        'MoeSketchpad 文档必须使用 .moesp 扩展名。',
        'MoeSketchpad documents must use the .moesp extension.',
      ),
    );
  }
  final file = File(rawPath);
  if (!await file.exists()) {
    if (allowMissing) {
      final title = p.basenameWithoutExtension(rawPath);
      return GeometryDocument(
        objects: [],
        title: title.isEmpty ? 'Untitled-1' : title,
      );
    }
    throw CliFailure(
      exitFormat,
      globals.t('文件不存在：$rawPath', 'File not found: $rawPath'),
    );
  }
  final length = await file.length();
  if (length > 64 * 1024 * 1024) {
    throw CliFailure(
      exitFormat,
      globals.t('文件超过允许的大小限制。', 'File exceeds the permitted size.'),
    );
  }
  final bytes = await file.readAsBytes();
  try {
    return await MspCodec().decode(bytes, password: globals.requirePassword());
  } on MspDecryptionException catch (error) {
    throw CliFailure(exitDecrypt, error.message);
  } on MspFormatException catch (error) {
    throw CliFailure(exitFormat, error.message);
  } on FormatException catch (error) {
    throw CliFailure(exitFormat, error.message);
  }
}

Future<void> saveDocument(
  CliGlobals globals,
  GeometryDocument document, {
  String? path,
  bool compress = true,
}) async {
  final rawPath = resolveFile(globals, override: path);
  if (rawPath == null) {
    throw CliFailure(exitUsage, 'Missing --file path.');
  }
  if (p.extension(rawPath).toLowerCase() != '.moesp') {
    throw CliFailure(exitFormat, 'Refusing to write a non-.moesp file.');
  }
  final password = globals.requirePassword();
  final target = File(rawPath);
  if (await FileSystemEntity.type(target.path) ==
      FileSystemEntityType.directory) {
    throw CliFailure(exitSecurity, 'Refusing to overwrite a directory.');
  }
  await target.parent.create(recursive: true);
  final bytes = await MspCodec().encode(
    document,
    password: password,
    compress: compress,
  );
  final temporary = File(
    '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  final backup = File(
    '${target.path}.bak-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.rename(backup.path);
    }
    await temporary.rename(target.path);
    if (await backup.exists()) await backup.delete();
  } on FileSystemException {
    if (await backup.exists()) {
      if (await target.exists()) await target.delete();
      await backup.rename(target.path);
    }
    rethrow;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

void appendAudit(CliGlobals globals, String event, {bool success = true}) {
  final path = globals.auditLog;
  if (path == null || path.isEmpty) return;
  try {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'event': event,
        'success': success,
        // Arguments and document content are deliberately never logged.
      })}\n',
      mode: FileMode.append,
      flush: true,
    );
  } on FileSystemException {
    // Audit logging failure must not leak content or crash a read-only query;
    // surface it on stderr for the operator.
    stderr.writeln('audit log write failed');
  }
}

/// Canonicalises an existing file and ensures it is inside the workspace root.
/// Used by MCP and other AI-facing entry points; never by ordinary user CLI
/// paths where the user explicitly chooses the file.
Future<File> requireWorkspaceFile(
  String rawPath, {
  required String workspace,
  String? requiredExtension,
  int maxBytes = 64 * 1024 * 1024,
}) async {
  final root = Directory(workspace).absolute;
  if (!await root.exists()) {
    throw const CliFailure(exitSecurity, 'Workspace root does not exist.');
  }
  final rootResolved = await root.resolveSymbolicLinks();
  final file = File(rawPath).absolute;
  if (!await file.exists()) {
    throw const CliFailure(exitFormat, 'File does not exist.');
  }
  final resolved = await file.resolveSymbolicLinks();
  final relative = p.relative(resolved, from: rootResolved);
  if (relative == '..' ||
      relative.startsWith('..${p.separator}') ||
      p.isAbsolute(relative)) {
    throw const CliFailure(
      exitSecurity,
      'Access outside the approved workspace is denied.',
    );
  }
  if (requiredExtension != null &&
      p.extension(resolved).toLowerCase() != requiredExtension) {
    throw const CliFailure(exitFormat, 'File extension is not allowed.');
  }
  final length = await file.length();
  if (length > maxBytes) {
    throw const CliFailure(exitFormat, 'File exceeds the permitted size.');
  }
  return File(resolved);
}
