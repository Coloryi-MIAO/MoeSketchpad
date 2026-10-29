// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:moesketchpad_cli/src/cli_support.dart';
import 'package:test/test.dart';

void main() {
  test(
    'workspace file access rejects traversal outside the canonical root',
    () async {
      final directory = await Directory.systemTemp.createTemp('msp-path-');
      addTearDown(() => directory.delete(recursive: true));
      final workspace = Directory('${directory.path}/workspace');
      await workspace.create();
      final outside = File('${directory.path}/outside.moesp');
      await outside.writeAsString('private');

      await expectLater(
        requireWorkspaceFile(
          outside.path,
          workspace: workspace.path,
          requiredExtension: '.moesp',
        ),
        throwsA(
          isA<CliFailure>().having((error) => error.exitCode, 'exitCode', 6),
        ),
      );
    },
  );
}
