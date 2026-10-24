// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'file_service_stub.dart' show PickedFile;

const XTypeGroup _moeTypeGroup = XTypeGroup(
  label: 'MoeSketchpad',
  extensions: ['moesp'],
  mimeTypes: ['application/x-moesketchpad'],
  uniformTypeIdentifiers: ['com.coloryi.moesketchpad.moesp'],
);

class FileService {
  const FileService._();

  static bool get supportsNativePaths => true;

  static Future<PickedFile?> openDocument() async {
    final file = await openFile(acceptedTypeGroups: const [_moeTypeGroup]);
    if (file == null) return null;
    return PickedFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      path: file.path,
    );
  }

  static Future<String?> saveDocument({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_moeTypeGroup],
    );
    if (location == null) return null;
    final file = XFile.fromData(
      bytes,
      name: suggestedName,
      mimeType: 'application/x-moesketchpad',
    );
    await file.saveTo(location.path);
    return location.path;
  }

  static Future<String?> saveExport({
    required String suggestedName,
    required Uint8List bytes,
    required String extension,
    required String mimeType,
  }) async {
    final group = XTypeGroup(
      label: 'MoeSketchpad export',
      extensions: [extension],
      mimeTypes: [mimeType],
    );
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [group],
    );
    if (location == null) return null;
    await XFile.fromData(
      bytes,
      name: suggestedName,
      mimeType: mimeType,
    ).saveTo(location.path);
    return location.path;
  }

  static Future<PickedFile?> readFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return PickedFile(
      name: file.uri.pathSegments.last,
      bytes: await file.readAsBytes(),
      path: file.path,
    );
  }

  static Future<void> writeToPath(String path, Uint8List bytes) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    final temporary = File(
      '$path.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
