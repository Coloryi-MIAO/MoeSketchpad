// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/geometry.dart';

void main() => runApp(const MoeSketchpadApp());

class MoeSketchpadApp extends StatelessWidget {
  const MoeSketchpadApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '萌板 / MoeSketchpad',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff3978b7),
        brightness: Brightness.light,
      ),
      useMaterial3: false,
      fontFamily: 'Microsoft YaHei',
    ),
    home: const DrawingWorkspace(),
  );
}

enum DrawingTool { select, point, segment, pan }

class DrawingWorkspace extends StatefulWidget {
  const DrawingWorkspace({super.key});

  @override
  State<DrawingWorkspace> createState() => _DrawingWorkspaceState();
}

class _DrawingWorkspaceState extends State<DrawingWorkspace> {
  static const _blue = Color(0xff3978b7);
  final List<GeometryObject> _objects = [];
  final List<List<GeometryObject>> _undo = [];
  DrawingTool _tool = DrawingTool.select;
  Offset _camera = Offset.zero;
  double _zoom = 1;
  bool _cuteTheme = true;
  bool _english = false;
  bool _showGrid = true;
  Point2? _segmentStart;
  bool _dirty = false;
  int _pointSequence = 0;
  double _zoomAtScaleStart = 1;

  String _text(String zh, String en) => _english ? en : zh;
  Color get _chrome =>
      _cuteTheme ? const Color(0xfff6f8fc) : const Color(0xffe8e8e8);

  void _undoEdit() {
    if (_undo.isEmpty) return;
    setState(() {
      _objects
        ..clear()
        ..addAll(_undo.removeLast());
      _dirty = _undo.isNotEmpty;
    });
  }

  void _recordEdit() {
    _undo.add(List<GeometryObject>.of(_objects));
    _dirty = true;
  }

