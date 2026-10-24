// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:moesketchpad_cli/msp_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await const MspCli().run(arguments);
}
