import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Map<String, Object> encryptPayload(
  List<int> plaintext,
  String passphrase, {
  required String header,
  int iterations = 100000,
}) {
  final random = Random.secure();
  final salt = Uint8List.fromList(
    List<int>.generate(16, (_) => random.nextInt(256)),
  );
  final nonce = Uint8List.fromList(
    List<int>.generate(16, (_) => random.nextInt(256)),
  );
  final keyMaterial = _pbkdf2Sha256(
    utf8.encode(passphrase),
    salt,
    iterations,
    64,
  );
  final encKey = keyMaterial.sublist(0, 32);
  final macKey = keyMaterial.sublist(32, 64);
  final ciphertext = _xorWithKeystream(plaintext, encKey, nonce);
  final mac = Hmac(
    sha256,
    macKey,
  ).convert([...utf8.encode(header), ...salt, ...nonce, ...ciphertext]).bytes;
  return {
    'kdf': 'PBKDF2-HMAC-SHA256',
    'cipher': 'HMAC-SHA256-CTR-XOR',
    'salt': base64Encode(salt),
    'nonce': base64Encode(nonce),
    'iterations': iterations,
    'ciphertext': base64Encode(ciphertext),
    'mac': base64Encode(mac),
  };
}

Object? decryptPayload(
  Map<String, Object?> payload,
  String passphrase, {
  required String header,
}) {
  final salt = base64Decode(payload['salt'] as String? ?? '');
  final nonce = base64Decode(payload['nonce'] as String? ?? '');
  final ciphertext = base64Decode(payload['ciphertext'] as String? ?? '');
  final mac = base64Decode(payload['mac'] as String? ?? '');
  final iterations = payload['iterations'] as int? ?? 0;
  if (iterations <= 0) {
    throw const FormatException('Invalid encryption parameters.');
  }

  final keyMaterial = _pbkdf2Sha256(
    utf8.encode(passphrase),
    salt,
    iterations,
    64,
  );
  final encKey = keyMaterial.sublist(0, 32);
  final macKey = keyMaterial.sublist(32, 64);
  final expectedMac = Hmac(
    sha256,
    macKey,
  ).convert([...utf8.encode(header), ...salt, ...nonce, ...ciphertext]).bytes;
  if (!_constantTimeEquals(mac, expectedMac)) {
    throw const FormatException('Invalid passphrase or corrupted file.');
  }

  final plaintext = _xorWithKeystream(ciphertext, encKey, nonce);
  return jsonDecode(utf8.decode(plaintext));
}

List<int> _pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) {
  final hmacSha256 = Hmac(sha256, password);
  final blockCount = (length / 32).ceil();
  final output = <int>[];
  for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
    final blockSalt = <int>[
      ...salt,
      (blockIndex >> 24) & 0xff,
      (blockIndex >> 16) & 0xff,
      (blockIndex >> 8) & 0xff,
      blockIndex & 0xff,
    ];
    var u = hmacSha256.convert(blockSalt).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmacSha256.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    output.addAll(t);
  }
  return output.sublist(0, length);
}

List<int> _xorWithKeystream(
  List<int> input,
  List<int> key,
  List<int> nonce,
) {
  final output = List<int>.filled(input.length, 0);
  var counter = 0;
  var offset = 0;
  while (offset < input.length) {
    final block = Hmac(
      sha256,
      key,
    ).convert([
      ...nonce,
      (counter >> 24) & 0xff,
      (counter >> 16) & 0xff,
      (counter >> 8) & 0xff,
      counter & 0xff,
    ]).bytes;
    for (var i = 0; i < block.length && offset + i < input.length; i++) {
      output[offset + i] = input[offset + i] ^ block[i];
    }
    offset += block.length;
    counter++;
  }
  return output;
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i];
  }
  return diff == 0;
}
