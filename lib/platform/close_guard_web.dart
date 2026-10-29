// SPDX-License-Identifier: GPL-3.0-only
// Browsers own the wording of beforeunload prompts and may suppress them
// entirely. This is a best-effort warning, not a custom modal dialog.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

import 'close_guard_stub.dart';

StreamSubscription<html.Event>? _subscription;

class CloseGuard {
  const CloseGuard._();

  static Future<void> install({
    required AsyncBoolCallback confirmClose,
    required BoolCallback hasUnsavedChanges,
  }) async {
    await uninstall();
    _subscription = html.window.onBeforeUnload.listen((event) {
      if (!hasUnsavedChanges()) return;
      (event as html.BeforeUnloadEvent).returnValue = '';
      event.preventDefault();
    });
  }

  static Future<void> uninstall() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
