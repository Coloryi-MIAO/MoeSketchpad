// SPDX-License-Identifier: GPL-3.0-only
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.sha256Url,
  });

  final String version;
  final String releaseUrl;
  final String downloadUrl;
  final String sha256Url;
}

class UpdateService {
  const UpdateService();

  bool get supported => false;

  Future<AvailableUpdate?> check({required String currentVersion}) async =>
      null;

  Future<String> downloadInstaller(AvailableUpdate update) async =>
      throw UnsupportedError(
        'Automatic updates are only available on Windows.',
      );

  Future<void> launchInstaller(String path) async => throw UnsupportedError(
    'Automatic updates are only available on Windows.',
  );
}
