// SPDX-License-Identifier: GPL-3.0-only
/// Reverses an installation performed by [InstallerPage].
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'install_manifest.dart';

/// Steps the uninstaller walks through; the UI drives them one at a time so the
/// progress ring has something concrete to report.
enum UninstallStep {
  removingFiles,
  removingShortcuts,
  removingAssociation,
  removingPath,
  removingRegistry,
  complete,
}

/// Context handed back at each progress tick.
class UninstallProgress {
  const UninstallProgress({
    required this.step,
    required this.status,
    required this.progress,
    this.error,
  });

  final UninstallStep step;
  final String status;
  final double progress;
  final Object? error;
}

/// Callback that maps a step to its localized label.
typedef UninstallStrings = String? Function(UninstallStep);

/// Runs the uninstaller as a state machine. [onStep] is invoked before each
/// step (including the final [UninstallStep.complete]). Per-step failures are
/// reported through [UninstallProgress.error] on the relevant tick and do not
/// abort the run.
class Uninstaller {
  const Uninstaller(
    this._strings, {
    required void Function(UninstallProgress) onStep,
  }) : _onStep = onStep;

  final UninstallStrings _strings;
  final void Function(UninstallProgress) _onStep;

  static const String _arpKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\MoeSketchpad';

  Future<void> run(String installDir) async {
    final directory = Directory(installDir);
    final manifest = await InstallManifest.load(installDir);

    void tick(UninstallStep step, double progress, [Object? error]) {
      _onStep(
        UninstallProgress(
          step: step,
          status: _strings(step) ?? '',
          progress: progress,
          error: error,
        ),
      );
    }

    // 1. Remove the .moesp file association. (Run before touching the install
    //    directory so the running installer exe stays on disk for the child
    //    reg.exe processes that follow.)
    final registeredPath = manifest?.registeredPath ?? false;
    final desktopShortcut = manifest?.desktopShortcut ?? true;
    final startMenuShortcut = manifest?.startMenuShortcut ?? true;

    tick(UninstallStep.removingAssociation, 0.15);
    try {
      await _run('reg.exe', ['delete', r'HKCU\Software\Classes\.moesp', '/f']);
      await _run('reg.exe', [
        'delete',
        r'HKCU\Software\Classes\MoeSketchpad.Document',
        '/f',
      ]);
    } catch (e) {
      tick(UninstallStep.removingAssociation, 0.15, e);
    }

    // 2. Remove shortcuts.
    tick(UninstallStep.removingShortcuts, 0.30);
    try {
      final profile = Platform.environment['USERPROFILE'];
      final appData = Platform.environment['APPDATA'];
      if (desktopShortcut && profile != null) {
        await _deleteFile(File(p.join(profile, 'Desktop', 'MoeSketchpad.lnk')));
      }
      if (startMenuShortcut && appData != null) {
        await _deleteFile(
          File(
            p.join(
              appData,
              'Microsoft',
              'Windows',
              'Start Menu',
              'Programs',
              'MoeSketchpad.lnk',
            ),
          ),
        );
        // Clean up an empty Start Menu\MoeSketchpad folder if present.
        final menuDir = Directory(
          p.join(
            appData,
            'Microsoft',
            'Windows',
            'Start Menu',
            'Programs',
            'MoeSketchpad',
          ),
        );
        try {
          await menuDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      tick(UninstallStep.removingShortcuts, 0.30, e);
    }

    // 3. Remove the install dir from the user PATH.
    tick(UninstallStep.removingPath, 0.45);
    if (registeredPath) {
      try {
        await _removeFromPath(installDir);
      } catch (e) {
        tick(UninstallStep.removingPath, 0.45, e);
      }
    }

    // 4. Remove the Add/Remove Programs entry.
    tick(UninstallStep.removingRegistry, 0.60);
    try {
      await _run('reg.exe', ['delete', _arpKey, '/f']);
    } catch (e) {
      tick(UninstallStep.removingRegistry, 0.60, e);
    }

    // 5. Remove the install directory itself. This runs last because deleting
    //    the running installer exe mid-process can break child-process spawning
    //    on Windows. Best-effort: locked files (e.g. the live exe) are skipped.
    tick(UninstallStep.removingFiles, 0.80);
    try {
      await _deleteTree(directory);
    } catch (e) {
      tick(UninstallStep.removingFiles, 0.80, e);
    }

    tick(UninstallStep.complete, 1.0);
  }

  // ─── helpers ─────────────────────────────────────────────────────────────

  static Future<void> _deleteTree(Directory dir) async {
    if (!await dir.exists()) return;
    // Delete children one at a time so a single locked file (typically this
    // running uninstaller) is skipped rather than aborting the whole removal.
    final futures = <Future>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      futures.add(_deleteEntity(entity));
    }
    await Future.wait(futures);
    try {
      await dir.delete();
    } catch (_) {}
  }

  static Future<void> _deleteEntity(FileSystemEntity entity) async {
    try {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else {
        await entity.delete();
      }
    } catch (_) {}
  }

  static Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort: a locked or missing shortcut is non-fatal.
    }
  }

  static Future<void> _run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  static Future<void> _removeFromPath(String installDir) async {
    final result = await Process.run('reg.exe', [
      'query',
      r'HKCU\Environment',
      '/v',
      'Path',
    ]);
    final match = RegExp(
      r'^\s*Path\s+REG_\w+\s+(.*)$',
      multiLine: true,
    ).firstMatch(result.stdout as String);
    final existing = (match?.group(1) ?? '')
        .split(';')
        .where((e) => e.isNotEmpty);
    final kept = existing.where((e) {
      try {
        return !p.equals(p.normalize(e), p.normalize(installDir));
      } catch (_) {
        return true;
      }
    }).toList();
    final newPath = kept.join(';');
    final result2 = await Process.run('reg.exe', [
      'add',
      r'HKCU\Environment',
      '/v',
      'Path',
      '/t',
      'REG_EXPAND_SZ',
      '/d',
      newPath,
      '/f',
    ]);
    if (result2.exitCode != 0) {
      throw ProcessException(
        'reg.exe',
        ['add', r'HKCU\Environment', '/v', 'Path'],
        '${result2.stderr}'.trim(),
        result2.exitCode,
      );
    }
  }
}
