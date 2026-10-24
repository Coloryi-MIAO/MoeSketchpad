// SPDX-License-Identifier: GPL-3.0-only
export 'close_guard_stub.dart'
    if (dart.library.io) 'close_guard_io.dart'
    if (dart.library.html) 'close_guard_web.dart';
