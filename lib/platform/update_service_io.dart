// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'update_service_stub.dart';

class UpdateService {
  const UpdateService();

  bool get supported => Platform.isWindows;

  static const _releaseUrl =
      'https://api.github.com/repos/Coloryi-MIAO/MoeSketchpad/releases/latest';
  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 3),
      followRedirects: true,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'MoeSketchpad-Updater',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ),
  );

  Future<AvailableUpdate?> check({required String currentVersion}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Automatic updates are only available on Windows.',
      );
    }
    final response = await _dio.get<Object?>(_releaseUrl);
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('GitHub returned an invalid release record.');
    }
    final tag = data['tag_name'];
    final htmlUrl = data['html_url'];
    final rawAssets = data['assets'];
    if (tag is! String || htmlUrl is! String || rawAssets is! List) {
      throw const FormatException('GitHub release is missing required fields.');
    }
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!_validVersion(version)) {
      throw FormatException('GitHub release has an invalid version tag: $tag');
    }
    if (_compareVersions(version, currentVersion) <= 0) return null;

    final assets = <String, String>{};
    for (final asset in rawAssets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String && url is String) assets[name] = url;
    }
    const packageName = 'moesketchpad-setup-windows-x64.zip';
    final downloadUrl = assets[packageName];
    final sha256Url = assets['$packageName.sha256'];
    if (downloadUrl == null || sha256Url == null) {
      throw const FormatException(
        'Latest GitHub release does not contain the Windows installer and SHA-256 file.',
      );
    }
    _requireGithubReleaseUrl(downloadUrl);
    _requireGithubReleaseUrl(sha256Url);
    return AvailableUpdate(
      version: version,
      releaseUrl: htmlUrl,
      downloadUrl: downloadUrl,
      sha256Url: sha256Url,
    );
  }

  Future<String> downloadInstaller(AvailableUpdate update) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Automatic updates are only available on Windows.',
      );
    }
    final directory = Directory(
      p.join(Directory.systemTemp.path, 'moesketchpad-update'),
    );
    await directory.create(recursive: true);
    final packageFile = File(p.join(directory.path, 'installer.zip'));
    final checksumResponse = await _dio.get<String>(
      update.sha256Url,
      options: Options(responseType: ResponseType.plain),
    );
    _requireGithubReleaseUrl(checksumResponse.realUri.toString());
    final expected = RegExp(
      r'^\s*([0-9a-fA-F]{64})(?:\s+\*?.+)?\s*$',
    ).firstMatch(checksumResponse.data ?? '')?.group(1)?.toLowerCase();
    if (expected == null) {
      throw const FormatException('Release SHA-256 file is invalid.');
    }
    final download = await _dio.get<List<int>>(
      update.downloadUrl,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        receiveDataWhenStatusError: false,
      ),
    );
    _requireGithubReleaseUrl(download.realUri.toString());
    final bytes = download.data;
    if (bytes == null || bytes.isEmpty || bytes.length > 1024 * 1024 * 1024) {
      throw const FormatException('Downloaded installer has an invalid size.');
    }
    if (sha256.convert(bytes).toString() != expected) {
      throw const FormatException('Downloaded installer checksum mismatch.');
    }
    await packageFile.writeAsBytes(bytes, flush: true);
    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = archive.files.where((item) => item.isFile).toList();
    if (entries.isEmpty || entries.length > 20000) {
      throw const FormatException('Downloaded installer archive is invalid.');
    }
    final totalSize = entries.fold<int>(0, (sum, entry) => sum + entry.size);
    if (totalSize > 2 * 1024 * 1024 * 1024) {
      throw const FormatException('Downloaded installer expands beyond 2 GiB.');
    }
    final extractDir = Directory(p.join(directory.path, 'package'));
    if (await extractDir.exists()) await extractDir.delete(recursive: true);
    await extractDir.create(recursive: true);
    String? installerPath;
    for (final entry in entries) {
      final target = _archiveTarget(extractDir.path, entry.name);
      if (entry.size > 256 * 1024 * 1024) {
        throw FormatException(
          'Installer archive entry is invalid: ${entry.name}',
        );
      }
      final content = entry.content as List<int>;
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(content, flush: true);
      if (p.basename(target).toLowerCase() == 'moesketchpad_installer.exe') {
        installerPath = target;
      }
    }
    if (installerPath == null) {
      throw const FormatException('Installer executable was not found.');
    }
    return installerPath;
  }

  Future<void> launchInstaller(String path) async {
    final file = File(path);
    if (!await file.exists() ||
        p.basename(path).toLowerCase() != 'moesketchpad_installer.exe') {
      throw const FormatException('Verified installer executable is missing.');
    }
    await Process.start(
      file.path,
      [
        '--wait-pid=$pid',
        '--install-dir=${p.dirname(Platform.resolvedExecutable)}',
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: file.parent.path,
    );
    await windowManager.destroy();
  }
}

void _requireGithubReleaseUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !const {
        'github.com',
        'objects.githubusercontent.com',
        'release-assets.githubusercontent.com',
      }.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const FormatException(
      'Release asset URL is not an allowed GitHub URL.',
    );
  }
}

bool _validVersion(String value) =>
    RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(value);

int _compareVersions(String first, String second) {
  final a = first.split('-').first.split('.').map(int.parse).toList();
  final b = second.split('-').first.split('.').map(int.parse).toList();
  for (var i = 0; i < math.max(a.length, b.length); i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  final firstPre = first.contains('-');
  final secondPre = second.contains('-');
  if (firstPre != secondPre) return firstPre ? -1 : 1;
  return 0;
}

String _archiveTarget(String root, String name) {
  final normalized = name.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.split('/').any((part) => part == '..' || part.isEmpty)) {
    throw FormatException('Unsafe installer archive path: $name');
  }
  final target = p.normalize(p.joinAll([root, ...normalized.split('/')]));
  if (!p.isWithin(p.normalize(root), target)) {
    throw FormatException(
      'Installer archive path escapes staging directory: $name',
    );
  }
  return target;
}
