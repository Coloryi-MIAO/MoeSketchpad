// SPDX-License-Identifier: GPL-3.0-only
import 'dart:typed_data';

class PickedFile {
  const PickedFile({required this.name, required this.bytes, this.path});
  final String name;
  final Uint8List bytes;
  final String? path;
}

class FileService {
  const FileService._();

  static bool get supportsNativePaths => false;

  static Future<PickedFile?> openDocument() async => null;

  static Future<String?> saveDocument({
    required String suggestedName,
    required Uint8List bytes,
  }) async => null;

  static Future<void> writeToPath(String path, Uint8List bytes) async {
    throw UnsupportedError('This platform has no writable filesystem paths.');
  }

  static Future<PickedFile?> readFromPath(String path) async => null;
}
