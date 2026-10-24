// SPDX-License-Identifier: GPL-3.0-only
// Web deliberately uses a download instead of pretending it has a filesystem
// path. Local font enumeration and process invocation are unavailable.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'file_service_stub.dart' show PickedFile;

class FileService {
  const FileService._();

  static bool get supportsNativePaths => false;

  static Future<PickedFile?> openDocument() async {
    final input = html.FileUploadInputElement()
      ..accept = '.msp,application/x-moesketchpad'
      ..style.display = 'none';
    html.document.body?.children.add(input);
    final completer = Completer<PickedFile?>();
    input.onChange.listen((_) async {
      final file = input.files?.isEmpty == true ? null : input.files!.first;
      input.remove();
      if (file == null) {
        completer.complete(null);
        return;
      }
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoadEnd.first;
      final result = reader.result;
      if (result is! ByteBuffer) {
        completer.completeError(
          const FormatException('Browser could not read the file.'),
        );
        return;
      }
      completer.complete(
        PickedFile(name: file.name, bytes: result.asUint8List()),
      );
    });
    input.click();
    return completer.future;
  }

  static Future<String?> saveDocument({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    final blob = html.Blob([bytes], 'application/x-moesketchpad');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = suggestedName
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    return suggestedName;
  }

  static Future<PickedFile?> readFromPath(String path) async => null;

  static Future<void> writeToPath(String path, Uint8List bytes) async {
    await saveDocument(
      suggestedName: path.split(RegExp(r'[/\\]')).last,
      bytes: bytes,
    );
  }
}
