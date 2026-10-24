// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

void main() {
  final document = GeometryDocument(objects: const []);

  test(
    'sends configured OpenAI-compatible request and previews, not applies',
    () async {
      final settings = _MemoryAiSettings();
      http.Request? sentRequest;
      final proposal = jsonEncode({
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
      });
      final client = MockClient((request) async {
        sentRequest = request;
        expect(request.followRedirects, isFalse);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': proposal},
              },
            ],
          }),
          200,
        );
      });
      final bloc = AiBloc(client: client, settings: settings);
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

      expect(sentRequest?.url.path, '/v1/chat/completions');
      expect(sentRequest?.headers['authorization'], 'Bearer test-secret');
      final requestBody = jsonDecode(sentRequest!.body) as Map<String, dynamic>;
      expect(requestBody['model'], 'test-model');
      expect(requestBody['messages'], hasLength(2));
      expect(bloc.state.preview?.addedObjects, 1);
      expect(bloc.state.preview?.document.objects.single.label, 'A');
      expect(bloc.state.applied, isFalse);
      expect(document.objects, isEmpty);

      await bloc.close();
    },
  );

  test('rejects insecure remote endpoints before storing a key', () async {
    final settings = _MemoryAiSettings();
    var requestCount = 0;
    final bloc = AiBloc(
      client: MockClient((_) async {
        requestCount++;
        return http.Response('{}', 200);
      }),
      settings: settings,
    );
    await bloc.loadSettings();

    expect(
      await bloc.saveSettings(
        endpoint: 'http://example.com/v1',
        model: 'model',
        apiKey: 'never-store-this',
      ),
      isFalse,
    );
    expect(settings.values, isEmpty);

    await bloc.close();
    expect(requestCount, 0);
  });

  test('requires HTTPS and rejects credentials, query and fragments', () async {
    final settings = _MemoryAiSettings();
    final bloc = AiBloc(
      client: MockClient((_) async => http.Response('{}', 200)),
      settings: settings,
    );
    await bloc.loadSettings();

    for (final endpoint in [
      'https://user:pass@example.com/v1',
      'https://example.com/v1?token=secret',
      'https://example.com/v1#fragment',
      'file:///tmp/config',
    ]) {
      expect(
        await bloc.saveSettings(
          endpoint: endpoint,
          model: 'test-model',
          apiKey: 'test-secret',
        ),
        isFalse,
        reason: endpoint,
      );
    }
    expect(settings.values, isEmpty);
    await bloc.close();
  });

  test('keeps malformed model output out of the document preview', () async {
    final settings = _MemoryAiSettings()
      ..values.addAll({
        'endpoint': 'http://localhost:8080/v1',
        'model': 'test-model',
        'key': 'test-secret',
      });
    final bloc = AiBloc(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'not JSON'},
              },
            ],
          }),
          200,
        ),
      ),
      settings: settings,
    );
    await bloc.loadSettings();

    await bloc.sendPrompt('Create a point.', document);

    expect(bloc.state.preview, isNull);
    expect(bloc.state.error, isNotNull);
    expect(bloc.state.busy, isFalse);
    await bloc.close();
  });

  test('rejects whole-document replacements from the AI endpoint', () async {
    final settings = _MemoryAiSettings()
      ..values.addAll({
        'endpoint': 'http://localhost:8080/v1',
        'model': 'test-model',
        'key': 'test-secret',
      });
    final bloc = AiBloc(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'format': 'moesketchpad-document',
                    'objects': [],
                  }),
                },
              },
            ],
          }),
          200,
        ),
      ),
      settings: settings,
    );
    await bloc.loadSettings();

    await bloc.sendPrompt('Create a point.', document);

    expect(bloc.state.preview, isNull);
    expect(bloc.state.error, contains('additive proposal'));
    await bloc.close();
  });

  test('redacts an API key if the provider echoes it in an error', () async {
    final settings = _MemoryAiSettings()
      ..values.addAll({
        'endpoint': 'http://localhost:8080/v1',
        'model': 'test-model',
        'key': 'private-secret',
      });
    final bloc = AiBloc(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'invalid key private-secret'},
          }),
          401,
        ),
      ),
      settings: settings,
    );
    await bloc.loadSettings();

    await bloc.sendPrompt('Create a point.', document);

    expect(bloc.state.error, contains('[redacted]'));
    expect(bloc.state.error, isNot(contains('private-secret')));
    expect(bloc.state.preview, isNull);
    await bloc.close();
  });

  test('deletes API key without exposing it in bloc state', () async {
    final settings = _MemoryAiSettings()
      ..values.addAll({
        'endpoint': 'https://api.example.com/v1',
        'model': 'model',
        'key': 'private-key',
      });
    final bloc = AiBloc(
      client: MockClient((_) async => http.Response('{}', 200)),
      settings: settings,
    );
    await bloc.loadSettings();

    expect(bloc.state.apiKeyConfigured, isTrue);
    expect(bloc.state.toString(), isNot(contains('private-key')));
    expect(
      await bloc.saveSettings(
        endpoint: bloc.state.endpoint,
        model: bloc.state.model,
        clearApiKey: true,
      ),
      isTrue,
    );
    expect(bloc.state.apiKeyConfigured, isFalse);
    expect(settings.values.containsKey('key'), isFalse);
    await bloc.close();
  });
}
