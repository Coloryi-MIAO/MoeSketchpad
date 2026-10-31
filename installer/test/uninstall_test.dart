// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad_installer/install_manifest.dart';
import 'package:moesketchpad_installer/uninstaller.dart';

void main() {
  group('InstallManifest round-trips', () {
    test('write then load', () async {
      final dir = await Directory.systemTemp.createTemp('moesp_manifest');
      final manifest = InstallManifest(
        installDir: dir.path,
        appVersion: '1.0.0',
        buildNumber: 42,
        languageCode: 'zh',
        registeredPath: true,
        desktopShortcut: true,
        startMenuShortcut: false,
      );
      await InstallManifest.writeTo(dir.path, manifest);
      final loaded = await InstallManifest.load(dir.path);
      expect(loaded, isNotNull);
      expect(loaded!.installDir, dir.path);
      expect(loaded.appVersion, '1.0.0');
      expect(loaded.buildNumber, 42);
      expect(loaded.languageCode, 'zh');
      expect(loaded.registeredPath, isTrue);
      expect(loaded.desktopShortcut, isTrue);
      expect(loaded.startMenuShortcut, isFalse);
      await dir.delete(recursive: true);
    });
  });

  group('Uninstaller', () {
    test('emits steps in order and completes', () async {
      final dir = await Directory.systemTemp.createTemp('moesp_uninstall');
      final manifest = InstallManifest(
        installDir: dir.path,
        appVersion: '1.0.0',
        buildNumber: 1,
        languageCode: 'en',
        registeredPath: false,
        desktopShortcut: false,
        startMenuShortcut: false,
      );
      await InstallManifest.writeTo(dir.path, manifest);

      final steps = <UninstallStep>[];
      final uninstaller = Uninstaller(
        (_) => '',
        onStep: (event) => steps.add(event.step),
      );
      await uninstaller.run(dir.path);

      expect(
        steps,
        containsAllInOrder([
          // Registry + PATH + shortcuts run before the install dir is removed
          // so the running uninstaller exe stays on disk for child processes.
          UninstallStep.removingAssociation,
          UninstallStep.removingShortcuts,
          UninstallStep.removingPath,
          UninstallStep.removingRegistry,
          UninstallStep.removingFiles,
          UninstallStep.complete,
        ]),
      );
      expect(await dir.exists(), isFalse);
      // best-effort: registry deletion may fail under test isolation, that's ok
    });
  });
}
