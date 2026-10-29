// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moesketchpad/app.dart';
import 'package:moesketchpad/bloc/canvas_bloc.dart';
import 'package:moesketchpad/bloc/document_bloc.dart';
import 'package:moesketchpad/bloc/tool_bloc.dart';

void main() {
  testWidgets('workspace shows the CDR shell and creates a point', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MoeSketchpadApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('文件(F)'), findsOneWidget);
    expect(find.byKey(const ValueKey('top-tool-select')), findsOneWidget);
    expect(find.byKey(const ValueKey('top-tool-point')), findsOneWidget);
    expect(find.byKey(const ValueKey('top-tool-ellipse')), findsOneWidget);
    expect(find.text('拖拽对象或框选；滚轮缩放，空格拖动画布。'), findsOneWidget);
    expect(find.text('A4 · 210×297 mm'), findsNothing);
    expect(find.text('画布 · 几何设定'), findsOneWidget);
    expect(find.text('选择'), findsWidgets);
    expect(find.byKey(const ValueKey('canvas-quick-toolbar')), findsNothing);
    for (final tool in MoeTool.values) {
      expect(
        find.byKey(ValueKey('top-tool-${tool.name}')).hitTestable(),
        findsOneWidget,
        reason: '${tool.name} should be visible without horizontal scrolling',
      );
    }
    for (final label in [
      '文件(F)',
      '编辑(E)',
      '视图(V)',
      '布局(L)',
      '对象(O)',
      '效果(C)',
      '文本(T)',
      '工具(O)',
      '窗口(W)',
      '帮助(H)',
    ]) {
      expect(
        find.byKey(ValueKey('menu-$label')).hitTestable(),
        findsOneWidget,
        reason: '$label should be visible in the compact menu',
      );
    }
    expect(find.text('几何设定'), findsOneWidget);
    expect(find.text('基础网格间距'), findsOneWidget);
    expect(find.text('数值容差'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-endpoint')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-model')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-api-key')), findsOneWidget);
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
      find.byKey(const ValueKey('toolbar-snap-grid')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-snap-grid')));
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

    await tester.tap(find.byKey(const ValueKey('top-tool-point')));
    await tester.pump();
    expect(find.text('点击画布创建点。'), findsOneWidget);
    // These coordinates are inside the canvas, away from rulers and the dock.
    await tester.tapAt(const Offset(520, 430));
    await tester.pumpAndSettle();
    expect(find.text('1 个对象'), findsOneWidget);
    await tester.tap(find.text('对象 (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('point-'), findsWidgets);
    await tester.tap(find.textContaining('point-').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('选中对象'));
    await tester.tap(find.text('选中对象'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('stroke-color-ffd33f49')),
    );
    await tester.tap(find.byKey(const ValueKey('stroke-color-ffd33f49')));
    await tester.pumpAndSettle();
    final point = documentBloc.state.active.document.objects.single;
    expect(point.style.strokeColor, 0xffd33f49);

    await tester.tap(find.byKey(const ValueKey('top-tool-rectangle')));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(460, 320), const Offset(130, 90));
    await tester.pumpAndSettle();
    final rectangle = documentBloc.state.active.document.objects.singleWhere(
      (object) => object.params['shape'] == 'rectangle',
    );
    expect(rectangle.points, hasLength(4));
    expect(rectangle.style.fillColor, isNull);

    await tester.tap(find.byKey(const ValueKey('top-tool-ray')));
    await tester.pump();
    expect(
      tester
          .element(find.byKey(const ValueKey('geometry-unit')))
          .read<ToolBloc>()
          .state
          .active,
      MoeTool.ray,
    );
    await tester.tap(find.byKey(const ValueKey('top-tool-vector')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('top-tool-arc')));
    await tester.pump();
    expect(
      tester
          .element(find.byKey(const ValueKey('geometry-unit')))
          .read<ToolBloc>()
          .state
          .active,
      MoeTool.arc,
    );

    await tester.binding.setSurfaceSize(const Size(720, 704));
    await tester.pumpAndSettle();
    expect(find.text('文件(F)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('top-tool-select')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('top-tool-point')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('选择'), findsWidgets);
    expect(find.text('几何设定'), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-quick-toolbar')), findsNothing);
    for (final action in [
      'toolbar-new',
      'toolbar-open',
      'toolbar-save',
      'toolbar-undo',
      'toolbar-redo',
      'toolbar-zoom',
      'toolbar-unit',
      'toolbar-grid',
      'toolbar-snap-grid',
      'toolbar-snap-objects',
    ]) {
      expect(
        find.byKey(ValueKey(action)).hitTestable(),
        findsOneWidget,
        reason: '$action should be visible in the compact operations bar',
      );
    }
    for (final tool in MoeTool.values) {
      expect(
        find.byKey(ValueKey('top-tool-${tool.name}')).hitTestable(),
        findsOneWidget,
        reason: '${tool.name} should be visible without horizontal scrolling',
      );
    }
    for (final label in [
      '文件(F)',
      '编辑(E)',
      '视图(V)',
      '布局(L)',
      '对象(O)',
      '效果(C)',
      '文本(T)',
      '工具(O)',
      '窗口(W)',
      '帮助(H)',
    ]) {
      expect(
        find.byKey(ValueKey('menu-$label')).hitTestable(),
        findsOneWidget,
        reason: '$label should be visible in the compact menu',
      );
    }
    expect(find.text('表格(A)'), findsNothing);
    expect(
      tester.getRect(find.text('文件(F)').first).top,
      greaterThanOrEqualTo(0),
    );
    expect(tester.getRect(find.text('文件(F)').first).bottom, lessThan(40));
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1140, 760));
    await tester.pumpAndSettle();
    for (final tool in MoeTool.values) {
      final rect = tester.getRect(
        find.byKey(ValueKey('top-tool-${tool.name}')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1140));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(760));
    }
    expect(tester.takeException(), isNull);
  });
}
