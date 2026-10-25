// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceDocumentKeyStore {
  const DeviceDocumentKeyStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _keyName = 'document.device-key.v1';
  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _keyName);

  Future<String> readOrCreate() async {
    final existing = await read();
    if (existing != null && existing.length >= 64) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(48, (_) => random.nextInt(256));
    final key = base64UrlEncode(bytes);
    await _storage.write(key: _keyName, value: key);
    final stored = await read();
    if (stored != key) {
      throw StateError('Could not securely store the device document key.');
    }
    return key;
  }
}
