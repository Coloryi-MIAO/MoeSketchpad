// SPDX-License-Identifier: GPL-3.0-only
/// MoeSketchpad encrypted binary container, format version 2.
///
/// Layout (big-endian):
///  0  12  magic "MOESKETCHPAD"
/// 12   2  format version (2)
/// 14   2  flags: 1=encrypted, 2=gzip, 4=encrypted thumbnail
/// 16   1  KDF id (1=Argon2id)
/// 17   4  Argon2id memory KiB
/// 21   4  Argon2id iterations
/// 25   1  Argon2id parallelism
/// 26   1  salt length (16)
/// 27  16  salt
/// 43   1  nonce length (12)
/// 44  12  AES-GCM nonce
/// 56   8  plaintext length
/// 64   8  ciphertext length
/// 72   N  ciphertext
/// 72+N 16 GCM authentication tag
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';

import '../geometry/object.dart';

class MspFormatException implements Exception {
  const MspFormatException(this.message);
  final String message;
  @override
  String toString() => 'MspFormatException: $message';
}

class MspDecryptionException implements Exception {
  const MspDecryptionException([
    this.message = 'Unable to decrypt document. Check the password.',
  ]);
  final String message;
  @override
  String toString() => 'MspDecryptionException: $message';
}

class MspValidation {
  const MspValidation({
    required this.version,
    required this.flags,
    required this.kdf,
    required this.plainLength,
    required this.cipherLength,
    required this.authenticated,
  });

  final int version;
  final int flags;
  final String kdf;
  final int plainLength;
  final int cipherLength;
  final bool authenticated;

  bool get encrypted => flags & 1 != 0;
  bool get compressed => flags & 2 != 0;
  bool get hasThumbnail => flags & 4 != 0;

  Map<String, Object?> toJson() => {
    'validHeader': true,
    'version': version,
    'encrypted': encrypted,
    'compressed': compressed,
    'hasThumbnail': hasThumbnail,
    'kdf': kdf,
    'plainBytes': plainLength,
    'cipherBytes': cipherLength,
    'authenticated': authenticated,
  };
}

class MspCodec {
  MspCodec({
    this.maxFileBytes = 64 * 1024 * 1024,
    this.maxPayloadBytes = 32 * 1024 * 1024,
  });

  static const int currentVersion = 2;
  static const int _headerLength = 72;
  static const int _tagLength = 16;
  static const int _encryptedFlag = 1;
  static const int _compressedFlag = 2;
  static const int _thumbnailFlag = 4;
  static const int _argon2id = 1;
  static const int _memoryKiB = 19 * 1024;
  static const int _iterations = 2;
  static const int _parallelism = 1;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const List<int> _magic = [
    0x4d,
    0x4f,
    0x45,
    0x53,
    0x4b,
    0x45,
    0x54,
    0x43,
    0x48,
    0x50,
    0x41,
    0x44,
  ];

