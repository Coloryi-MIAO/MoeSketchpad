// SPDX-License-Identifier: GPL-3.0-only
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

const maxPackageFiles = 20000;
const maxPackageFileSize = 256 * 1024 * 1024;
const maxPackageSize = 1024 * 1024 * 1024;

void validateApplicationArchive(Archive archive) {
  if (archive.files.isEmpty || archive.files.length > maxPackageFiles) {
    throw const FormatException(
      'Installation package has an invalid file count.',
    );
  }
  final hasApp = archive.files.any(
    (file) =>
        file.isFile &&
        p.basename(file.name).toLowerCase() == 'moesketchpad.exe',
  );
  if (!hasApp) {
    throw const FormatException(
      'Installation package does not contain the app.',
    );
  }
  var totalSize = 0;
  for (final file in archive.files.where((file) => file.isFile)) {
    safePackageDestination(r'C:\moesketchpad-install-check', file.name);
    if (file.size < 0 || file.size > maxPackageFileSize) {
      throw FormatException('Invalid package entry size: ${file.name}');
    }
    totalSize += file.size;
    if (totalSize > maxPackageSize) {
      throw const FormatException('Installation package expands beyond 1 GiB.');
    }
  }
}

String safePackageDestination(String root, String archiveName) {
  final normalized = archiveName.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw FormatException('Unsafe package path: $archiveName');
  }
  final segments = normalized.split('/');
  if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
    throw FormatException('Unsafe package path: $archiveName');
  }
  final destination = p.normalize(p.joinAll([root, ...segments]));
  final rootPath = p.normalize(root);
  if (!p.isWithin(rootPath, destination)) {
    throw FormatException(
      'Package path escapes installation folder: $archiveName',
    );
  }
  return destination;
}
