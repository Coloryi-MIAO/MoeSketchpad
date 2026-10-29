// SPDX-License-Identifier: GPL-3.0-only
export 'update_service_stub.dart'
    if (dart.library.io) 'update_service_io.dart'
    if (dart.library.html) 'update_service_stub.dart';
