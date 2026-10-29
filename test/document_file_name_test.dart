// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/platform/document_file_name.dart';

void main() {
  test('adds the MoeSketchpad extension and preserves an existing one', () {
    expect(normalizeMoespFileName('lesson 1'), 'lesson 1.moesp');
    expect(normalizeMoespFileName('lesson.moesp'), 'lesson.moesp');
    expect(normalizeMoespFileName('lesson.MOESP'), 'lesson.MOESP');
  });

  test('rejects blank, path-like, reserved and overlong file names', () {
    for (final name in [
      '',
      '  ',
      '../outside',
      r'C:\outside',
      'lesson?.moesp',
      List.filled(121, 'x').join(),
    ]) {
      expect(
        () => normalizeMoespFileName(name),
        throwsFormatException,
        reason: name,
      );
    }
  });
}
