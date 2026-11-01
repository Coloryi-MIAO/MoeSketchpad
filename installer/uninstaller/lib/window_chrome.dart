// SPDX-License-Identifier: GPL-3.0-only
/// Custom caption bar drawn by Flutter for the frameless installer window.
library;

import 'package:flutter/material.dart';

import 'windows_window_manager.dart';

const _chromeHeight = 36.0;
const _chromeBackground = Color(0xffeef2f6);
const _chromeBorder = Color(0xffd3dbe3);
const _chromeIcon = Color(0xff4a5b6b);
const _chromeHover = Color(0x14000000);
const _closeHover = Color(0xffc9453d);

/// A draggable caption strip with minimize / maximize / close buttons.
///
/// The strip is intentionally thin and only reports drags through the native
/// caption hit test, so Flutter widgets placed below it keep their gestures.
class WindowChrome extends StatefulWidget {
  const WindowChrome({
    super.key,
    this.title = 'MoeSketchpad Setup',
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  State<WindowChrome> createState() => _WindowChromeState();
}

class _WindowChromeState extends State<WindowChrome> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    WindowsWindowManager.ensureInitialized().then((state) {
      if (mounted) setState(() => _maximized = state.maximized);
    });
  }

  Future<void> _toggleMaximize() async {
    await WindowsWindowManager.toggleMaximize();
    final state = await WindowsWindowManager.state();
    if (mounted) setState(() => _maximized = state.maximized);
  }

  /// Second caption line, or null when no subtitle was supplied.
  Widget? get _subtitleText {
    final subtitle = widget.subtitle;
    if (subtitle == null) return null;
    return Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 10.5, color: Color(0xff74838f)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The native runner performs the actual drag via WM_NCHITTEST, so the strip
    // only needs to avoid swallowing pointer events.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowsWindowManager.startDrag(),
      onDoubleTap: _toggleMaximize,
      child: Container(
        height: _chromeHeight,
        decoration: const BoxDecoration(
          color: _chromeBackground,
          border: Border(bottom: BorderSide(color: _chromeBorder)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.gesture_rounded, size: 16, color: _chromeIcon),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff2c3e4f),
                    ),
                  ),
                  ?_subtitleText,
                ],
              ),
            ),
            ?widget.trailing,
            _ChromeButton(
              icon: Icons.remove,
              tooltip: 'Minimize',
              onPressed: WindowsWindowManager.minimize,
            ),
            _ChromeButton(
              icon: _maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              tooltip: _maximized ? 'Restore' : 'Maximize',
              onPressed: _toggleMaximize,
            ),
            _ChromeButton(
              icon: Icons.close,
              tooltip: 'Close',
              danger: true,
              onPressed: WindowsWindowManager.close,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChromeButton extends StatefulWidget {
  const _ChromeButton({
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
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final background = _hovered
        ? (widget.danger ? _closeHover : _chromeHover)
        : Colors.transparent;
    final foreground = _hovered && widget.danger ? Colors.white : _chromeIcon;
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
            height: _chromeHeight,
            alignment: Alignment.center,
            color: background,
            child: Icon(widget.icon, size: 15, color: foreground),
          ),
        ),
      ),
    );
  }
}
