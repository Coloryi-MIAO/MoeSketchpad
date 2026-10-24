// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import '../../bloc/tool_bloc.dart';
import '../../l10n/app_localizations.dart';

class ToolBox extends StatelessWidget {
  const ToolBox({
    super.key,
    required this.active,
    required this.onSelected,
    required this.cute,
  });

  final MoeTool active;
  final ValueChanged<MoeTool> onSelected;
  final bool cute;

  String _name(AppLocalizations l10n, MoeTool tool) => switch (tool) {
    MoeTool.select => l10n.toolSelect,
    MoeTool.point => l10n.toolPoint,
    MoeTool.segment => l10n.toolSegment,
    MoeTool.line => l10n.toolLine,
    MoeTool.circle => l10n.toolCircle,
    MoeTool.triangle => l10n.toolTriangle,
    MoeTool.polygon => l10n.toolPolygon,
    MoeTool.function => l10n.toolFunction,
    MoeTool.text => l10n.toolText,
    MoeTool.pan => l10n.toolPan,
    MoeTool.zoom => l10n.toolZoom,
    MoeTool.rectangle => l10n.toolRectangle,
    MoeTool.ellipse => l10n.toolEllipse,
    MoeTool.freehand => l10n.toolFreehand,
    MoeTool.fill => l10n.toolFill,
    MoeTool.transparency => l10n.toolTransparency,
    MoeTool.eyedropper => l10n.toolEyedropper,
    MoeTool.outline => l10n.toolOutline,
  };

