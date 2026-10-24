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
      ..accept = '.moesp'
      ..style.display = 'none';
    final body = html.document.body;
    if (body == null) {
      throw StateError('The browser document body is unavailable.');
    }
    body.children.add(input);
    final completer = Completer<PickedFile?>();
    late final StreamSubscription<html.Event> changeSubscription;
    changeSubscription = input.onChange.listen((_) {
      final file = input.files?.isEmpty == true ? null : input.files!.first;
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final reader = html.FileReader();
      reader.onLoad.listen((_) {
        final result = reader.result;
        final bytes = switch (result) {
          ByteBuffer buffer => buffer.asUint8List(),
          Uint8List data => data,
          _ => null,
        };
        if (bytes == null) {
          if (!completer.isCompleted) {
            completer.completeError(
              const FormatException(
                'Browser could not read the selected file.',
              ),
            );
          }
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(PickedFile(name: file.name, bytes: bytes));
        }
      });
      reader.onError.listen((_) {
        if (!completer.isCompleted) {
          completer.completeError(
            const FormatException('Browser could not read the selected file.'),
          );
        }
      });
      reader.readAsArrayBuffer(file);
    });
    input.click();
    return completer.future.whenComplete(() {
      changeSubscription.cancel();
      input.remove();
    });
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
    Timer(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
    return suggestedName;
  }

  static Future<String?> saveExport({
    required String suggestedName,
    required Uint8List bytes,
    required String extension,
    required String mimeType,
  }) async {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = suggestedName
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    Timer(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
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
