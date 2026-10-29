// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:moesketchpad_cli/msp_cli.dart';

/// Compatibility entry point. The canonical executable lives in
/// packages/moesketchpad_cli and is published as `msp`.
Future<void> main(List<String> arguments) async {
  exitCode = await const MspCli().run(arguments);
}
