// SPDX-License-Identifier: GPL-3.0-only
/// Dart side of the installer's custom frameless window manager.
///
/// The installer deliberately avoids third-party window plugins. The native
/// runner in `windows/runner/` owns the window and exposes it over a single
/// method channel; this class is the typed facade the UI uses.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Custom frameless window manager for the Windows installer.
///
/// All commands are no-ops on platforms without the native handler, so the same
/// widget tree runs in widget tests and on non-Windows hosts.
class WindowsWindowManager {
  WindowsWindowManager._();

  static const _channel = MethodChannel('moesketchpad/installer_window');

  static final _states = StreamController<WindowChromeState>.broadcast();

  static bool _initialized = false;

  /// Whether the custom frameless chrome is available on this platform.
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// Native window state changes, such as a system-driven maximize.
  static Stream<WindowChromeState> get stateChanges => _states.stream;

  /// Installs the incoming handler and queries the initial state.
  ///
  /// Safe to call more than once. Failures are swallowed so a missing native
  /// handler degrades to an ordinary window instead of crashing the UI.
  static Future<WindowChromeState> ensureInitialized() async {
    if (!isSupported) return const WindowChromeState.unknown();
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'windowStateChanged') {
          _states.add(
            WindowChromeState.fromMap(
              call.arguments is Map
                  ? Map<String, Object?>.from(call.arguments as Map)
                  : null,
            ),
          );
        }
        return null;
      });
    }
    return state();
  }

  /// Releases the channel handler. Called when the installer UI is disposed.
  static Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    _channel.setMethodCallHandler(null);
  }

  /// Minimizes the window.
  static Future<void> minimize() => _invoke('minimize');

  /// Maximizes the window, or restores it when already maximized.
  static Future<void> toggleMaximize() => _invoke('toggleMaximize');

  /// Requests a normal close.
  static Future<void> close() => _invoke('close');

  /// Asks the native side to begin a window drag.
  static Future<void> startDrag() => _invoke('startDrag');

  /// Reads the current native window state.
  static Future<WindowChromeState> state() async {
    if (!isSupported) return const WindowChromeState.unknown();
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('state');
      return WindowChromeState.fromMap(result);
    } on Object {
      return const WindowChromeState.unknown();
    }
  }

  static Future<void> _invoke(String method) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<Object?>(method);
    } on Object {
      // Window commands are best-effort; the UI stays usable without them.
    }
  }
}

/// Snapshot of the native window state used to render the chrome buttons.
@immutable
class WindowChromeState {
  const WindowChromeState({required this.maximized, required this.frameless});

  const WindowChromeState.unknown() : maximized = false, frameless = false;

  final bool maximized;
  final bool frameless;

  static WindowChromeState fromMap(Map<String, Object?>? map) {
    if (map == null) return const WindowChromeState.unknown();
    return WindowChromeState(
      maximized: map['maximized'] == true,
      frameless: map['frameless'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WindowChromeState &&
      other.maximized == maximized &&
      other.frameless == frameless;

  @override
  int get hashCode => Object.hash(maximized, frameless);
}
