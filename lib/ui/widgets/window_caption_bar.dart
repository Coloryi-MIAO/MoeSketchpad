// SPDX-License-Identifier: GPL-3.0-only
/// Desktop caption bar for the frameless MoeSketchpad window.
///
/// The desktop build hides the native title bar (`TitleBarStyle.hidden`) so the
/// app can paint the CDR-style shell edge to edge. That leaves no way to move or
/// close the window unless the app draws its own controls, which is what this
/// widget provides.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the app must draw its own caption bar on this platform.
bool get usesCustomWindowChrome =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS);

/// Height of the custom caption strip, in logical pixels.
///
/// Exposed so layout tests and callers can account for the strip that
/// [usesCustomWindowChrome] platforms reserve above the app content.
const double windowCaptionHeight = 34.0;
const _captionIcon = Color(0xff46586a);
const _captionHover = Color(0x14000000);
const _captionCloseHover = Color(0xffc9453d);
const _captionBorder = Color(0xff9ba9b7);

/// Draggable caption strip with minimize, maximize and close controls.
///
/// [cute] follows the active theme so the strip matches the rest of the shell.
class WindowCaptionBar extends StatefulWidget {
  const WindowCaptionBar({
    super.key,
    required this.title,
    required this.cute,
    this.leading,
    this.trailing,
  });

  final String title;
  final bool cute;

  /// Optional widgets pinned to the left, after the app mark.
  final List<Widget>? leading;

  /// Optional widgets pinned to the right, before the window buttons.
  final List<Widget>? trailing;

  @override
  State<WindowCaptionBar> createState() => _WindowCaptionBarState();
}

class _WindowCaptionBarState extends State<WindowCaptionBar>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (!usesCustomWindowChrome) return;
    windowManager.addListener(this);
    _syncState();
  }

  @override
  void dispose() {
    if (usesCustomWindowChrome) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncState() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = maximized);
    } on Object {
      // Plugin unavailable (widget tests / unusual embedder).
    }
  }

  @override
  void onWindowMaximize() => _syncState();

  @override
  void onWindowUnmaximize() => _syncState();

  @override
  void onWindowRestore() => _syncState();

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncState();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.cute
        ? const Color(0xfff4eef5)
        : const Color(0xffeef1f4);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: usesCustomWindowChrome
          ? (_) => windowManager.startDragging()
          : null,
      onDoubleTap: usesCustomWindowChrome ? _toggleMaximize : null,
      child: Container(
        height: windowCaptionHeight,
        decoration: BoxDecoration(
          color: background,
          border: const Border(
            bottom: BorderSide(color: _captionBorder, width: 1),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(
              Icons.gesture_rounded,
              size: 15,
              color: widget.cute ? const Color(0xff8c5470) : _captionIcon,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff35485a),
                ),
              ),
            ),
            ...?widget.leading,
            const Spacer(),
            ...?widget.trailing,
            if (usesCustomWindowChrome) ...[
              WindowCaptionButton(
                icon: Icons.remove,
                tooltip: 'Minimize',
                onPressed: windowManager.minimize,
              ),
              WindowCaptionButton(
                icon: _maximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                tooltip: _maximized ? 'Restore' : 'Maximize',
                onPressed: _toggleMaximize,
              ),
              WindowCaptionButton(
                icon: Icons.close,
                tooltip: 'Close',
                danger: true,
                onPressed: () async {
                  // Route through the same guard as the native close button so
                  // unsaved documents still prompt.
                  await windowManager.close();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Caption button matching the Windows 11 metrics.
class WindowCaptionButton extends StatefulWidget {
  const WindowCaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final bool danger;

  @override
  State<WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<WindowCaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final background = _hovered
        ? (widget.danger ? _captionCloseHover : _captionHover)
        : Colors.transparent;
    final foreground = _hovered && widget.danger ? Colors.white : _captionIcon;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 44,
            height: windowCaptionHeight,
            alignment: Alignment.center,
            color: background,
            child: Icon(widget.icon, size: 14, color: foreground),
          ),
        ),
      ),
    );
  }
}
