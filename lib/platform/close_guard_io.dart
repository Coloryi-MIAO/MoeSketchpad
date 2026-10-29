// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:window_manager/window_manager.dart';

import 'close_guard_stub.dart';

class _GuardListener extends WindowListener {
  _GuardListener(this.confirmClose);
  final AsyncBoolCallback confirmClose;
  bool _closing = false;

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    final shouldClose = await confirmClose();
    if (!shouldClose) return;
    _closing = true;
    await windowManager.destroy();
  }
}

_GuardListener? _listener;

class CloseGuard {
  const CloseGuard._();

  static Future<void> install({
    required AsyncBoolCallback confirmClose,
    required BoolCallback hasUnsavedChanges,
  }) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      await uninstall();
      await windowManager.setPreventClose(true);
      _listener = _GuardListener(confirmClose);
      windowManager.addListener(_listener!);
    } on Object {
      // No window_manager plugin (widget tests / unusual embedder). The UI's
      // in-app close prompts still apply.
      _listener = null;
    }
  }

  static Future<void> uninstall() async {
    final listener = _listener;
    if (listener != null) {
      try {
        windowManager.removeListener(listener);
      } on Object {
        // Plugin may already be gone during teardown.
      }
      _listener = null;
    }
  }
}
