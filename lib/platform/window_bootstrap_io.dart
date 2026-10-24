// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> configureDesktopWindow() async {
  if (!Platform.isWindows && !Platform.isMacOS) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(980, 640),
    center: true,
    title: '萌板 / MoeSketchpad',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
