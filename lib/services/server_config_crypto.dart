import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'local_crypto.dart';

/// V3 config files use scrypt for key derivation and AES-256-GCM for
/// authenticated encryption. KDF parameters and envelope metadata are bound to
/// the ciphertext through the GCM associated data.
const serverConfigFormat = 'xylos.server-config';
const serverConfigV2Version = 2;
const serverConfigV3Version = 3;
const serverConfigV3CostN = 32768;
const serverConfigV3BlockSizeR = 8;
const serverConfigV3ParallelizationP = 1;

const _serverConfigV2Header = 'xylos.server-config|2';
const _serverConfigV3Header = 'xylos.server-config|3';
const _serverConfigV3Kdf = 'scrypt';
const _serverConfigV3Cipher = 'AES-256-GCM';
const _saltLength = 16;
const _nonceLength = 12;
const _tagLength = 16;
const _maxCiphertextBase64Length = 14 * 1024 * 1024;

int serverConfigEnvelopeVersion(Map<String, Object?> envelope) {
  final format = envelope['format'];
  if (format != serverConfigFormat) {
    throw const FormatException('Unsupported config format.');
  }
  final version = envelope['version'];
  if (version is! int) {
    throw const FormatException('Unsupported config version.');
  }
  return version;
}

Future<Map<String, Object>> encryptServerConfigV3(
  List<int> plaintext,
  String passphrase, {
  DateTime? exportedAt,
}) {
  final timestamp = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
  return Isolate.run(
    () => _encryptServerConfigV3(
      Uint8List.fromList(plaintext),
      passphrase,
      timestamp,
    ),
  );
}

Future<Object?> decryptServerConfig(
  Map<String, Object?> envelope,
  String passphrase,
) async {
  final version = serverConfigEnvelopeVersion(envelope);
  if (version == serverConfigV3Version) {
    _validateServerConfigV3Envelope(envelope);
    return Isolate.run(() => _decryptServerConfigV3(envelope, passphrase));
  }
  if (version == serverConfigV2Version) {
    return Isolate.run(
      () => decryptPayload(
        envelope,
        passphrase,
        header: _serverConfigV2Header,
      ),
    );
  }
  throw const FormatException('Unsupported config version.');
}

Map<String, Object> _encryptServerConfigV3(
  Uint8List plaintext,
  String passphrase,
  String exportedAt,
) {
  if (passphrase.isEmpty) {
    throw const FormatException('Passphrase is required.');
  }

  final random = Random.secure();
  final salt = _randomBytes(random, _saltLength);
  final nonce = _randomBytes(random, _nonceLength);
  final saltBase64 = base64Encode(salt);
  final nonceBase64 = base64Encode(nonce);
  final aad = _serverConfigV3Aad(
    exportedAt: exportedAt,
    salt: saltBase64,
    nonce: nonceBase64,
  );
  final key = _deriveKey(passphrase, salt);
  final encrypted = _aesGcm(true, key, nonce, aad, plaintext);
  if (encrypted.length < _tagLength) {
    throw StateError('Invalid AES-GCM output.');
  }
  final ciphertext = encrypted.sublist(0, encrypted.length - _tagLength);
  final tag = encrypted.sublist(encrypted.length - _tagLength);

  return <String, Object>{
    'format': serverConfigFormat,
    'version': serverConfigV3Version,
    'encrypted': true,
    'kdf': _serverConfigV3Kdf,
    'costN': serverConfigV3CostN,
    'blockSizeR': serverConfigV3BlockSizeR,
    'parallelizationP': serverConfigV3ParallelizationP,
    'cipher': _serverConfigV3Cipher,
    'exportedAt': exportedAt,
    'salt': saltBase64,
    'nonce': nonceBase64,
    'ciphertext': base64Encode(ciphertext),
    'tag': base64Encode(tag),
  };
}

