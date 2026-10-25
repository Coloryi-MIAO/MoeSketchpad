// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';

import '../ai/ai_api_client.dart';
import '../ai/tool_executor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiPreview {
  const AiPreview({
    required this.document,
    required this.summary,
    required this.addedObjects,
  });
  final GeometryDocument document;
  final String summary;
  final int addedObjects;
}

class AiState {
  const AiState({
    this.input = '',
    this.preview,
    this.error,
    this.applied = false,
    this.busy = false,
    this.endpoint = 'https://api.openai.com/v1',
    this.model = '',
    this.settingsLoaded = false,
    this.apiKeyConfigured = false,
  });

  final String input;
  final AiPreview? preview;
  final String? error;
  final bool applied;
  final bool busy;
  final String endpoint;
  final String model;
  final bool settingsLoaded;
  final bool apiKeyConfigured;

  AiState copyWith({
    String? input,
    AiPreview? preview,
    bool clearPreview = false,
    String? error,
    bool clearError = false,
    bool? applied,
    bool? busy,
    String? endpoint,
    String? model,
    bool? settingsLoaded,
    bool? apiKeyConfigured,
  }) => AiState(
    input: input ?? this.input,
    preview: clearPreview ? null : (preview ?? this.preview),
    error: clearError ? null : (error ?? this.error),
    applied: applied ?? this.applied,
    busy: busy ?? this.busy,
    endpoint: endpoint ?? this.endpoint,
    model: model ?? this.model,
    settingsLoaded: settingsLoaded ?? this.settingsLoaded,
    apiKeyConfigured: apiKeyConfigured ?? this.apiKeyConfigured,
  );
}

abstract interface class AiSettingsStore {
  Future<String?> readEndpoint();
  Future<String?> readModel();
  Future<String?> readApiKey();
  Future<void> writeEndpoint(String value);
  Future<void> writeModel(String value);
  Future<void> writeApiKey(String value);
  Future<void> deleteApiKey();
}

