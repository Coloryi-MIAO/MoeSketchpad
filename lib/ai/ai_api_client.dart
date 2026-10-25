// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';

import 'package:dio/dio.dart';

class AiToolCall {
  const AiToolCall({required this.name, required this.arguments});

  final String name;
  final String arguments;
}

class AiCompletion {
  const AiCompletion({this.content = '', this.toolCalls = const []});

  final String content;
  final List<AiToolCall> toolCalls;
}

class AiRequestException implements Exception {
  const AiRequestException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AiApiClient {
  AiApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  static const _maxBytes = 1024 * 1024;
  final Dio _dio;

  Future<AiCompletion> complete({
    required Uri endpoint,
    required String model,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async {
    try {
      final requestBody = jsonEncode({
        'model': model,
        'stream': true,
        'messages': messages,
        'tools': [_createGeometryTool],
        'tool_choice': 'auto',
      });
      if (utf8.encode(requestBody).length > _maxBytes) {
        throw const FormatException('AI request exceeds the 1 MiB limit.');
      }
      final response = await _dio.postUri<ResponseBody>(
        endpoint,
        data: requestBody,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream, application/json',
          },
          validateStatus: (_) => true,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const FormatException('AI server returned an empty response.');
      }
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > _maxBytes) {
          throw const FormatException('AI response exceeds the 1 MiB limit.');
        }
        bytes.addAll(chunk);
      }
      final text = utf8.decode(bytes);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw AiRequestException(
          _errorMessage(text, response.statusCode ?? 0, apiKey),
        );
      }
      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
          '';
      if (contentType.contains('text/event-stream') ||
          text.startsWith('data:')) {
        return _parseSse(text);
      }
      return _parseJson(text);
    } on DioException catch (error) {
      throw AiRequestException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => 'AI request timed out.',
        DioExceptionType.badCertificate => 'AI endpoint certificate rejected.',
        DioExceptionType.connectionError =>
          'Could not connect to the AI endpoint. Check the URL and CORS policy.',
        _ => 'AI network request failed.',
      });
    }
  }

  AiCompletion _parseJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('AI server returned an invalid response.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const FormatException('AI server response has no message choices.');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) {
      throw const FormatException(
        'AI server response has no assistant message.',
      );
    }
    final content = _readContent(message['content']);
    return AiCompletion(
      content: content,
      toolCalls: _readToolCalls(message['tool_calls']),
    );
  }

  AiCompletion _parseSse(String source) {
    final content = StringBuffer();
    final toolCalls = <int, _ToolCallBuilder>{};
    final eventData = StringBuffer();

    void consumeEvent() {
      final data = eventData.toString().trim();
      eventData.clear();
      if (data.isEmpty || data == '[DONE]') return;
      final event = jsonDecode(data);
      if (event is! Map) {
        throw const FormatException('AI stream contained an invalid event.');
      }
      if (event['error'] != null) {
        throw const FormatException('AI provider reported a stream error.');
      }
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) return;
      final delta = (choices.first as Map)['delta'];
      if (delta is! Map) return;
      final deltaContent = delta['content'];
      if (deltaContent is String) content.write(deltaContent);
      final deltas = delta['tool_calls'];
      if (deltas is! List) return;
      for (final item in deltas) {
        if (item is! Map || item['index'] is! int) continue;
        final builder = toolCalls.putIfAbsent(
          item['index'] as int,
          _ToolCallBuilder.new,
        );
        final id = item['id'];
        final function = item['function'];
        if (id is String) builder.id = id;
        if (function is Map) {
          final name = function['name'];
          final arguments = function['arguments'];
          if (name is String) builder.name.write(name);
          if (arguments is String) builder.arguments.write(arguments);
        }
      }
    }

    for (final line in const LineSplitter().convert(source)) {
      if (line.isEmpty) {
        consumeEvent();
      } else if (line.startsWith('data:')) {
        if (eventData.isNotEmpty) eventData.write('\n');
        eventData.write(line.substring(5).trimLeft());
      }
    }
    consumeEvent();
    final calls = [
      for (final entry
          in toolCalls.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        AiToolCall(
          name: entry.value.name.toString(),
          arguments: entry.value.arguments.toString(),
        ),
    ];
    if (content.isEmpty && calls.isEmpty) {
      throw const FormatException('AI stream returned no content.');
    }
    return AiCompletion(content: content.toString(), toolCalls: calls);
  }

  List<AiToolCall> _readToolCalls(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('AI tool calls are malformed.');
    }
    return [
      for (final call in value)
        if (call is Map &&
            call['function'] is Map &&
            (call['function'] as Map)['name'] is String &&
            (call['function'] as Map)['arguments'] is String)
          AiToolCall(
            name: (call['function'] as Map)['name'] as String,
            arguments: (call['function'] as Map)['arguments'] as String,
          ),
    ];
  }

  String _readContent(Object? value) {
    if (value is String) return value;
    if (value is List) {
      return value
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join('\n');
    }
    return '';
  }

  String _errorMessage(String body, int statusCode, String apiKey) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String && message.isNotEmpty) {
          final safeMessage = message.replaceAll(apiKey, '[redacted]');
          return 'AI server returned HTTP $statusCode: '
              '${safeMessage.substring(0, safeMessage.length.clamp(0, 300))}';
        }
      }
    } on FormatException {
      // Keep provider HTML and raw response bodies out of user-visible errors.
    }
    return 'AI server returned HTTP $statusCode.';
  }
}

const Map<String, Object?> _createGeometryTool = {
  'type': 'function',
  'function': {
    'name': 'create_geometry',
    'description':
        'Propose additive geometry objects for preview. Never executes commands.',
    'parameters': {
      'type': 'object',
      'properties': {
        'summary': {'type': 'string'},
        'objects': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'kind': {
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
              'points': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'x': {'type': 'number'},
                    'y': {'type': 'number'},
                  },
                  'required': ['x', 'y'],
                },
              },
              'label': {'type': 'string'},
              'params': {'type': 'object'},
            },
            'required': ['id', 'kind', 'points'],
          },
        },
      },
      'required': ['summary', 'objects'],
    },
  },
};

class _ToolCallBuilder {
  String? id;
  final StringBuffer name = StringBuffer();
  final StringBuffer arguments = StringBuffer();
}
