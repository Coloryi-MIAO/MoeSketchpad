// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'geometry.dart';

class MspFormatException implements Exception {
  const MspFormatException(this.message);
  final String message;
  @override
  String toString() => 'MspFormatException: $message';
}

class MspDecryptionException implements Exception {
  const MspDecryptionException();
  @override
  String toString() => 'MspDecryptionException: Unable to decrypt document.';
}

class MspCodec {
  MspCodec({
    this.maxFileBytes = 64 * 1024 * 1024,
    this.maxPayloadBytes = 32 * 1024 * 1024,
  });

  static const int currentVersion = 1;
  static const int _headerLength = 57;
  static const int _tagLength = 16;
  static const int _encryptedFlag = 1;
  static const int _compressedFlag = 2;
  static const int _argon2id = 1;
  static const int _memoryKiB = 19 * 1024;
  static const int _iterations = 2;
  static const int _parallelism = 1;
  static const List<int> _magic = [0x4d, 0x53, 0x50, 0x31];

  final int maxFileBytes;
  final int maxPayloadBytes;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> encode(
    GeometryDocument document, {
    required String password,
  }) async {
    if (password.isEmpty) {
      throw const MspFormatException('A non-empty password is required.');
    }
    final plain = utf8.encode(jsonEncode(document.toJson()));
    if (plain.length > maxPayloadBytes) {
      throw const MspFormatException(
        'Document payload exceeds the size limit.',
      );
    }

    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = _cipher.newNonce();
    final key = await _deriveKey(password, salt);
    final cipherLength = plain.length;
    final header = _makeHeader(
      flags: _encryptedFlag,
      salt: salt,
      nonce: nonce,
      cipherLength: cipherLength,
    );
    final box = await _cipher.encrypt(
      plain,
      secretKey: key,
      nonce: nonce,
      aad: header,
    );
    final result = Uint8List.fromList([
      ...header,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    if (result.length > maxFileBytes) {
      throw const MspFormatException(
        'Encoded document exceeds the size limit.',
      );
    }
    return result;
  }

  Future<GeometryDocument> decode(
    List<int> bytes, {
    required String password,
  }) async {
    final header = _parseHeader(bytes);
    if (header.flags & _compressedFlag != 0) {
      throw const MspFormatException(
        'Compressed payloads are reserved but unsupported in format version 1.',
      );
    }
    if (password.isEmpty) {
      throw const MspDecryptionException();
    }
    final ciphertextEnd = _headerLength + header.cipherLength;
    final ciphertext = bytes.sublist(_headerLength, ciphertextEnd);
    final tag = bytes.sublist(ciphertextEnd);
    try {
      final key = await _deriveKey(password, header.salt);
      final plain = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: header.nonce, mac: Mac(tag)),
        secretKey: key,
        aad: bytes.sublist(0, _headerLength),
      );
      if (plain.length > maxPayloadBytes) {
        throw const MspFormatException(
          'Decrypted payload exceeds the size limit.',
        );
      }
      final json = jsonDecode(utf8.decode(plain));
      if (json is! Map<String, dynamic>) {
        throw const MspFormatException(
          'Document payload must be a JSON object.',
        );
      }
      return GeometryDocument.fromJson(json);
    } on MspFormatException {
      rethrow;
    } on FormatException {
      throw const MspFormatException('Document payload is malformed.');
    } catch (_) {
      throw const MspDecryptionException();
    }
  }

  Map<String, Object> validate(List<int> bytes) {
    final header = _parseHeader(bytes);
    return {
      'validHeader': true,
      'version': header.version,
      'encrypted': header.flags & _encryptedFlag != 0,
      'compressed': header.flags & _compressedFlag != 0,
      'cipherBytes': header.cipherLength,
      'authenticated': false,
    };
  }

  GeometryDocument migrate(GeometryDocument document) => document;

  String exportJson(GeometryDocument document) =>
      const JsonEncoder.withIndent('  ').convert(document.toJson());

  GeometryDocument importJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const MspFormatException('JSON document must be an object.');
    }
    return GeometryDocument.fromJson(decoded);
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) => Argon2id(
    memory: _memoryKiB,
    iterations: _iterations,
    parallelism: _parallelism,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  Uint8List _makeHeader({
    required int flags,
    required List<int> salt,
    required List<int> nonce,
    required int cipherLength,
  }) {
    final data = ByteData(_headerLength);
    var offset = 0;
    for (final byte in _magic) {
      data.setUint8(offset++, byte);
    }
    data.setUint16(offset, currentVersion, Endian.big);
    offset += 2;
    data.setUint16(offset, flags, Endian.big);
    offset += 2;
    data.setUint8(offset++, _argon2id);
    data.setUint32(offset, _memoryKiB, Endian.big);
    offset += 4;
    data.setUint32(offset, _iterations, Endian.big);
    offset += 4;
    data.setUint32(offset, _parallelism, Endian.big);
    offset += 4;
    data.buffer.asUint8List().setRange(offset, offset + salt.length, salt);
    offset += salt.length;
    data.buffer.asUint8List().setRange(offset, offset + nonce.length, nonce);
    offset += nonce.length;
    data.setUint64(offset, cipherLength, Endian.big);
    return data.buffer.asUint8List();
  }

  _MspHeader _parseHeader(List<int> bytes) {
    if (bytes.length > maxFileBytes ||
        bytes.length < _headerLength + _tagLength) {
      throw const MspFormatException('Invalid document length.');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    for (var i = 0; i < _magic.length; i++) {
      if (data.getUint8(i) != _magic[i]) {
        throw const MspFormatException('Unrecognized MoeSketchpad file.');
      }
    }
    final version = data.getUint16(4, Endian.big);
    if (version != currentVersion) {
      throw MspFormatException('Unsupported document version $version.');
    }
    final flags = data.getUint16(6, Endian.big);
    if (flags & ~(_encryptedFlag | _compressedFlag) != 0 ||
        flags & _encryptedFlag == 0) {
      throw const MspFormatException('Unsupported document flags.');
    }
    if (data.getUint8(8) != _argon2id ||
        data.getUint32(9, Endian.big) != _memoryKiB ||
        data.getUint32(13, Endian.big) != _iterations ||
        data.getUint32(17, Endian.big) != _parallelism) {
      throw const MspFormatException('Unsupported key derivation parameters.');
    }
    final salt = bytes.sublist(21, 37);
    final nonce = bytes.sublist(37, 49);
    final cipherLength = data.getUint64(49, Endian.big);
    if (cipherLength > maxPayloadBytes ||
        _headerLength + cipherLength + _tagLength != bytes.length) {
      throw const MspFormatException('Invalid ciphertext length.');
    }
    return _MspHeader(
      version: version,
      flags: flags,
      salt: salt,
      nonce: nonce,
      cipherLength: cipherLength,
    );
  }
}

class _MspHeader {
  const _MspHeader({
    required this.version,
    required this.flags,
    required this.salt,
    required this.nonce,
    required this.cipherLength,
  });

  final int version;
  final int flags;
  final List<int> salt;
  final List<int> nonce;
  final int cipherLength;
}
