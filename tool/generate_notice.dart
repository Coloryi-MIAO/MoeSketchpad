// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

/// Regenerates NOTICE from pubspec.lock package names and resolved versions.
/// It does not copy full license texts; release engineers must review the
/// LICENSE file of each resolved package in the pub cache before shipping.
Future<void> main(List<String> args) async {
  final lock = File('pubspec.lock');
  if (!await lock.exists()) {
    stderr.writeln('Run from the repository root after `flutter pub get`.');
    exitCode = 1;
    return;
  }
  final content = await lock.readAsString();
  final lines = const LineSplitter().convert(content);
  final packages = <String, String>{};
  String? current;
  for (final line in lines) {
    if (line.startsWith('  ') &&
        line.endsWith(':') &&
        !line.startsWith('    ')) {
      current = line.trim().substring(0, line.trim().length - 1);
    } else if (current != null && line.trim().startsWith('version: ')) {
      packages[current] = line
          .trim()
          .substring('version: '.length)
          .replaceAll('"', '');
      current = null;
    }
  }
  final sorted = packages.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final buffer = StringBuffer()
    ..writeln('MoeSketchpad / 萌板 — third-party notices')
    ..writeln('Copyright (C) 2026 Coloryi-MIAO')
    ..writeln('SPDX-License-Identifier: GPL-3.0-only')
    ..writeln()
    ..writeln('Resolved dependencies from pubspec.lock at generation time:')
    ..writeln(
      'This list is informational; consult each package LICENSE and the',
    )
    ..writeln('Flutter/Dart SDK for the governing full texts.')
    ..writeln();
  for (final entry in sorted) {
    buffer.writeln(
      '- ${entry.key} ${entry.value} — see pub.dev/packages/${entry.key}',
    );
  }
  buffer
    ..writeln()
    ..writeln('Sources: https://github.com/Coloryi-MIAO/MoeSketchpad')
    ..writeln('License text: COPYING');
  final output = File(args.isEmpty ? 'NOTICE.generated' : args.first);
  await output.writeAsString(buffer.toString());
  stdout.writeln('Wrote ${output.path} (${packages.length} packages).');
}
