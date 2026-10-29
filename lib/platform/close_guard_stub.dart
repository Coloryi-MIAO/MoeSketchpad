// SPDX-License-Identifier: GPL-3.0-only
typedef AsyncBoolCallback = Future<bool> Function();
typedef BoolCallback = bool Function();

class CloseGuard {
  const CloseGuard._();

  static Future<void> install({
    required AsyncBoolCallback confirmClose,
    required BoolCallback hasUnsavedChanges,
  }) async {}

  static Future<void> uninstall() async {}
}