  void _onCanvasTap(Offset local, Size size) {
    final world = Point2(
      (local.dx - size.width / 2 - _camera.dx) / _zoom,
      (local.dy - size.height / 2 - _camera.dy) / _zoom,
    );
    setState(() {
      switch (_tool) {
        case DrawingTool.point:
          _recordEdit();
          final label = String.fromCharCode(65 + (_pointSequence++ % 26));
          _objects.add(
            GeometryObject(
              id: 'point-${DateTime.now().microsecondsSinceEpoch}',
              kind: 'point',
              points: [world],
              label: label,
            ),
          );
          break;
        case DrawingTool.segment:
          if (_segmentStart == null) {
            _segmentStart = world;
          } else {
            _recordEdit();
            _objects.add(
              GeometryObject(
                id: 'segment-${DateTime.now().microsecondsSinceEpoch}',
                kind: 'segment',
                points: [_segmentStart!, world],
              ),
            );
            _segmentStart = null;
          }
          break;
        case DrawingTool.select:
        case DrawingTool.pan:
          break;
      }
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_tool == DrawingTool.pan || details.pointerCount > 1) {
      setState(() {
        _camera += details.focalPointDelta;
        if (details.pointerCount > 1) {
          _zoom = (_zoomAtScaleStart * details.scale).clamp(0.05, 64);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chrome,
      body: SafeArea(
        child: Column(
          children: [
            _buildMenuBar(),
            _buildStandardBar(),
            _buildContextBar(),
            Expanded(child: _buildWorkspace()),
            _buildDocumentTabs(),
            _buildStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuBar() => Container(
    height: 34,
    color: _chrome,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        const Icon(Icons.gesture, size: 19, color: _blue),
        const SizedBox(width: 8),
        Text(
          _text('萌板', 'MoeSketchpad'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  [
                        '文件(F)',
                        '编辑(E)',
                        '视图(V)',
                        '布局(L)',
                        '对象(O)',
                        '效果(C)',
                        '文本(T)',
                        '表格(A)',
                        '工具(O)',
                        '窗口(W)',
                        '帮助(H)',
                      ]
                      .map(
                        (label) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: _text('切换语言', 'Toggle language'),
          onPressed: () => setState(() => _english = !_english),
          icon: const Icon(Icons.language, size: 18),
        ),
        IconButton(
          tooltip: _text('切换主题', 'Toggle theme'),
          onPressed: () => setState(() => _cuteTheme = !_cuteTheme),
          icon: Icon(_cuteTheme ? Icons.auto_awesome : Icons.tune, size: 18),
        ),
      ],
    ),
  );

  Widget _buildStandardBar() => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Color(0xfffdfdfd),
      border: Border(bottom: BorderSide(color: Color(0xffd5d9df))),
    ),
    child: Row(
      children: [
        _toolbarButton(Icons.insert_drive_file_outlined, '新建'),
        _toolbarButton(Icons.folder_open_outlined, '打开'),
        _toolbarButton(Icons.save_outlined, '保存'),
        const VerticalDivider(indent: 8, endIndent: 8),
        IconButton(
          tooltip: '撤销',
          onPressed: _undo.isEmpty ? null : _undoEdit,
          icon: const Icon(Icons.undo, size: 19),
        ),
        IconButton(
          tooltip: '重做',
          onPressed: null,
          icon: const Icon(Icons.redo, size: 19),
        ),
        const VerticalDivider(indent: 8, endIndent: 8),
        DropdownButton<double>(
          value: 1,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 1, child: Text('100%')),
            DropdownMenuItem(value: 0.5, child: Text('50%')),
            DropdownMenuItem(value: 2, child: Text('200%')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _zoom = value);
          },
        ),
        const SizedBox(width: 12),
        const Text('px', style: TextStyle(fontSize: 12)),
        const Spacer(),
        FilterChip(
          label: Text(_text('贴齐', 'Snap')),
          selected: false,
          onSelected: (_) {},
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );

  Widget _toolbarButton(IconData icon, String tooltip) => IconButton(
    tooltip: tooltip,
    onPressed: () => _showNotReady(tooltip),
    icon: Icon(icon, size: 19),
  );

  Widget _buildContextBar() => Container(
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: const BoxDecoration(
      color: Color(0xfff5f6f8),
      border: Border(bottom: BorderSide(color: Color(0xffd5d9df))),
    ),
    child: Row(
      children: [
        Text(
          _text('页面', 'Page'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        const Text('A4', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        const Text('210 × 297 mm', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 18),
        const Text('▭', style: TextStyle(color: _blue)),
        const SizedBox(width: 8),
        Text(
          _text('方向：纵向', 'Orientation: Portrait'),
          style: const TextStyle(fontSize: 12),
        ),
        const Spacer(),
        Text(
          _text('工具：${_tool.name}', 'Tool: ${_tool.name}'),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    ),
  );

  Widget _buildWorkspace() => Row(
    children: [
      Container(
        width: 48,
        color: _chrome,
        child: Column(
          children: [
            _toolButton(DrawingTool.select, Icons.near_me_outlined, '选择'),
            _toolButton(
              DrawingTool.point,
              Icons.add_location_alt_outlined,
              '点',
            ),
            _toolButton(DrawingTool.segment, Icons.show_chart, '线段'),
            _toolButton(DrawingTool.pan, Icons.pan_tool_alt_outlined, '平移'),
            const Divider(indent: 9, endIndent: 9),
            IconButton(
              tooltip: '缩放',
              onPressed: () =>
                  setState(() => _zoom = (_zoom * 1.25).clamp(.05, 64)),
              icon: const Icon(Icons.zoom_in, size: 20),
            ),
            IconButton(
              tooltip: '网格',
              onPressed: () => setState(() => _showGrid = !_showGrid),
              icon: Icon(
                Icons.grid_on,
                size: 18,
                color: _showGrid ? _blue : Colors.black54,
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: Container(
          color: const Color(0xffdfe3e8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                children: [
                  RepaintBoundary(
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          setState(() {
                            _zoom =
                                (event.scrollDelta.dy < 0
                                        ? _zoom * 1.1
                                        : _zoom / 1.1)
                                    .clamp(.05, 64);
                          });
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _onCanvasTap(details.localPosition, size),
                        onScaleStart: (_) => _zoomAtScaleStart = _zoom,
                        onScaleUpdate: _onScaleUpdate,
                        child: CustomPaint(
                          size: size,
                          painter: _CanvasPainter(
                            objects: _objects,
                            camera: _camera,
                            zoom: _zoom,
                            showGrid: _showGrid,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          _segmentStart == null
                              ? _text(
                                  '滚轮/双指缩放 · 空格/平移工具拖动画布',
                                  'Wheel/pinch to zoom · Choose Pan tool to drag',
                                )
                              : _text('点击第二个端点完成线段', 'Tap the second endpoint'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      Container(
        width: 204,
        color: const Color(0xfff8f9fb),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dockHeader(_text('对象', 'Objects')),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: _objects.reversed
                    .map(
                      (object) => ListTile(
                        dense: true,
                        leading: Icon(
                          object.kind == 'point'
                              ? Icons.circle
                              : Icons.show_chart,
                          size: 16,
                          color: _blue,
                        ),
                        title: Text(
                          '${object.kind} ${object.label ?? ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            _dockHeader(_text('图层', 'Layers')),
            ListTile(
              dense: true,
              leading: const Icon(Icons.layers_outlined, size: 18),
              title: Text(
                _text('图层 1', 'Layer 1'),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.visibility_outlined, size: 16),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _toolButton(DrawingTool tool, IconData icon, String label) {
    final selected = _tool == tool;
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: () => setState(() => _tool = tool),
          child: Container(
            width: 36,
            height: 34,
            decoration: BoxDecoration(
              color: selected ? const Color(0xffd8e8f8) : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected ? _blue : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dockHeader(String title) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xffd5d9df))),
    ),
    child: Text(
      title,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  Widget _buildDocumentTabs() => Container(
    height: 31,
    color: const Color(0xfff5f6f8),
    padding: const EdgeInsets.only(left: 58),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        color: Colors.white,
        child: Text(
          '未命名-1.msp${_dirty ? ' *' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    ),
  );

  Widget _buildStatusBar() => Container(
    height: 24,
    color: const Color(0xfffdfdfd),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      children: [
        Text(
          _text('${_objects.length} 个对象', '${_objects.length} objects'),
          style: const TextStyle(fontSize: 11),
        ),
        const Spacer(),
        Text(
          'x ${(100 * _zoom).toStringAsFixed(0)}%',
          style: const TextStyle(fontSize: 11),
        ),
        const SizedBox(width: 14),
        Text(
          _text('工作区坐标系', 'Workspace coordinates'),
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );

  void _showNotReady(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _text(
            '$feature：此功能将在后续版本接入平台文件服务。',
            '$feature: platform file service is planned for a later milestone.',
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.objects,
    required this.camera,
    required this.zoom,
    required this.showGrid,
  });

  final List<GeometryObject> objects;
  final Offset camera;
  final double zoom;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xffdfe3e8), BlendMode.src);
    final origin = Offset(
      size.width / 2 + camera.dx,
      size.height / 2 + camera.dy,
    );
    if (showGrid) _paintGrid(canvas, size, origin);

    final page = Rect.fromCenter(
      center: origin,
      width: 794 * zoom,
      height: 1123 * zoom,
    );
    canvas.drawRect(
      page.shift(const Offset(2, 3)),
      Paint()
        ..color = const Color(0x26000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRect(page, Paint()..color = Colors.white);
    canvas.drawRect(
      page,
      Paint()
        ..color = const Color(0xffc4cbd3)
        ..style = PaintingStyle.stroke,
    );

    for (final object in objects) {
      if (object.kind == 'point') {
        final p = _toScreen(object.points.first, size);
        canvas.drawCircle(p, 4.5, Paint()..color = const Color(0xff246db2));
        canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
        if (object.label != null) {
          _drawLabel(canvas, object.label!, p + const Offset(7, -15));
        }
      } else if (object.kind == 'segment' && object.points.length == 2) {
        final a = _toScreen(object.points[0], size);
        final b = _toScreen(object.points[1], size);
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = const Color(0xff2878bd)
            ..strokeWidth = 1.8,
        );
      }
    }
    canvas.drawCircle(
      origin,
      3,
      Paint()
        ..color = const Color(0xffde6b61)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintGrid(Canvas canvas, Size size, Offset origin) {
    var worldSpacing = 24.0;
    while (worldSpacing * zoom < 18) {
      worldSpacing *= 2;
    }
    while (worldSpacing * zoom > 72) {
      worldSpacing /= 2;
    }
    final spacing = worldSpacing * zoom;
    if (spacing < 7 || spacing > 160) return;
    final paint = Paint()
      ..color = const Color(0x1a56677a)
      ..strokeWidth = 0.7;
    final firstX = ((-origin.dx) / spacing).floor();
    final lastX = ((size.width - origin.dx) / spacing).ceil();
    for (var i = firstX; i <= lastX; i++) {
      final x = origin.dx + i * spacing;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final firstY = ((-origin.dy) / spacing).floor();
    final lastY = ((size.height - origin.dy) / spacing).ceil();
    for (var i = firstY; i <= lastY; i++) {
      final y = origin.dy + i * spacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  Offset _toScreen(Point2 point, Size size) => Offset(
    size.width / 2 + camera.dx + point.x * zoom,
    size.height / 2 + camera.dy + point.y * zoom,
  );

  void _drawLabel(Canvas canvas, String label, Offset position) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xff263746),
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.objects != objects ||
      oldDelegate.camera != camera ||
      oldDelegate.zoom != zoom ||
      oldDelegate.showGrid != showGrid;
}