  final int maxFileBytes;
  final int maxPayloadBytes;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> encode(
    GeometryDocument document, {
    required String password,
    bool compress = true,
  }) async {
    if (password.isEmpty) {
      throw const MspFormatException('A non-empty password is required.');
    }
    final json = const JsonEncoder().convert(document.toJson());
    final plain = Uint8List.fromList(utf8.encode(json));
    if (plain.length > maxPayloadBytes) {
      throw const MspFormatException(
        'Document payload exceeds the plaintext size limit.',
      );
    }
    var payload = plain;
    var compressed = false;
    if (compress) {
      final gzip = GZipEncoder().encodeBytes(plain, level: 6);
      if (gzip.length < plain.length) {
        payload = Uint8List.fromList(gzip);
        compressed = true;
      }
    }
    if (payload.length > maxPayloadBytes) {
      throw const MspFormatException('Compressed payload is too large.');
    }
    final hasThumbnail = document.metadata.containsKey('thumbnail');
    final flags =
        _encryptedFlag |
        (compressed ? _compressedFlag : 0) |
        (hasThumbnail ? _thumbnailFlag : 0);
    final salt = List<int>.generate(
      _saltLength,
      (_) => Random.secure().nextInt(256),
    );
    final nonce = _cipher.newNonce();
    final key = await _deriveKey(password, salt);
    final header = _makeHeader(
      flags: flags,
      salt: salt,
      nonce: nonce,
      plainLength: plain.length,
      cipherLength: payload.length,
    );
    final box = await _cipher.encrypt(
      payload,
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
        'Encoded document exceeds the file limit.',
      );
    }
    return result;
  }

  Future<GeometryDocument> decode(
    List<int> bytes, {
    required String password,
  }) async {
    final header = _parseHeader(bytes);
    if (password.isEmpty) throw const MspDecryptionException();
    final payloadEnd = _headerLength + header.cipherLength;
    final ciphertext = Uint8List.fromList(
      bytes.sublist(_headerLength, payloadEnd),
    );
    final tag = bytes.sublist(payloadEnd);
    try {
      final key = await _deriveKey(password, header.salt);
      final plain = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: header.nonce, mac: Mac(tag)),
        secretKey: key,
        aad: Uint8List.fromList(bytes.sublist(0, _headerLength)),
      );
      if (plain.length > maxPayloadBytes ||
          (header.flags & _compressedFlag == 0 &&
              plain.length != header.plainLength)) {
        throw const MspFormatException(
          'Decrypted payload has an invalid size.',
        );
      }
      Uint8List decoded;
      if (header.flags & _compressedFlag != 0) {
        try {
          decoded = GZipDecoder().decodeBytes(
            plain,
            verify: true,
            maxOutputSize: maxPayloadBytes + 1,
          );
        } on ArchiveException {
          throw const MspFormatException(
            'Compressed payload is malformed or exceeds the size limit.',
          );
        } on FormatException {
          throw const MspFormatException('Compressed payload is malformed.');
        }
        if (decoded.length != header.plainLength) {
          throw const MspFormatException(
            'Decompressed payload length does not match the header.',
          );
        }
      } else {
        decoded = Uint8List.fromList(plain);
      }
      if (decoded.length > maxPayloadBytes) {
        throw const MspFormatException('Decrypted payload is too large.');
      }
      final json = jsonDecode(utf8.decode(decoded));
      if (json is! Map) {
        throw const MspFormatException('Document payload must be an object.');
      }
      return GeometryDocument.fromJson(Map<String, Object?>.from(json));
    } on MspFormatException {
      rethrow;
    } on MspDecryptionException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const MspDecryptionException();
    } on FormatException {
      throw const MspFormatException('Document payload is malformed.');
    } catch (_) {
      throw const MspDecryptionException();
    }
  }

  MspValidation validate(List<int> bytes) {
    final header = _parseHeader(bytes);
    return MspValidation(
      version: header.version,
      flags: header.flags,
      kdf: 'Argon2id',
      plainLength: header.plainLength,
      cipherLength: header.cipherLength,
      authenticated: false,
    );
  }

  GeometryDocument migrate(Map<String, Object?> payload) {
    if (payload['format'] != 'moesketchpad-document') {
      throw const MspFormatException('Unsupported document payload.');
    }
    return GeometryDocument.fromJson(payload);
  }

  String exportJson(GeometryDocument document) =>
      const JsonEncoder.withIndent('  ').convert(document.toJson());

  GeometryDocument importJson(String source) {
    if (source.length > maxPayloadBytes) {
      throw const MspFormatException('JSON source exceeds the size limit.');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const MspFormatException('JSON document must be an object.');
    }
    return migrate(Map<String, Object?>.from(decoded));
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
    required int plainLength,
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
    data.setUint8(offset++, _parallelism);
    data.setUint8(offset++, salt.length);
    for (final byte in salt) {
      data.setUint8(offset++, byte);
    }
    data.setUint8(offset++, nonce.length);
    for (final byte in nonce) {
      data.setUint8(offset++, byte);
    }
    data.setUint64(offset, plainLength, Endian.big);
    offset += 8;
    data.setUint64(offset, cipherLength, Endian.big);
    return data.buffer.asUint8List();
  }

  _Header _parseHeader(List<int> bytes) {
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
    final version = data.getUint16(12, Endian.big);
    if (version != currentVersion) {
      throw MspFormatException('Unsupported document version $version.');
    }
    final flags = data.getUint16(14, Endian.big);
    if (flags & ~(_encryptedFlag | _compressedFlag | _thumbnailFlag) != 0 ||
        flags & _encryptedFlag == 0) {
      throw const MspFormatException('Unsupported document flags.');
    }
    if (data.getUint8(16) != _argon2id ||
        data.getUint32(17, Endian.big) != _memoryKiB ||
        data.getUint32(21, Endian.big) != _iterations ||
        data.getUint8(25) != _parallelism) {
      throw const MspFormatException('Unsupported key derivation parameters.');
    }
    final saltLength = data.getUint8(26);
    if (saltLength != _saltLength) {
      throw const MspFormatException('Invalid salt length.');
    }
    final salt = bytes.sublist(27, 43);
    final nonceLength = data.getUint8(43);
    if (nonceLength != _nonceLength) {
      throw const MspFormatException('Invalid nonce length.');
    }
    final nonce = bytes.sublist(44, 56);
    final plainLength = data.getUint64(56, Endian.big);
    final cipherLength = data.getUint64(64, Endian.big);
    if (plainLength > maxPayloadBytes ||
        cipherLength > maxPayloadBytes ||
        _headerLength + cipherLength + _tagLength != bytes.length) {
      throw const MspFormatException('Invalid payload length.');
    }
    return _Header(
      version: version,
      flags: flags,
      salt: salt,
      nonce: nonce,
      plainLength: plainLength,
      cipherLength: cipherLength,
    );
  }
}

class _Header {
  const _Header({
    required this.version,
    required this.flags,
    required this.salt,
    required this.nonce,
    required this.plainLength,
    required this.cipherLength,
  });

  final int version;
  final int flags;
  final List<int> salt;
  final List<int> nonce;
  final int plainLength;
  final int cipherLength;
}
