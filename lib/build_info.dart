// SPDX-License-Identifier: GPL-3.0-only
/// Build metadata. CI can override the dart-define values below.
library;

class BuildInfo {
  const BuildInfo._();

  static const String version = String.fromEnvironment(
    'MSP_VERSION',
    defaultValue: '1.0.0',
  );
  static const String buildNumber = String.fromEnvironment(
    'MSP_BUILD_NUMBER',
    defaultValue: '1',
  );
  static const String buildDate = String.fromEnvironment(
    'MSP_BUILD_DATE',
    defaultValue: '2026-10-24',
  );
  static const String commit = String.fromEnvironment(
    'MSP_COMMIT',
    defaultValue: 'local',
  );
  static const String repository =
      'https://github.com/Coloryi-MIAO/MoeSketchpad';
  static const String issues =
      'https://github.com/Coloryi-MIAO/MoeSketchpad/issues';
  static const String author = 'Coloryi-MIAO';
  static const String license = 'GPL-3.0-only';
}
