// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

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
  });

  final String input;
  final AiPreview? preview;
  final String? error;
  final bool applied;
  final bool busy;

  AiState copyWith({
    String? input,
    AiPreview? preview,
    bool clearPreview = false,
    String? error,
    bool clearError = false,
    bool? applied,
    bool? busy,
  }) => AiState(
    input: input ?? this.input,
    preview: clearPreview ? null : (preview ?? this.preview),
    error: clearError ? null : (error ?? this.error),
    applied: applied ?? this.applied,
    busy: busy ?? this.busy,
  );
}

/// AI integration is deliberately transport-free in this build: no model
/// endpoint is bundled and no network request is made. The bloc validates and
/// previews structured proposals, which can come from an MCP-connected client.
class AiBloc extends Cubit<AiState> {
  AiBloc() : super(const AiState());

  String systemPrompt(String language) =>
      moeSketchpadSystemPrompt(language: language);

  void setInput(String value) {
    emit(state.copyWith(input: value, clearError: true, applied: false));
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