Object? _decryptServerConfigV3(
  Map<String, Object?> envelope,
  String passphrase,
) {
  if (passphrase.isEmpty) {
    throw const FormatException('Passphrase is required.');
  }

  final exportedAt = envelope['exportedAt'] as String;
  final saltBase64 = envelope['salt'] as String;
  final nonceBase64 = envelope['nonce'] as String;
  final ciphertextBase64 = envelope['ciphertext'] as String;
  final tagBase64 = envelope['tag'] as String;
  final salt = base64Decode(saltBase64);
  final nonce = base64Decode(nonceBase64);
  final ciphertext = base64Decode(ciphertextBase64);
  final tag = base64Decode(tagBase64);
  final aad = _serverConfigV3Aad(
    exportedAt: exportedAt,
    salt: saltBase64,
    nonce: nonceBase64,
  );
  final key = _deriveKey(passphrase, salt);

  try {
    final plaintext = _aesGcm(
      false,
      key,
      nonce,
      aad,
      Uint8List.fromList([...ciphertext, ...tag]),
    );
    return jsonDecode(utf8.decode(plaintext));
  } on InvalidCipherTextException {
    throw const FormatException('Invalid passphrase or corrupted file.');
  }
}

void _validateServerConfigV3Envelope(Map<String, Object?> envelope) {
  if (envelope['encrypted'] != true ||
      envelope['kdf'] != _serverConfigV3Kdf ||
      envelope['costN'] != serverConfigV3CostN ||
      envelope['blockSizeR'] != serverConfigV3BlockSizeR ||
      envelope['parallelizationP'] != serverConfigV3ParallelizationP ||
      envelope['cipher'] != _serverConfigV3Cipher) {
    throw const FormatException('Unsupported config encryption parameters.');
  }

  final exportedAt = envelope['exportedAt'];
  final salt = envelope['salt'];
  final nonce = envelope['nonce'];
  final ciphertext = envelope['ciphertext'];
  final tag = envelope['tag'];
  if (exportedAt is! String ||
      DateTime.tryParse(exportedAt) == null ||
      salt is! String ||
      nonce is! String ||
      ciphertext is! String ||
      tag is! String) {
    throw const FormatException('Invalid config encryption parameters.');
  }
  if (ciphertext.length > _maxCiphertextBase64Length) {
    throw const FormatException('Config file is too large.');
  }
  if (_decodedLength(salt) != _saltLength ||
      _decodedLength(nonce) != _nonceLength ||
      _decodedLength(tag) != _tagLength) {
    throw const FormatException('Invalid config encryption parameters.');
  }
}

int _decodedLength(String value) {
  try {
    return base64Decode(value).length;
  } on FormatException {
    throw const FormatException('Invalid config encryption parameters.');
  }
}

String _serverConfigV3Aad({
  required String exportedAt,
  required String salt,
  required String nonce,
}) {
  return [
    _serverConfigV3Header,
    'format=$serverConfigFormat',
    'version=$serverConfigV3Version',
    'encrypted=true',
    'kdf=$_serverConfigV3Kdf',
    'costN=$serverConfigV3CostN',
    'blockSizeR=$serverConfigV3BlockSizeR',
    'parallelizationP=$serverConfigV3ParallelizationP',
    'cipher=$_serverConfigV3Cipher',
    'exportedAt=$exportedAt',
    'salt=$salt',
    'nonce=$nonce',
  ].join('\n');
}

Uint8List _deriveKey(String passphrase, Uint8List salt) {
  final derivator = Scrypt()
    ..init(
      ScryptParameters(
        serverConfigV3CostN,
        serverConfigV3BlockSizeR,
        serverConfigV3ParallelizationP,
        32,
        salt,
      ),
    );
  return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
}

Uint8List _aesGcm(
  bool forEncryption,
  Uint8List key,
  Uint8List nonce,
  String aad,
  Uint8List input,
) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      forEncryption,
      AEADParameters(
        KeyParameter(key),
        _tagLength * 8,
        nonce,
        Uint8List.fromList(utf8.encode(aad)),
      ),
    );
  return cipher.process(input);
}

Uint8List _randomBytes(Random random, int length) {
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}
