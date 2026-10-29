// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/ai/ai_api_client.dart';
import 'package:moesketchpad/ai/tool_executor.dart';
import 'package:moesketchpad/bloc/ai_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

class _MemoryAiSettings implements AiSettingsStore {
  final values = <String, String>{};

  @override
  Future<String?> readEndpoint() async => values['endpoint'];

  @override
  Future<String?> readModel() async => values['model'];

  @override
  Future<String?> readApiKey() async => values['key'];

  @override
  Future<void> writeEndpoint(String value) async => values['endpoint'] = value;

  @override
  Future<void> writeModel(String value) async => values['model'] = value;

  @override
  Future<void> writeApiKey(String value) async => values['key'] = value;

  @override
  Future<void> deleteApiKey() async => values.remove('key');
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handle);

  final Future<ResponseBody> Function(RequestOptions options) handle;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handle(options);

  @override
  void close({bool force = false}) {}
}

Dio _dio(Future<ResponseBody> Function(RequestOptions options) handle) {
  final dio = Dio();
  dio.httpClientAdapter = _MockAdapter(handle);
  return dio;
}

ResponseBody _jsonResponse(Object body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  final document = GeometryDocument(objects: const []);

  test(
    'Dio client sends credentials, tools, and previews a JSON proposal',
    () async {
      final settings = _MemoryAiSettings();
      RequestOptions? sentRequest;
      final apiClient = AiApiClient(
        dio: _dio((request) async {
          sentRequest = request;
          expect(request.followRedirects, isFalse);
          return _jsonResponse({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'summary': 'A point',
                    'objects': [
                      {
                        'id': 'ai-point-1',
                        'kind': 'point',
                        'points': [
                          {'x': 1, 'y': 2},
                        ],
                        'label': 'A',
                      },
                    ],
                  }),
                },
              },
            ],
          });
        }),
      );
      final bloc = AiBloc(apiClient: apiClient, settings: settings);
      await bloc.loadSettings();
      expect(
        await bloc.saveSettings(
          endpoint: 'http://localhost:8080/v1/',
          model: 'test-model',
          apiKey: 'test-secret',
        ),
        isTrue,
      );

      await bloc.sendPrompt('Create a point A.', document);

      expect(sentRequest?.uri.path, '/v1/chat/completions');
      expect(sentRequest?.headers['Authorization'], 'Bearer test-secret');
      final requestBody =
          jsonDecode(sentRequest!.data as String) as Map<String, dynamic>;
      expect(requestBody['model'], 'test-model');
      expect(requestBody['stream'], isTrue);
      expect(requestBody['tools'], isNotEmpty);
      expect(bloc.state.preview?.addedObjects, 1);
      expect(bloc.state.preview?.document.objects.single.label, 'A');
      expect(bloc.state.applied, isFalse);
      expect(document.objects, isEmpty);
      await bloc.close();
    },
  );

  test('Dio SSE parser assembles streamed function calls', () async {
    final client = AiApiClient(
      dio: _dio((request) async {
        final sse = [
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call-1',
                      'function': {
                        'name': 'create_geometry',
                        'arguments': '{"summary":"Create","objects":[',
                      },
                    },
                  ],
                },
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {
                        'arguments':
                            '{"id":"p1","kind":"point","points":[{"x":0,"y":0}]}]}',
                      },
                    },
                  ],
                },
              },
            ],
          },
          '[DONE]',
        ];
        final content = sse
            .map(
              (event) => event == '[DONE]'
                  ? 'data: [DONE]\n\n'
                  : 'data: ${jsonEncode(event)}\n\n',
            )
            .join();
        return ResponseBody.fromString(
          content,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream'],
          },
        );
      }),
    );
    final completion = await client.complete(
      endpoint: Uri.parse('https://api.example.com/v1/chat/completions'),
      model: 'test',
      apiKey: 'secret',
      messages: const [],
    );
    expect(completion.toolCalls, hasLength(1));
    expect(completion.toolCalls.single.name, 'create_geometry');
    final proposal =
        jsonDecode(ToolExecutor().toProposal(completion.toolCalls))
            as Map<String, dynamic>;
    expect(proposal['objects'], hasLength(1));
  });

  test('ToolExecutor rejects arbitrary tool names', () {
    expect(
      () => ToolExecutor().toProposal([
        const AiToolCall(name: 'run_shell', arguments: '{}'),
      ]),
      throwsFormatException,
    );
  });

  test('repairs incomplete model geometry exactly once', () async {
    final settings = _MemoryAiSettings()
      ..values.addAll({
        'endpoint': 'http://localhost:8080/v1',
        'model': 'test-model',
        'key': 'test-secret',
      });
    var requests = 0;
    final bloc = AiBloc(
      apiClient: AiApiClient(
        dio: _dio((request) async {
          requests++;
          final body = jsonDecode(request.data as String) as Map;
          final messages = body['messages'] as List;
          final content = requests == 1
              ? {
                  'summary': 'A point',
                  'objects': [
                    {'id': 'p1'},
                  ],
                }
              : {
                  'summary': 'A point',
                  'objects': [
                    {
                      'id': 'p1',
                      'kind': 'point',
                      'points': [
                        {'x': 1, 'y': 2},
                      ],
                    },
                  ],
                };
          if (requests == 2) {
            expect(messages, hasLength(4));
            expect(messages.last['content'], contains('must include'));
          }
          return _jsonResponse({
            'choices': [
              {
                'message': {'content': jsonEncode(content)},
              },
            ],
          });
        }),
      ),
      settings: settings,
    );
    await bloc.loadSettings();
    await bloc.sendPrompt('Create a point.', document);
    expect(requests, 2);
    expect(bloc.state.preview?.addedObjects, 1);
    expect(bloc.state.error, isNull);
    await bloc.close();
  });

  test(
    'provider errors redact credentials and reject insecure endpoints',
    () async {
      final settings = _MemoryAiSettings()
        ..values.addAll({
          'endpoint': 'http://localhost:8080/v1',
          'model': 'test-model',
          'key': 'private-secret',
        });
      final bloc = AiBloc(
        apiClient: AiApiClient(
          dio: _dio(
            (_) async => _jsonResponse({
              'error': {'message': 'invalid private-secret'},
            }, status: 401),
          ),
        ),
        settings: settings,
      );
      await bloc.loadSettings();
      await bloc.sendPrompt('Create a point.', document);
      expect(bloc.state.error, contains('[redacted]'));
      expect(bloc.state.error, isNot(contains('private-secret')));
      expect(bloc.state.preview, isNull);
      expect(
        await bloc.saveSettings(
          endpoint: 'http://example.com/v1',
          model: 'model',
          apiKey: 'never-store-this',
        ),
        isFalse,
      );
      await bloc.close();
    },
  );
}
