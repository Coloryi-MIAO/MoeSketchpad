// SPDX-License-Identifier: GPL-3.0-only
export 'file_service_stub.dart' show PickedFile;
export 'file_service_stub.dart'
    if (dart.library.io) 'file_service_io.dart'
    if (dart.library.html) 'file_service_web.dart';
