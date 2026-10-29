// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/services/document_command_executor.dart';
import 'package:moesketchpad_core/moesketchpad_core.dart';

void main() {
  const executor = DocumentCommandExecutor();
  final empty = GeometryDocument(objects: const []);

  test('creates objects in the active document using structured arguments', () {
    final result = executor.execute(
      'moesp create point --x=2.5 --y=-4 --label="Point A"',
      empty,
    );
    expect(result.document.objects, hasLength(1));
    expect(result.document.objects.single.kind, GeometryKind.point);
    expect(result.document.objects.single.points.single, const Point2(2.5, -4));
    expect(result.document.objects.single.label, 'Point A');
  });

  test('executes safe calculations and rejects shell-like commands', () {
    expect(executor.execute('moesp calc sqrt(3^2+4^2)', empty).message, '5.0');
    expect(
      () => executor.execute('moesp rm -rf .', empty),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unknown and duplicate primitive options', () {
    expect(
      () => executor.execute('moesp create point --x=1 --y=2 --z=3', empty),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => executor.execute('moesp create point --x=1 --x=2 --y=3', empty),
      throwsA(isA<FormatException>()),
    );
  });
}
