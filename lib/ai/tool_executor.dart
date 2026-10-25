// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';

import 'ai_api_client.dart';

class ToolExecutor {
  static const _allowedTools = {'create_geometry'};

  String toProposal(List<AiToolCall> calls) {
    if (calls.isEmpty) {
      throw const FormatException('AI returned no allow-listed tool call.');
    }
    final objects = <Object?>[];
    String? summary;
    for (final call in calls) {
      if (!_allowedTools.contains(call.name)) {
        throw FormatException('AI tool "${call.name}" is not allow-listed.');
      }
      final decoded = jsonDecode(call.arguments);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Geometry tool arguments must be an object.',
        );
      }
      final candidateSummary = decoded['summary'];
      final candidateObjects = decoded['objects'];
      if (candidateSummary is! String || candidateObjects is! List) {
        throw const FormatException(
          'Geometry tool requires a summary and objects array.',
        );
      }
      summary ??= candidateSummary;
      objects.addAll(candidateObjects);
    }
    return jsonEncode({'summary': summary, 'objects': objects});
  }
}
