// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

Future<void> configureDesktopWindow() async {
  if (!Platform.isWindows && !Platform.isMacOS) return;
  await windowManager.ensureInitialized();
  final display = await screenRetriever.getPrimaryDisplay();
  final available = display.visibleSize ?? display.size;
  final minimumSize = Size(
    math.min(720, available.width * 0.75),
    math.min(480, available.height * 0.75),
  );
  final initialSize = Size(
    math.max(minimumSize.width, math.min(1440, available.width * 0.9)),
    math.max(minimumSize.height, math.min(900, available.height * 0.9)),
  );
  final options = WindowOptions(
    size: initialSize,
    minimumSize: minimumSize,
    center: true,
    title: 'MoeSketchpad',
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