  IconData _icon(MoeTool tool) => switch (tool) {
    MoeTool.select => Icons.near_me_outlined,
    MoeTool.point => Icons.circle,
    MoeTool.segment => Icons.show_chart,
    MoeTool.line => Icons.horizontal_rule,
    MoeTool.circle => Icons.circle_outlined,
    MoeTool.triangle => Icons.change_history,
    MoeTool.polygon => Icons.pentagon_outlined,
    MoeTool.function => Icons.functions,
    MoeTool.text => Icons.text_fields,
    MoeTool.pan => Icons.pan_tool_alt_outlined,
    MoeTool.zoom => Icons.zoom_in,
    MoeTool.rectangle => Icons.crop_square,
    MoeTool.ellipse => Icons.circle_outlined,
    MoeTool.freehand => Icons.gesture,
    MoeTool.fill => Icons.format_color_fill,
    MoeTool.transparency => Icons.opacity,
    MoeTool.eyedropper => Icons.colorize,
    MoeTool.outline => Icons.line_weight,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: cute ? const Color(0xfff4edf3) : const Color(0xffe6ebf0),
        border: const Border(
          right: BorderSide(color: Color(0xffb7c2cd), width: 1.2),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            _ToolGroup(
              primary: MoeTool.select,
              alternatives: const [],
              active: active,
              onSelected: onSelected,
              label: _name(l10n, MoeTool.select),
              icon: _icon(MoeTool.select),
              cute: cute,
            ),
            _ToolGroup(
              primary: MoeTool.rectangle,
              alternatives: const [MoeTool.ellipse, MoeTool.polygon],
              active: active,
              onSelected: onSelected,
              label: _name(l10n, MoeTool.rectangle),
              icon: _icon(MoeTool.rectangle),
              cute: cute,
            ),
            _ToolGroup(
              primary: MoeTool.zoom,
              alternatives: const [MoeTool.pan],
              active: active,
              onSelected: onSelected,
              label: _name(l10n, MoeTool.zoom),
              icon: _icon(MoeTool.zoom),
              cute: cute,
            ),
            for (final tool in const [
              MoeTool.freehand,
              MoeTool.text,
              MoeTool.fill,
              MoeTool.transparency,
              MoeTool.eyedropper,
              MoeTool.outline,
            ])
              _ToolGroup(
                primary: tool,
                alternatives: const [],
                active: active,
                onSelected: onSelected,
                label: _name(l10n, tool),
                icon: _icon(tool),
                cute: cute,
              ),
            Divider(
              height: 10,
              indent: 10,
              endIndent: 10,
              color: cute ? const Color(0xffdecfd9) : const Color(0xffbec5cd),
            ),
            _SectionLabel(text: l10n.toolShape, cute: cute),
            for (final tool in const [
              MoeTool.point,
              MoeTool.segment,
              MoeTool.line,
              MoeTool.circle,
              MoeTool.triangle,
              MoeTool.polygon,
              MoeTool.function,
            ])
              _ToolGroup(
                primary: tool,
                alternatives: const [],
                active: active,
                onSelected: onSelected,
                label: _name(l10n, tool),
                icon: _icon(tool),
                cute: cute,
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.cute});
  final String text;
  final bool cute;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 4, 3),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 8.5,
        color: cute ? const Color(0xff9a7182) : const Color(0xff71808f),
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _ToolGroup extends StatelessWidget {
  const _ToolGroup({
    required this.primary,
    required this.alternatives,
    required this.active,
    required this.onSelected,
    required this.label,
    required this.icon,
    required this.cute,
  });

  final MoeTool primary;
  final List<MoeTool> alternatives;
  final MoeTool active;
  final ValueChanged<MoeTool> onSelected;
  final String label;
  final IconData icon;
  final bool cute;

  @override
  Widget build(BuildContext context) {
    final selected = active == primary || alternatives.contains(active);
    final shown = selected ? active : primary;
    final l10n = AppLocalizations.of(context);
    String toolName(MoeTool tool) => switch (tool) {
      MoeTool.select => l10n.toolSelect,
      MoeTool.point => l10n.toolPoint,
      MoeTool.segment => l10n.toolSegment,
      MoeTool.line => l10n.toolLine,
      MoeTool.circle => l10n.toolCircle,
      MoeTool.triangle => l10n.toolTriangle,
      MoeTool.polygon => l10n.toolPolygon,
      MoeTool.function => l10n.toolFunction,
      MoeTool.text => l10n.toolText,
      MoeTool.pan => l10n.toolPan,
      MoeTool.zoom => l10n.toolZoom,
      MoeTool.rectangle => l10n.toolRectangle,
      MoeTool.ellipse => l10n.toolEllipse,
      MoeTool.freehand => l10n.toolFreehand,
      MoeTool.fill => l10n.toolFill,
      MoeTool.transparency => l10n.toolTransparency,
      MoeTool.eyedropper => l10n.toolEyedropper,
      MoeTool.outline => l10n.toolOutline,
    };
    IconData iconFor(MoeTool tool) => switch (tool) {
      MoeTool.select => Icons.near_me_outlined,
      MoeTool.point => Icons.circle,
      MoeTool.segment => Icons.show_chart,
      MoeTool.line => Icons.horizontal_rule,
      MoeTool.circle => Icons.circle_outlined,
      MoeTool.triangle => Icons.change_history,
      MoeTool.polygon => Icons.pentagon_outlined,
      MoeTool.function => Icons.functions,
      MoeTool.text => Icons.text_fields,
      MoeTool.pan => Icons.pan_tool_alt_outlined,
      MoeTool.zoom => Icons.zoom_in,
      MoeTool.rectangle => Icons.crop_square,
      MoeTool.ellipse => Icons.circle_outlined,
      MoeTool.freehand => Icons.gesture,
      MoeTool.fill => Icons.format_color_fill,
      MoeTool.transparency => Icons.opacity,
      MoeTool.eyedropper => Icons.colorize,
      MoeTool.outline => Icons.line_weight,
    };
    Future<void> openFlyout() async {
      final render = context.findRenderObject() as RenderBox?;
      final origin = render == null
          ? Offset.zero
          : render.localToGlobal(Offset(render.size.width, 0));
      final picked = await showMenu<MoeTool>(
        context: context,
        position: RelativeRect.fromLTRB(
          origin.dx,
          origin.dy,
          origin.dx + 190,
          origin.dy + 260,
        ),
        items: [
          for (final tool in [primary, ...alternatives])
            PopupMenuItem(
              value: tool,
              height: 38,
              child: Row(
                children: [
                  Icon(iconFor(tool), size: 17),
                  const SizedBox(width: 9),
                  Text(toolName(tool), style: const TextStyle(fontSize: 12)),
                  if (tool == primary && alternatives.isNotEmpty) ...[
                    const Spacer(),
                    Text(
                      '1',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
      if (picked != null) onSelected(picked);
    }

    return Tooltip(
      message: alternatives.isEmpty
          ? toolName(shown)
          : '${toolName(shown)} · ${l10n.toolMoreInGroup}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(cute ? 9 : 3),
          onTap: () => onSelected(shown),
          onLongPress: alternatives.isEmpty ? null : openFlyout,
          onSecondaryTap: alternatives.isEmpty ? null : openFlyout,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: selected
                  ? (cute ? const Color(0xffffe1ed) : const Color(0xffd9ebfb))
                  : (cute ? const Color(0xfffdf9fc) : const Color(0xfff9fbfd)),
              borderRadius: BorderRadius.circular(cute ? 9 : 3),
              border: Border.all(
                color: selected
                    ? (cute ? const Color(0xffbf6687) : const Color(0xff5d93bd))
                    : const Color(0xffc4cdd6),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        iconFor(shown),
                        size: 21,
                        color: selected
                            ? (cute
                                  ? const Color(0xff853855)
                                  : const Color(0xff205d88))
                            : const Color(0xff263f54),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        toolName(shown),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: selected
                              ? (cute
                                    ? const Color(0xff853855)
                                    : const Color(0xff205d88))
                              : const Color(0xff263f54),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (alternatives.isNotEmpty)
                  Positioned(
                    right: 3,
                    bottom: 2,
                    child: CustomPaint(
                      size: const Size(5, 5),
                      painter: _FlyoutTrianglePainter(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlyoutTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xff2a3948));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
