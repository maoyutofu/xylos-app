import 'dart:convert';

import '../models/webdav_account.dart';
import 'local_crypto.dart';

const serverQrPayloadPrefix = 'xylos.server-qr:';
const _serverQrPayloadFormat = 'xylos.server-qr';
const _serverQrPayloadHeader = 'xylos.server-qr|1';

String encodeServerQrPayload(WebDavAccount server, String passphrase) {
  final plaintext = utf8.encode(
    jsonEncode({
      'server': {
        ...server.toJson(),
        'secret': server.secret,
      },
    }),
  );
  final encrypted = encryptPayload(
    plaintext,
    passphrase,
    header: _serverQrPayloadHeader,
  );
  final payload = <String, Object?>{
    'format': _serverQrPayloadFormat,
    'version': 1,
    'encrypted': true,
    'kdf': encrypted['kdf'],
    'cipher': encrypted['cipher'],
    'salt': encrypted['salt'],
    'nonce': encrypted['nonce'],
    'iterations': encrypted['iterations'],
    'ciphertext': encrypted['ciphertext'],
    'mac': encrypted['mac'],
  };
  return '$serverQrPayloadPrefix${_base64UrlEncodeUtf8(jsonEncode(payload))}';
}

WebDavAccount decodeServerQrPayload(String content, String passphrase) {
  if (!content.startsWith(serverQrPayloadPrefix)) {
    throw const FormatException('Unsupported QR code format.');
  }
  final encoded = content.substring(serverQrPayloadPrefix.length).trim();
  if (encoded.isEmpty) {
    throw const FormatException('Empty QR code payload.');
  }
  final decoded = jsonDecode(_base64UrlDecodeUtf8(encoded));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Invalid QR code payload.');
  }
  final format = decoded['format'] as String? ?? '';
  final version = decoded['version'] as int? ?? 0;
  if (format != _serverQrPayloadFormat || version != 1) {
    throw const FormatException('Unsupported QR code format.');
  }
  final decrypted = decryptPayload(
    decoded,
    passphrase,
    header: _serverQrPayloadHeader,
  );
  if (decrypted is! Map<String, Object?>) {
    throw const FormatException('Invalid decrypted QR payload.');
  }
  final rawServer = decrypted['server'];
  if (rawServer is! Map) {
    throw const FormatException('Missing server payload.');
  }
  return WebDavAccount.fromJson(Map<String, Object?>.from(rawServer));
}

String _base64UrlEncodeUtf8(String value) {
  return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}

String _base64UrlDecodeUtf8(String value) {
  final normalized = switch (value.length % 4) {
    0 => value,
    2 => '$value==',
    3 => '$value=',
    _ => throw const FormatException('Invalid base64 payload.'),
  };
  return utf8.decode(base64Url.decode(normalized));
}