class SecureAiSettingsStore implements AiSettingsStore {
  SecureAiSettingsStore({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secureStorage = secureStorage;

  static const _endpointKey = 'ai.endpoint';
  static const _modelKey = 'ai.model';
  static const _apiKey = 'ai.api-key';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> readEndpoint() async =>
      (await SharedPreferences.getInstance()).getString(_endpointKey);

  @override
  Future<String?> readModel() async =>
      (await SharedPreferences.getInstance()).getString(_modelKey);

  @override
  Future<String?> readApiKey() => _secureStorage.read(key: _apiKey);

  @override
  Future<void> writeEndpoint(String value) async =>
      (await SharedPreferences.getInstance()).setString(_endpointKey, value);

  @override
  Future<void> writeModel(String value) async =>
      (await SharedPreferences.getInstance()).setString(_modelKey, value);

  @override
  Future<void> writeApiKey(String value) =>
      _secureStorage.write(key: _apiKey, value: value);

  @override
  Future<void> deleteApiKey() => _secureStorage.delete(key: _apiKey);
}

class AiBloc extends Cubit<AiState> {
  AiBloc({AiApiClient? apiClient, AiSettingsStore? settings})
    : _apiClient = apiClient ?? AiApiClient(),
      _settings = settings ?? SecureAiSettingsStore(),
      super(const AiState()) {
    loadSettings();
  }

  final AiApiClient _apiClient;
  final AiSettingsStore _settings;
  String? _apiKey;

  String systemPrompt(String language) =>
      moeSketchpadSystemPrompt(language: language);

  void setInput(String value) {
    emit(state.copyWith(input: value, clearError: true, applied: false));
  }

  Future<void> loadSettings() async {
    try {
      final values = await Future.wait<String?>([
        _settings.readEndpoint(),
        _settings.readModel(),
        _settings.readApiKey(),
      ]);
      if (isClosed) return;
      final endpoint = values[0];
      final model = values[1];
      _apiKey = values[2];
      emit(
        state.copyWith(
          endpoint: endpoint ?? state.endpoint,
          model: model ?? state.model,
          apiKeyConfigured: _apiKey?.isNotEmpty == true,
          settingsLoaded: true,
        ),
      );
    } on Object catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          settingsLoaded: true,
          error: 'Could not load AI settings: $error',
        ),
      );
    }
  }

  Future<bool> saveSettings({
    required String endpoint,
    required String model,
    String? apiKey,
    bool clearApiKey = false,
  }) async {
    final normalizedEndpoint = endpoint.trim();
    final normalizedModel = model.trim();
    final validationError = _validateEndpoint(normalizedEndpoint);
    if (validationError != null) {
      emit(state.copyWith(error: validationError));
      return false;
    }
    if (normalizedModel.isEmpty || normalizedModel.length > 200) {
      emit(
        state.copyWith(
          error: 'Model name must be between 1 and 200 characters.',
        ),
      );
      return false;
    }
    final newApiKey = apiKey?.trim();
    if (clearApiKey && newApiKey?.isNotEmpty == true) {
      emit(
        state.copyWith(
          error: 'Choose either a new API key or clear the saved key.',
        ),
      );
      return false;
    }
    if (newApiKey != null && newApiKey.length > 4096) {
      emit(state.copyWith(error: 'API key is too long.'));
      return false;
    }
    if (newApiKey?.contains(RegExp(r'[\r\n]')) == true) {
      emit(state.copyWith(error: 'API key contains invalid line breaks.'));
      return false;
    }

    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _settings.writeEndpoint(normalizedEndpoint);
      await _settings.writeModel(normalizedModel);
      if (clearApiKey) {
        await _settings.deleteApiKey();
        _apiKey = null;
      } else if (newApiKey?.isNotEmpty == true) {
        await _settings.writeApiKey(newApiKey!);
        _apiKey = newApiKey;
      }
      if (isClosed) return false;
      emit(
        state.copyWith(
          endpoint: normalizedEndpoint,
          model: normalizedModel,
          apiKeyConfigured: _apiKey?.isNotEmpty == true,
          busy: false,
          clearError: true,
        ),
      );
      return true;
    } on Object catch (error) {
      if (isClosed) return false;
      emit(
        state.copyWith(
          busy: false,
          error: 'Could not save AI settings: $error',
        ),
      );
      return false;
    }
  }

  Future<void> sendPrompt(
    String prompt,
    GeometryDocument current, {
    String language = 'zh',
  }) async {
    final userPrompt = prompt.trim();
    if (userPrompt.isEmpty) {
      emit(state.copyWith(error: 'Describe the geometry you want to create.'));
      return;
    }
    if (userPrompt.length > 12000) {
      emit(
        state.copyWith(error: 'Prompt is too long (maximum 12000 characters).'),
      );
      return;
    }
    final validationError = _validateEndpoint(state.endpoint);
    if (validationError != null) {
      emit(state.copyWith(error: validationError));
      return;
    }
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      emit(state.copyWith(error: 'Save an API key in AI settings first.'));
      return;
    }
    if (state.model.trim().isEmpty) {
      emit(state.copyWith(error: 'Set a model name in AI settings first.'));
      return;
    }

    emit(
      state.copyWith(
        input: userPrompt,
        busy: true,
        clearError: true,
        clearPreview: true,
      ),
    );
    try {
      final uri = _completionUri(state.endpoint);
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt(language)},
        {'role': 'user', 'content': userPrompt},
      ];
      var completion = await _apiClient.complete(
        endpoint: uri,
        model: state.model.trim(),
        apiKey: apiKey,
        messages: messages,
      );
      String proposalFor(AiCompletion value) => value.toolCalls.isNotEmpty
          ? ToolExecutor().toProposal(value.toolCalls)
          : _extractJsonProposal(value.content);
      late String proposal;
      try {
        proposal = proposalFor(completion);
      } on FormatException catch (error) {
        final invalidOutput = completion.toolCalls.isEmpty
            ? completion.content
            : jsonEncode({
                'tool_calls': [
                  for (final call in completion.toolCalls)
                    {'name': call.name, 'arguments': call.arguments},
                ],
              });
        completion = await _apiClient.complete(
          endpoint: uri,
          model: state.model.trim(),
          apiKey: apiKey,
          messages: [
            ...messages,
            {'role': 'assistant', 'content': invalidOutput},
            {
              'role': 'user',
              'content':
                  'Correct the previous response so it can be imported. '
                  'Validation error: ${error.message}. Return only one JSON '
                  'object with summary and objects. Every object must include '
                  'a unique string id, a supported string kind, and a points '
                  'array of numeric {x,y} coordinates. Do not omit required '
                  'fields, add prose, or use Markdown fences.',
            },
          ],
        );
        proposal = proposalFor(completion);
      }
      preview(proposal, current);
    } on Object catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          busy: false,
          error: error is FormatException
              ? error.message
              : error is AiRequestException
              ? error.message
              : 'AI request failed.',
        ),
      );
    }
  }

  static String? _validateEndpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return 'Enter a valid HTTP(S) API base URL without credentials, query, or fragment.';
    }
    final localHost = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(uri.host);
    if (uri.scheme == 'http' && !localHost) {
      return 'Use HTTPS for non-local AI endpoints.';
    }
    return null;
  }

  static Uri _completionUri(String endpoint) {
    final base = Uri.parse(endpoint.trim());
    final path = base.path.replaceFirst(RegExp(r'/+$'), '');
    final completionPath = path.endsWith('/chat/completions')
        ? path
        : '$path/chat/completions';
    return base.replace(
      path: completionPath.isEmpty ? '/chat/completions' : completionPath,
    );
  }

  static String _extractJsonProposal(String content) {
    var candidate = content.trim();
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (fenced != null) candidate = fenced.group(1)!.trim();
    final decoded = jsonDecode(candidate);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] == 'moesketchpad-document' ||
        decoded['objects'] is! List) {
      throw const FormatException(
        'AI must return an additive proposal with an objects array.',
      );
    }
    final objects = decoded['objects'] as List;
    for (var index = 0; index < objects.length; index++) {
      final object = objects[index];
      if (object is! Map ||
          object['id'] is! String ||
          object['kind'] is! String ||
          object['points'] is! List) {
        throw FormatException(
          'Object ${index + 1} must include id, kind, and points.',
        );
      }
      GeometryObject.fromJson(object);
    }
    return candidate;
  }

  void preview(String source, GeometryDocument current) {
    emit(state.copyWith(busy: true, clearError: true, applied: false));
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Proposal must be a JSON object.');
      }
      final map = Map<String, Object?>.from(decoded);
      late GeometryDocument candidate;
      late int addedObjects;
      if (map['format'] == 'moesketchpad-document') {
        candidate = GeometryDocument.fromJson(map);
        addedObjects = candidate.objects.length;
      } else {
        final rawObjects = map['objects'];
        if (rawObjects is! List) {
          throw const FormatException(
            'Proposal needs an "objects" array or a full document.',
          );
        }
        final added = [
          for (final item in rawObjects) GeometryObject.fromJson(item),
        ];
        final rawConstraints = map['constraints'];
        final rawMeasurements = map['measurements'];
        final rawAnimations = map['animations'];
        candidate = current.copyWith(
          objects: [...current.objects, ...added],
          constraints: [
            ...current.constraints,
            if (rawConstraints is List)
              for (final item in rawConstraints) Constraint.fromJson(item),
          ],
          measurements: [
            ...current.measurements,
            if (rawMeasurements is List)
              for (final item in rawMeasurements) Measurement.fromJson(item),
          ],
          animations: [
            ...current.animations,
            if (rawAnimations is List)
              for (final item in rawAnimations) AnimationSpec.fromJson(item),
          ],
        );
        addedObjects = added.length;
      }
      final summary = map['summary'] is String
          ? map['summary'] as String
          : 'AI proposal';
      emit(
        state.copyWith(
          preview: AiPreview(
            document: candidate,
            summary: summary,
            addedObjects: addedObjects,
          ),
          busy: false,
        ),
      );
    } on FormatException catch (error) {
      emit(state.copyWith(error: error.message, busy: false));
    } on Object catch (error) {
      emit(
        state.copyWith(
          error: error is Exception ? '$error' : 'Invalid proposal.',
          busy: false,
        ),
      );
    }
  }

  void markApplied() {
    emit(state.copyWith(clearPreview: true, applied: true, busy: false));
  }

  void discard() {
    emit(state.copyWith(clearPreview: true, clearError: true));
  }
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}
