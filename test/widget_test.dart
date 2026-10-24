// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/main.dart';

void main() {
  testWidgets('workspace creates a labeled point', (tester) async {
    await tester.pumpWidget(const MoeSketchpadApp());

    expect(find.text('萌板'), findsOneWidget);
    await tester.tap(find.byTooltip('点'));
    await tester.pump();
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(find.text('point A'), findsOneWidget);
    expect(find.text('1 个对象'), findsOneWidget);
  });
}
