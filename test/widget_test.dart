// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/app.dart';
import 'package:moesketchpad/bloc/canvas_bloc.dart';
import 'package:moesketchpad/bloc/document_bloc.dart';

void main() {
  testWidgets('workspace shows the CDR shell and creates a point', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MoeSketchpadApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('萌板'), findsWidgets);
    expect(find.textContaining('文件(F)'), findsOneWidget);
    expect(find.text('A4 · 210×297 mm'), findsNothing);
    expect(find.text('画布'), findsOneWidget);
    expect(find.text('选择'), findsWidgets);
    expect(
      find.byKey(const ValueKey('canvas-quick-tool-select')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-quick-tool-point')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('canvas-action-save')), findsOneWidget);
    expect(find.text('几何设定'), findsOneWidget);
    expect(find.text('基础网格间距'), findsOneWidget);
    expect(find.text('数值容差'), findsOneWidget);
    expect(tester.getRect(find.text('文件(F)').first).top, lessThan(40));
    expect(tester.getRect(find.text('点').first).left, lessThan(400));
    expect(tester.getRect(find.text('几何设定')).right, greaterThan(1440 - 310));
    final canvasBloc = tester
        .element(find.byKey(const ValueKey('geometry-unit')))
        .read<CanvasBloc>();
    final documentBloc = tester
        .element(find.byKey(const ValueKey('geometry-unit')))
        .read<DocumentBloc>();

    await tester.tap(find.byKey(const ValueKey('geometry-grid-24.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();
    expect(canvasBloc.state.gridBaseSpacing, 10);
    expect(documentBloc.state.active.document.view.gridBaseSpacing, 10);
    expect(
      find.byKey(const ValueKey('canvas-action-grid-snap')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('canvas-action-grid-snap')));
    await tester.pumpAndSettle();
    expect(canvasBloc.state.snapGrid, isFalse);
    expect(documentBloc.state.active.document.view.snapGrid, isFalse);

    await tester.tap(find.byKey(const ValueKey('geometry-tolerance-1e-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1e-6').last);
    await tester.pumpAndSettle();
    expect(canvasBloc.state.geometryTolerance.relative, 1e-6);
    expect(canvasBloc.state.geometryTolerance.absolute, 1e-6);
    expect(
      documentBloc.state.active.document.view.geometryTolerance.relative,
      1e-6,
    );
    expect(documentBloc.state.active.dirty, isTrue);

    await tester.tap(find.byTooltip('点'));
    await tester.pump();
    // These coordinates are inside the canvas, away from rulers and the dock.
    await tester.tapAt(const Offset(520, 430));
    await tester.pumpAndSettle();
    expect(find.text('1 个对象'), findsOneWidget);
    await tester.tap(find.text('对象 (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('point-'), findsWidgets);

    await tester.binding.setSurfaceSize(const Size(720, 704));
    await tester.pumpAndSettle();
    expect(find.text('文件(F)'), findsOneWidget);
    expect(find.text('选择'), findsWidgets);
    expect(find.text('几何设定'), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-quick-toolbar')), findsOneWidget);
    final quickToolbarRect = tester.getRect(
      find.byKey(const ValueKey('canvas-quick-toolbar')),
    );
    expect(quickToolbarRect.left, greaterThanOrEqualTo(76));
    expect(quickToolbarRect.right, lessThanOrEqualTo(720 - 248 - 22));
    expect(
      tester.getRect(find.text('文件(F)').first).top,
      greaterThanOrEqualTo(0),
    );
    expect(tester.getRect(find.text('文件(F)').first).bottom, lessThan(40));
    expect(tester.takeException(), isNull);
  });
}
