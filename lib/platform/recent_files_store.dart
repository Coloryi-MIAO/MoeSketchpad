// SPDX-License-Identifier: GPL-3.0-only
import 'package:shared_preferences/shared_preferences.dart';

class RecentFilesStore {
  const RecentFilesStore();

  static const _key = 'recentDocuments';
  static const _limit = 12;

  Future<List<String>> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_key) ?? const [];
  }

  Future<List<String>> record(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty || normalized.length > 2048) {
      throw ArgumentError.value(path, 'path', 'Invalid recent document path.');
    }
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getStringList(_key) ?? const <String>[];
    final files = <String>[
      normalized,
      for (final item in previous)
        if (item != normalized) item,
    ].take(_limit).toList(growable: false);
    final saved = await preferences.setStringList(_key, files);
    if (!saved) {
      throw StateError('Could not persist the recent document list.');
    }
    return files;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    final removed = await preferences.remove(_key);
    if (!removed) {
      throw StateError('Could not clear the recent document list.');
    }
  }
}
