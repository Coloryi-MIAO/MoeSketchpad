// SPDX-License-Identifier: GPL-3.0-only
/// A deliberately small MCP server exposing only validated, side-effect-free
/// geometry operations. It never shells out and never reads files outside the
/// approved workspace.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:path/path.dart' as p;

import 'cli_support.dart';
import 'primitives.dart';

const String _protocolVersion = '2024-11-05';

Future<McpServer> createMcpServer(CliGlobals globals) async =>
    McpServer(globals);

class McpServer {
  McpServer(this.globals)
    : workspace = p.normalize(
        p.absolute(globals.workspace ?? Directory.current.path),
      );

  final CliGlobals globals;
  final String workspace;
  int _requestSequence = 0;

  String get auditLogPath {
    final raw = globals.auditLog;
    if (raw == null) return p.join(workspace, '.moesketchpad-audit.jsonl');
    if (p.isAbsolute(raw)) return raw;
    return p.normalize(p.join(workspace, raw));
  }

  Future<void> serve() async {
    final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Object? id;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) {
          _send(_error(null, -32600, 'Invalid Request'));
          continue;
        }
        id = decoded['id'];
        await _handle(decoded);
      } on FormatException {
        _send(_error(id, -32700, 'Parse error'));
      } on Object catch (_) {
        _send(_error(id, -32603, 'Internal error'));
      }
    }
  }

  Future<void> _handle(Map<String, dynamic> request) async {
    final method = request['method'];
    final id = request['id'];
    final params = request['params'];
    if (method is! String) {
      _send(_error(id, -32600, 'Invalid Request'));
      return;
    }
    if (id == null) {
      // Notifications (e.g. notifications/initialized) never get a response.
      return;
    }
    switch (method) {
      case 'initialize':
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'protocolVersion': _protocolVersion,
            'capabilities': {
              'tools': {'listChanged': false},
            },
            'serverInfo': {'name': 'moesketchpad-msp', 'version': '0.1.0'},
            'instructions': moeSketchpadSystemPrompt(language: globals.lang),
          },
        });
      case 'ping':
        _send({'jsonrpc': '2.0', 'id': id, 'result': {}});
      case 'tools/list':
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'result': {'tools': _toolDefinitions()},
        });
      case 'tools/call':
        if (params is! Map) {
          _send(_error(id, -32602, 'Invalid params'));
          return;
        }
        final name = params['name'];
        final arguments = params['arguments'] ?? <String, Object?>{};
        if (name is! String || arguments is! Map) {
          _send(_error(id, -32602, 'Invalid params'));
          return;
        }
        final toolName = name;
        _requestSequence++;
        try {
          final result = await _callTool(
            toolName,
            Map<String, Object?>.from(arguments),
          );
          _audit('tool:$toolName', success: true);
          _send({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'content': [
                {
                  'type': 'text',
                  'text': const JsonEncoder.withIndent('  ').convert(result),
                },
              ],
              'isError': false,
            },
          });
        } on _ToolException catch (error) {
          _audit('tool:$toolName', success: false);
          _send({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'content': [
                {'type': 'text', 'text': error.message},
              ],
              'isError': true,
            },
          });
        } on Object catch (error) {
          _audit('tool:$toolName', success: false);
          final safe = error is FormatException
              ? error.message
              : error is PrimitiveException
              ? error.message
              : 'Tool execution failed.';
          _send({
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'content': [
                {'type': 'text', 'text': safe},
              ],
              'isError': true,
            },
          });
        }
      default:
        _send(_error(id, -32601, 'Method not found'));
    }
  }

  Future<Object?> _callTool(String name, Map<String, Object?> arguments) async {
    switch (name) {
      case 'msp_calc':
        final expression = _string(arguments, 'expression', maxLength: 4096);
        final variables = <String, double>{};
        final rawVariables = arguments['variables'];
        if (rawVariables != null) {
          if (rawVariables is! Map) {
            throw const _ToolException('variables must be an object.');
          }
          if (rawVariables.length > 32) {
            throw const _ToolException('Too many variables.');
          }
          for (final entry in rawVariables.entries) {
            final key = entry.key;
            final value = entry.value;
            if (key is! String ||
                !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key) ||
                value is! num ||
                !value.isFinite) {
              throw const _ToolException('Invalid variable.');
            }
            variables[key] = value.toDouble();
          }
        }
        final value = const ExpressionEvaluator().evaluate(
          expression,
          variables: variables,
        );
        return {'ok': true, 'expression': expression, 'value': value};

      case 'msp_create_geometry':
        final primitive = _string(arguments, 'primitive', maxLength: 32);
        final rawOptions = arguments['options'] ?? <String, Object?>{};
        if (rawOptions is! Map || rawOptions.length > 32) {
          throw const _ToolException('options must be a small object.');
        }
        const allowed = {
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
        };
        final options = <String, String>{};
        for (final entry in rawOptions.entries) {
          if (entry.key is! String || !allowed.contains(entry.key)) {
            throw _ToolException('Option "${entry.key}" is not allowed.');
          }
          final value = entry.value;
          if (value is! String || value.length > 4096) {
            throw _ToolException('Option "${entry.key}" must be a string.');
          }
          options[entry.key as String] = value;
        }
        final object = const PrimitiveFactory().build(
          primitive,
          options,
          GeometryDocument(objects: []),
        );
        if (object.points.length > 10000) {
          throw const _ToolException('Too many points.');
        }
        return {'ok': true, 'preview': true, 'object': object.toJson()};

      case 'msp_document_stats':
        final raw = arguments['document'];
        if (raw is! Map) {
          throw const _ToolException('document must be an object.');
        }
        final byteLength = utf8.encode(jsonEncode(raw)).length;
        if (byteLength > 4 * 1024 * 1024) {
          throw const _ToolException('document exceeds 4 MiB.');
        }
        final document = GeometryDocument.fromJson(raw);
        final counts = <String, int>{};
        for (final object in document.objects) {
          counts[object.kind.name] = (counts[object.kind.name] ?? 0) + 1;
        }
        return {
          'ok': true,
          'title': document.title,
          'counts': counts,
          'objects': document.objects.length,
          'constraints': document.constraints.length,
          'measurements': document.measurements.length,
          'animations': document.animations.length,
          'bounds': document.contentBounds?.toJson(),
        };

      case 'msp_measure':
        final rawDocument = arguments['document'];
        if (rawDocument is! Map) {
          throw const _ToolException('document must be an object.');
        }
        if (utf8.encode(jsonEncode(rawDocument)).length > 4 * 1024 * 1024) {
          throw const _ToolException('document exceeds 4 MiB.');
        }
        final document = GeometryDocument.fromJson(rawDocument);
        final rawType = _string(arguments, 'type', maxLength: 32);
        final type = MeasurementType.values
            .where((value) => value.name == rawType)
            .firstOrNull;
        if (type == null) {
          throw const _ToolException('Unknown measurement type.');
        }
        final rawTargets = arguments['targetIds'];
        if (rawTargets is! List ||
            rawTargets.isEmpty ||
            rawTargets.length > 8 ||
            rawTargets.any((value) => value is! String)) {
          throw const _ToolException('targetIds must be a small string array.');
        }
        final units = _string(arguments, 'unit', maxLength: 32);
        final unit = MeasureUnit.values
            .where((value) => value.name == units)
            .firstOrNull;
        if (unit == null) throw const _ToolException('Unknown unit.');
        final measurement = Measurement(
          id: 'mcp-measure',
          type: type,
          targetIds: rawTargets.cast<String>(),
          unit: unit,
        );
        final value = const MeasurementEngine().measure(measurement, document);
        return {
          'ok': true,
          'measurement': measurement.toJson(),
          'value': value.toJson(),
        };

      case 'msp_validate_file':
        final rawPath = _string(arguments, 'path', maxLength: 4096);
        final file = await requireWorkspaceFile(
          p.isAbsolute(rawPath) ? rawPath : p.join(workspace, rawPath),
          workspace: workspace,
          requiredExtension: '.moesp',
        );
        final validation = MspCodec().validate(await file.readAsBytes());
        return {'ok': true, ...validation.toJson()};

      case 'msp_system_prompt':
        final lang = _string(
          arguments,
          'lang',
          maxLength: 2,
          optional: true,
          fallback: globals.lang,
        );
        if (lang != 'zh' && lang != 'en') {
          throw const _ToolException('lang must be zh or en.');
        }
        return {
          'ok': true,
          'lang': lang,
          'prompt': moeSketchpadSystemPrompt(language: lang),
        };

      default:
        throw _ToolException('Unknown or disallowed tool "$name".');
    }
  }

  List<Map<String, Object?>> _toolDefinitions() => [
    {
      'name': 'msp_calc',
      'description':
          'Safely evaluate a bounded pure-Dart mathematical expression. No shell.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'expression': {'type': 'string', 'maxLength': 4096},
          'variables': {
            'type': 'object',
            'additionalProperties': {'type': 'number'},
          },
        },
        'required': ['expression'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'msp_create_geometry',
      'description':
          'Return a preview geometry object. Writes nothing; the user must approve.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'primitive': {
            'type': 'string',
            'enum': [
              'point',
              'segment',
              'line',
              'ray',
              'circle',
              'arc',
              'triangle',
              'polygon',
              'conic',
              'function',
              'vector',
              'coordinate',
              'solid',
            ],
          },
          'options': {
            'type': 'object',
            'additionalProperties': {'type': 'string'},
          },
        },
        'required': ['primitive'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'msp_document_stats',
      'description':
          'Read-only validation and summary of an inline MoeSketchpad document object.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'document': {'type': 'object'},
        },
        'required': ['document'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'msp_measure',
      'description':
          'Compute one dynamic measurement against an inline document. No writes.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'document': {'type': 'object'},
          'type': {
            'type': 'string',
            'enum': [
              'length',
              'arcLength',
              'angle',
              'area',
              'slope',
              'functionValue',
            ],
          },
          'targetIds': {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
            'maxItems': 8,
          },
          'unit': {
            'type': 'string',
            'enum': ['unitless', 'cm', 'mm', 'px', 'custom'],
          },
        },
        'required': ['document', 'type', 'targetIds', 'unit'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'msp_validate_file',
      'description':
          'Validate the structural header of an .moesp file inside the approved workspace.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'maxLength': 4096},
        },
        'required': ['path'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'msp_system_prompt',
      'description':
          'Return the immutable MoeSketchpad assistant system prompt.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'lang': {
            'type': 'string',
            'enum': ['zh', 'en'],
          },
        },
        'additionalProperties': false,
      },
    },
  ];

  String _string(
    Map<String, Object?> arguments,
    String key, {
    required int maxLength,
    bool optional = false,
    String? fallback,
  }) {
    final value = arguments[key];
    if (value == null) {
      if (optional) return fallback ?? '';
      throw _ToolException('Missing string argument "$key".');
    }
    if (value is! String || value.isEmpty || value.length > maxLength) {
      throw _ToolException('Argument "$key" is invalid.');
    }
    return value;
  }

  void _send(Map<String, Object?> payload) {
    final encoded = jsonEncode(payload);
    if (encoded.length > 8 * 1024 * 1024) {
      stdout.writeln(
        jsonEncode(_error(payload['id'], -32603, 'Response too large')),
      );
      return;
    }
    stdout.writeln(encoded);
  }

  Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  void _audit(String event, {required bool success}) {
    try {
      final file = File(auditLogPath);
      final rootResolved = Directory(workspace).resolveSymbolicLinksSync();
      var ancestor = Directory(file.parent.path);
      while (!ancestor.existsSync()) {
        final parent = ancestor.parent;
        if (parent.path == ancestor.path) {
          throw const FileSystemException('No existing audit parent.');
        }
        ancestor = parent;
      }
      final resolvedAncestor = ancestor.resolveSymbolicLinksSync();
      final missingParent = p.relative(
        file.parent.absolute.path,
        from: ancestor.absolute.path,
      );
      final candidateParent = p.normalize(
        p.join(resolvedAncestor, missingParent),
      );
      final lexicalCandidate = p.join(candidateParent, p.basename(file.path));
      if (!p.isWithin(rootResolved, lexicalCandidate)) return;
      file.parent.createSync(recursive: true);
      final parentResolved = Directory(
        file.parent.path,
      ).resolveSymbolicLinksSync();
      final candidatePath = p.join(parentResolved, p.basename(file.path));
      final resolvedPath = file.existsSync()
          ? file.resolveSymbolicLinksSync()
          : candidatePath;
      if (!p.isWithin(rootResolved, resolvedPath)) {
        return;
      }
      final target = File(resolvedPath);
      target.writeAsStringSync(
        '${jsonEncode({'timestamp': DateTime.now().toUtc().toIso8601String(), 'request': _requestSequence, 'event': event, 'success': success})}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      stderr.writeln('MCP audit log write failed.');
    }
  }
}

class _ToolException implements Exception {
  const _ToolException(this.message);
  final String message;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
