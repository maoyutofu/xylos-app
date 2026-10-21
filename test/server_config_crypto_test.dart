import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xylos/services/local_crypto.dart';
import 'package:xylos/services/server_config_crypto.dart';

void main() {
  const passphrase = 'correct horse battery staple';
  final plaintext = utf8.encode(
    jsonEncode({
      'servers': [
        {
          'id': 'server-1',
          'name': 'Office NAS',
          'secret': 's3cr3t-token',
        },
      ],
    }),
  );
  final exportedAt = DateTime.utc(2026, 10, 21, 12);

  test('encrypts and decrypts a V3 server config', () async {
    final envelope = await encryptServerConfigV3(
      plaintext,
      passphrase,
      exportedAt: exportedAt,
    );

    expect(envelope['format'], serverConfigFormat);
    expect(envelope['version'], serverConfigV3Version);
    expect(envelope['kdf'], 'scrypt');
    expect(envelope['costN'], serverConfigV3CostN);
    expect(envelope['blockSizeR'], serverConfigV3BlockSizeR);
    expect(envelope['parallelizationP'], serverConfigV3ParallelizationP);
    expect(envelope['cipher'], 'AES-256-GCM');
    expect(envelope['ciphertext'], isNot(contains('s3cr3t-token')));

    final decrypted = await decryptServerConfig(envelope, passphrase);
    expect(decrypted, jsonDecode(utf8.decode(plaintext)));
  });

  test('rejects an incorrect V3 passphrase', () async {
    final envelope = await encryptServerConfigV3(
      plaintext,
      passphrase,
      exportedAt: exportedAt,
    );

    await expectLater(
      decryptServerConfig(envelope, 'wrong passphrase'),
      throwsFormatException,
    );
  });

  test('authenticates V3 envelope metadata', () async {
    final envelope = await encryptServerConfigV3(
      plaintext,
      passphrase,
      exportedAt: exportedAt,
    );
    final tampered = Map<String, Object?>.from(envelope)
      ..['exportedAt'] =
          exportedAt.add(const Duration(days: 1)).toIso8601String();

    await expectLater(
      decryptServerConfig(tampered, passphrase),
      throwsFormatException,
    );
  });

  test('rejects unsupported V3 parameters before deriving a key', () async {
    final envelope = await encryptServerConfigV3(
      plaintext,
      passphrase,
      exportedAt: exportedAt,
    );
    final tampered = Map<String, Object?>.from(envelope)..['costN'] = 1024;

    await expectLater(
      decryptServerConfig(tampered, passphrase),
      throwsFormatException,
    );
  });

  test('decrypts legacy V2 server configs', () async {
    final encrypted = encryptPayload(
      plaintext,
      passphrase,
      header: 'xylos.server-config|2',
    );
    final envelope = <String, Object?>{
      'format': serverConfigFormat,
      'version': serverConfigV2Version,
      'encrypted': true,
      ...encrypted,
    };

    final decrypted = await decryptServerConfig(envelope, passphrase);
    expect(decrypted, jsonDecode(utf8.decode(plaintext)));
  });
}
