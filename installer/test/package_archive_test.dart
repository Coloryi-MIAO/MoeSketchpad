// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad_installer/package_archive.dart';

void main() {
  test('package paths remain inside the installation directory', () {
    expect(
      safePackageDestination(r'C:\Apps\MoeSketchpad', 'data/app.so'),
      r'C:\Apps\MoeSketchpad\data\app.so',
    );
    for (final path in [
      '../outside.exe',
      r'..\outside.exe',
      r'C:\outside.exe',
      '/outside.exe',
      'data//app.so',
    ]) {
      expect(
        () => safePackageDestination(r'C:\Apps\MoeSketchpad', path),
        throwsFormatException,
      );
    }
  });
}
