// SPDX-License-Identifier: GPL-3.0-only
/// Lightweight record of what an installation wrote to the system, so the
/// uninstaller can remove exactly those pieces.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// What gets persisted inside every installation directory.
class InstallManifest {
  InstallManifest({
    required this.installDir,
    required this.appVersion,
    required this.buildNumber,
    required this.languageCode,
    required this.registeredPath,
    required this.desktopShortcut,
    required this.startMenuShortcut,
  });

  factory InstallManifest.fromJson(Map<String, dynamic> json) =>
      InstallManifest(
        installDir: json['installDir'] as String,
        appVersion: json['appVersion'] as String,
        buildNumber: json['buildNumber'] as int,
        languageCode: (json['languageCode'] as String?)?.isEmpty ?? true
            ? 'en'
            : json['languageCode'] as String,
        registeredPath: json['registeredPath'] as bool? ?? false,
        desktopShortcut: json['desktopShortcut'] as bool? ?? false,
        startMenuShortcut: json['startMenuShortcut'] as bool? ?? false,
      );

  /// Path the manifest was loaded from. Populated by [load].
  String? sourcePath;

  final String installDir;
  final String appVersion;
  final int buildNumber;
  final String languageCode;
  final bool registeredPath;
  final bool desktopShortcut;
  final bool startMenuShortcut;

  Map<String, dynamic> toJson() => {
    'installDir': installDir,
    'appVersion': appVersion,
    'buildNumber': buildNumber,
    'languageCode': languageCode,
    'registeredPath': registeredPath,
    'desktopShortcut': desktopShortcut,
    'startMenuShortcut': startMenuShortcut,
  };

  /// Loads the manifest from an install directory, returning null when one is
  /// not present.
  static Future<InstallManifest?> load(String installDir) async {
    final file = File(p.join(installDir, _manifestName));
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final manifest = InstallManifest.fromJson(json);
      manifest.sourcePath = file.path;
      return manifest;
    } on Object {
      return null;
    }
  }

  /// Writes the manifest next to the executable.
  static Future<File> writeTo(
    String installDir,
    InstallManifest manifest,
  ) async {
    final file = File(p.join(installDir, _manifestName));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    return file;
  }
}

/// Relative filename inside the install directory.
const _manifestName = 'install_info.json';
