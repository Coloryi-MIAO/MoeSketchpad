// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/window_bootstrap.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();
  String? launchFile;
  for (final argument in arguments) {
    if (argument.toLowerCase().endsWith('.moesp')) {
      launchFile = argument;
      break;
    }
  }
  runApp(MoeSketchpadApp(initialFilePath: launchFile));
}
