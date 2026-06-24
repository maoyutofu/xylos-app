import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../models/webdav_account.dart';
import '../models/webdav_resource.dart';
import 'app_logger.dart';

class WebDavClient {
  WebDavClient(this.account);

  final WebDavAccount account;
  static final Map<String, _DigestSession> _digestSessions = {};

  Uri resourceUri(String path) {
    return _resolveUri(path);
  }

  Map<String, String> authorizationHeaders() {
    switch (account.authType) {
      case AuthType.basic:
        final token =
            base64Encode(utf8.encode('${account.username}:${account.secret}'));
        return {HttpHeaders.authorizationHeader: 'Basic $token'};
      case AuthType.digest:
        return const {};
      case AuthType.bearer:
        return {HttpHeaders.authorizationHeader: 'Bearer ${account.secret}'};
    }
  }

  Future<void> testConnection() async {
    AppLogger.debug(
      'WebDAV',
      'testConnection baseUrl=${_safeUri(Uri.parse(account.baseUrl))} defaultPath=${account.defaultPath} auth=${account.authType.name} allowHttp=${account.allowHttp} trustSelfSignedCert=${account.trustSelfSignedCert}',
    );
    final response = await _request('OPTIONS', account.defaultPath);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavException.fromStatus(response.statusCode, response.body);
    }
  }

  Future<List<WebDavResource>> list(String path) async {
    AppLogger.debug('WebDAV', 'list path=$path');
    final response = await _request(
      'PROPFIND',
      path,
      headers: const {'Depth': '1'},
      body: utf8.encode(_propfindBody),
      contentType: 'application/xml; charset=utf-8',
    );

    if (response.statusCode != 207) {
      throw WebDavException.fromStatus(response.statusCode, response.body);
    }

    final resources = _parsePropfind(response.body);
    AppLogger.debug('WebDAV', 'parsed PROPFIND resources=${resources.length}');
    final normalizedCurrentPath = _normalizeDirectoryPath(path);
    return resources
        .where((resource) => resource.path != normalizedCurrentPath)
        .toList()
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  Future<void> uploadFile(String remotePath, File file) async {
    final bytes = await file.readAsBytes();
    AppLogger.debug(
      'WebDAV',
      'uploadFile remotePath=$remotePath localPath=${file.path} bytes=${bytes.length}',
    );
    await uploadBytes(remotePath, bytes);
  }

  Future<void> uploadBytes(String remotePath, List<int> bytes) async {
    AppLogger.debug(
      'WebDAV',
      'uploadBytes remotePath=$remotePath bytes=${bytes.length}',
    );
    final response = await _request(
      'PUT',
      remotePath,
      body: bytes,
      contentType: 'application/octet-stream',
    );
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw WebDavException.fromStatus(response.statusCode, response.body);
    }
  }

  Future<List<int>> downloadBytes(String path) async {
    AppLogger.debug('WebDAV', 'downloadBytes path=$path');
    final response = await _request('GET', path, decodeBodyAsText: false);
    if (response.statusCode != 200) {
      throw WebDavException.fromStatus(response.statusCode, response.bodyText);
    }
    return response.bodyBytes;
  }

  Future<void> createDirectory(String path) async {
    AppLogger.debug('WebDAV', 'createDirectory path=$path');
    final response = await _request('MKCOL', path);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw WebDavException.fromStatus(response.statusCode, response.body);
    }
  }

  Future<void> delete(String path) async {
    AppLogger.debug('WebDAV', 'delete path=$path');
    final response = await _request('DELETE', path);
    if (response.statusCode != 200 &&
        response.statusCode != 202 &&
        response.statusCode != 204) {
      throw WebDavException.fromStatus(response.statusCode, response.body);
    }
  }

  Future<_WebDavResponse> _request(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
    String? contentType,
    bool decodeBodyAsText = true,
  }) async {
    final uri = _resolveUri(path);
    final safeUri = _safeUri(uri);
    if (uri.scheme == 'http' && !account.allowHttp) {
      AppLogger.error(
        'WebDAV',
        'blocked insecure HTTP request method=$method url=$safeUri allowHttp=false',
      );
      throw const WebDavException(WebDavFailureKind.httpDisabled);
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    if (account.trustSelfSignedCert) {
      client.badCertificateCallback = (_, __, ___) => true;
    }

    try {
      final stopwatch = Stopwatch()..start();
      if (account.authType == AuthType.digest &&
          _digestSession == null &&
          body != null) {
        await _primeDigestSession(client, uri: uri, safeUri: safeUri);
      }
      AppLogger.debug(
        'WebDAV',
        '-> $method $safeUri headers=${_safeHeaders(headers, contentType)} bodyBytes=${body?.length ?? 0}',
      );
      final request = await client.openUrl(method, uri);
      final cachedDigestSession = _digestSession;
      _applyBaseHeaders(
        request,
        headers: headers,
        contentType: contentType,
        method: method,
        uri: uri,
        digestSession: cachedDigestSession,
      );
      final response = await _sendRequest(
        request,
        method: method,
        headers: headers,
        body: body,
        contentType: contentType,
      );
      final responseBytes = await _readResponseBytes(response);
      final responseBody = decodeBodyAsText
          ? utf8.decode(responseBytes, allowMalformed: true)
          : '';
      if (response.statusCode == 401 && account.authType == AuthType.digest) {
        final authenticateHeaders =
            response.headers[HttpHeaders.wwwAuthenticateHeader] ?? const [];
        final challenge = _parseDigestChallenge(
          authenticateHeaders,
          method: method,
          safeUri: safeUri,
        );
        if (challenge != null) {
          AppLogger.debug(
            'WebDAV',
            'digest challenge received method=$method url=$safeUri realm=${challenge.realm} algorithm=${challenge.algorithm ?? ''} qop=${challenge.qop ?? ''}',
          );
          _digestSession = _DigestSession(challenge);
          final digestRequest = await client.openUrl(method, uri);
          _applyBaseHeaders(
            digestRequest,
            headers: headers,
            contentType: contentType,
            method: method,
            uri: uri,
            digestSession: _digestSession,
          );
          final digestResponse = await _sendRequest(
            digestRequest,
            method: method,
            headers: headers,
            body: body,
            contentType: contentType,
          );
          final digestResponseBytes = await _readResponseBytes(digestResponse);
          final digestResponseBody = decodeBodyAsText
              ? utf8.decode(digestResponseBytes, allowMalformed: true)
              : '';
          stopwatch.stop();
          AppLogger.debug(
            'WebDAV',
            '<- $method $safeUri status=${digestResponse.statusCode} durationMs=${stopwatch.elapsedMilliseconds} responseBytes=${digestResponseBytes.length} responsePreview="${AppLogger.preview(digestResponseBody)}"',
          );
          return _WebDavResponse(
            digestResponse.statusCode,
            digestResponseBody,
            digestResponseBytes,
          );
        }
        AppLogger.error(
          'WebDAV',
          'digest challenge not found method=$method url=$safeUri configuredAlgorithm=${account.digestAlgorithm.wireName}',
        );
      }
      stopwatch.stop();
      AppLogger.debug(
        'WebDAV',
        '<- $method $safeUri status=${response.statusCode} durationMs=${stopwatch.elapsedMilliseconds} responseBytes=${responseBytes.length} responsePreview="${AppLogger.preview(responseBody)}"',
      );
      return _WebDavResponse(response.statusCode, responseBody, responseBytes);
    } on TimeoutException catch (error, stackTrace) {
      AppLogger.error(
          'WebDAV', 'timeout method=$method url=$safeUri', error, stackTrace);
      throw const WebDavException(WebDavFailureKind.timeout);
    } on HandshakeException catch (error, stackTrace) {
      AppLogger.error(
        'WebDAV',
        'TLS handshake failed method=$method url=$safeUri trustSelfSignedCert=${account.trustSelfSignedCert}',
        error,
        stackTrace,
      );
      throw const WebDavException(WebDavFailureKind.certificate);
    } on SocketException catch (error, stackTrace) {
      AppLogger.error('WebDAV', 'socket failed method=$method url=$safeUri',
          error, stackTrace);
      throw WebDavException(
        WebDavFailureKind.network,
        detail: error.message,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'WebDAV',
        'unexpected failure method=$method url=$safeUri',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _primeDigestSession(
    HttpClient client, {
    required Uri uri,
    required String safeUri,
  }) async {
    AppLogger.debug(
      'WebDAV',
      'prime digest challenge method=OPTIONS url=$safeUri',
    );
    final request = await client.openUrl('OPTIONS', uri);
    _applyBaseHeaders(
      request,
      headers: const {},
      contentType: null,
      method: 'OPTIONS',
      uri: uri,
    );
    final response = await _sendRequest(
      request,
      method: 'OPTIONS',
      headers: const {},
      body: null,
      contentType: null,
    );
    final responseBytes = await _readResponseBytes(response);
    if (response.statusCode != 401) {
      AppLogger.debug(
        'WebDAV',
        'prime digest challenge skipped status=${response.statusCode} url=$safeUri responseBytes=${responseBytes.length}',
      );
      return;
    }

    final authenticateHeaders =
        response.headers[HttpHeaders.wwwAuthenticateHeader] ?? const [];
    final challenge = _parseDigestChallenge(
      authenticateHeaders,
      method: 'OPTIONS',
      safeUri: safeUri,
    );
    if (challenge == null) {
      AppLogger.error(
        'WebDAV',
        'prime digest challenge not found url=$safeUri configuredAlgorithm=${account.digestAlgorithm.wireName}',
      );
      return;
    }
    _digestSession = _DigestSession(challenge);
    AppLogger.debug(
      'WebDAV',
      'prime digest challenge received url=$safeUri realm=${challenge.realm} algorithm=${challenge.algorithm ?? ''} qop=${challenge.qop ?? ''}',
    );
  }

  _DigestChallenge? _parseDigestChallenge(
    List<String> authenticateHeaders, {
    required String method,
    required String safeUri,
  }) {
    AppLogger.debug(
      'WebDAV',
      'digest auth headers method=$method url=$safeUri values=${authenticateHeaders.map(AppLogger.preview).toList()}',
    );
    return _DigestChallenge.tryParseHeaders(
      authenticateHeaders,
      preferredAlgorithm: _DigestHashAlgorithm.fromDigestAlgorithm(
        account.digestAlgorithm,
      ),
    );
  }

  void _applyAuthorization(HttpClientRequest request) {
    for (final entry in authorizationHeaders().entries) {
      request.headers.set(entry.key, entry.value);
    }
  }

  void _applyBaseHeaders(
    HttpClientRequest request, {
    required Map<String, String> headers,
    required String? contentType,
    required String method,
    required Uri uri,
    _DigestSession? digestSession,
  }) {
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    _applyAuthorization(request);
    if (account.authType == AuthType.digest && digestSession != null) {
      final digestHeaderValue = _buildDigestAuthorizationHeader(
        method: method,
        uri: uri,
        challenge: digestSession.challenge,
        nonceCount: digestSession.nextNonceCount(),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        digestHeaderValue,
      );
      AppLogger.debug(
        'WebDAV',
        'preemptive digest auth method=$method uri=${_safeUri(uri)} algorithm=${digestSession.challenge.algorithm ?? account.digestAlgorithm.wireName}',
      );
    }
  }

  Future<HttpClientResponse> _sendRequest(
    HttpClientRequest request, {
    required String method,
    required Map<String, String> headers,
    required List<int>? body,
    required String? contentType,
  }) async {
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    return request.close().timeout(const Duration(seconds: 30));
  }

  String _buildDigestAuthorizationHeader({
    required String method,
    required Uri uri,
    required _DigestChallenge challenge,
    required String nonceCount,
  }) {
    final username = account.username;
    final password = account.secret;
    final uriPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final selectedAlgorithm = account.digestAlgorithm;
    final challengeAlgorithm =
        _DigestHashAlgorithm.tryParse(challenge.algorithm) ??
            _DigestHashAlgorithm.fromDigestAlgorithm(selectedAlgorithm);
    final selectedHashAlgorithm =
        _DigestHashAlgorithm.fromDigestAlgorithm(selectedAlgorithm);
    if (challenge.algorithm != null &&
        challengeAlgorithm != selectedHashAlgorithm) {
      throw WebDavException(
        WebDavFailureKind.digestAlgorithmMismatch,
        serverAlgorithm: challengeAlgorithm.label,
        selectedAlgorithm: selectedHashAlgorithm.label,
      );
    }

    final cnonce = _randomHex(16);
    final ha1 = _hashHex(
      challengeAlgorithm,
      '$username:${challenge.realm}:$password',
    );
    final ha2 = _hashHex(challengeAlgorithm, '$method:$uriPath');

    final response = switch (challenge.qop) {
      'auth' => _hashHex(
          challengeAlgorithm,
          '$ha1:${challenge.nonce}:$nonceCount:$cnonce:${challenge.qop}:$ha2',
        ),
      null => _hashHex(challengeAlgorithm, '$ha1:${challenge.nonce}:$ha2'),
      _ => throw WebDavException(
          WebDavFailureKind.digestUnsupportedQop,
          qop: challenge.qop,
        ),
    };

    final parts = <String>[
      'username="${_escapeHeaderValue(username)}"',
      'realm="${_escapeHeaderValue(challenge.realm)}"',
      'nonce="${_escapeHeaderValue(challenge.nonce)}"',
      'uri="${_escapeHeaderValue(uriPath)}"',
      'response="$response"',
    ];
    if (challenge.opaque != null && challenge.opaque!.isNotEmpty) {
      parts.add('opaque="${_escapeHeaderValue(challenge.opaque!)}"');
    }
    if (challenge.algorithm != null && challenge.algorithm!.isNotEmpty) {
      parts.add('algorithm=${challenge.algorithm}');
    } else {
      parts.add('algorithm=${challengeAlgorithm.wireName}');
    }
    if (challenge.qop != null) {
      parts.add('qop=${challenge.qop}');
      parts.add('nc=$nonceCount');
      parts.add('cnonce="$cnonce"');
    }
    return 'Digest ${parts.join(', ')}';
  }

  _DigestSession? get _digestSession {
    if (account.authType != AuthType.digest) {
      return null;
    }
    return _digestSessions[_digestSessionKey];
  }

  set _digestSession(_DigestSession? value) {
    if (account.authType != AuthType.digest) {
      return;
    }
    if (value == null) {
      _digestSessions.remove(_digestSessionKey);
      return;
    }
    _digestSessions[_digestSessionKey] = value;
  }

  String get _digestSessionKey {
    return '${account.baseUrl}|${account.username}|${account.digestAlgorithm.name}';
  }

  Uri _resolveUri(String path) {
    final base = Uri.parse(account.baseUrl.trim());
    final basePath = _normalizeDirectoryPath(base.path);
    final targetPath = _normalizePath(path);
    final joinedPath = _joinPaths(basePath, targetPath);
    return base.replace(path: joinedPath);
  }

  List<WebDavResource> _parsePropfind(String body) {
    final document = XmlDocument.parse(body);
    final responses = document.findAllElements('response', namespace: '*');
    return [
      for (final response in responses)
        WebDavResource(
          path: _resourcePathFromHref(_firstText(response, 'href')),
          name: _resourceName(_firstText(response, 'href')),
          isDirectory:
              response.findAllElements('collection', namespace: '*').isNotEmpty,
          size: int.tryParse(_firstText(response, 'getcontentlength')),
          etag: _emptyToNull(_firstText(response, 'getetag')),
          contentType: _emptyToNull(_firstText(response, 'getcontenttype')),
          lastModified:
              _tryParseHttpDate(_firstText(response, 'getlastmodified')),
        ),
    ];
  }

  String _resourcePathFromHref(String href) {
    final decoded = Uri.decodeComponent(Uri.parse(href).path);
    final basePath = _normalizeDirectoryPath(Uri.parse(account.baseUrl).path);
    final relative = decoded.startsWith(basePath)
        ? decoded.substring(basePath.length)
        : decoded;
    return _normalizePath(relative);
  }

  String _resourceName(String href) {
    final path = _resourcePathFromHref(href);
    if (path == '/') {
      return '/';
    }
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    return trimmed.split('/').last;
  }

  static String _firstText(XmlElement parent, String localName) {
    final elements = parent.findAllElements(localName, namespace: '*');
    if (elements.isEmpty) {
      return '';
    }
    return elements.first.innerText.trim();
  }

  static String? _emptyToNull(String value) {
    return value.isEmpty ? null : value;
  }

  static DateTime? _tryParseHttpDate(String value) {
    if (value.isEmpty) {
      return null;
    }
    try {
      return HttpDate.parse(value);
    } on FormatException {
      return null;
    }
  }

  static String _safeUri(Uri uri) {
    return uri
        .replace(userInfo: '', query: _redactQuery(uri.queryParameters))
        .toString();
  }

  static String? _redactQuery(Map<String, String> queryParameters) {
    if (queryParameters.isEmpty) {
      return null;
    }
    return queryParameters.entries.map((entry) {
      final key = entry.key.toLowerCase();
      final value = key.contains('token') ||
              key.contains('password') ||
              key.contains('secret') ||
              key.contains('key')
          ? '***'
          : entry.value;
      return '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value)}';
    }).join('&');
  }

  static Map<String, String> _safeHeaders(
    Map<String, String> headers,
    String? contentType,
  ) {
    final safeHeaders = <String, String>{};
    if (contentType != null) {
      safeHeaders[HttpHeaders.contentTypeHeader] = contentType;
    }
    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase();
      safeHeaders[entry.key] =
          key == HttpHeaders.authorizationHeader ? '***' : entry.value;
    }
    return safeHeaders;
  }

  static Future<List<int>> _readResponseBytes(HttpClientResponse response) {
    final completer = Completer<List<int>>();
    final chunks = <int>[];
    response.listen(
      chunks.addAll,
      onDone: () => completer.complete(chunks),
      onError: completer.completeError,
      cancelOnError: true,
    );
    return completer.future;
  }
}

class _DigestChallenge {
  const _DigestChallenge({
    required this.realm,
    required this.nonce,
    this.opaque,
    this.algorithm,
    this.qop,
  });

  final String realm;
  final String nonce;
  final String? opaque;
  final String? algorithm;
  final String? qop;

  static _DigestChallenge? tryParse(String? headerValue) {
    if (headerValue == null || headerValue.isEmpty) {
      return null;
    }
    final prefixMatch = RegExp(
      r'^\s*Digest\s+',
      caseSensitive: false,
    ).firstMatch(headerValue);
    if (prefixMatch == null) {
      return null;
    }
    final rawParams = headerValue.substring(prefixMatch.end);
    final params = <String, String>{};
    final matches =
        RegExp(r'(\w+)=("([^"\\]|\\.)*"|[^,]+)').allMatches(rawParams);
    for (final match in matches) {
      final key = match.group(1);
      final rawValue = match.group(2);
      if (key == null || rawValue == null) {
        continue;
      }
      var value = rawValue.trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1).replaceAll(r'\"', '"');
      }
      params[key.toLowerCase()] = value;
    }
    final realm = params['realm'];
    final nonce = params['nonce'];
    if (realm == null || realm.isEmpty || nonce == null || nonce.isEmpty) {
      return null;
    }
    final qop = params['qop']?.split(',').map((e) => e.trim()).firstWhere(
          (item) => item == 'auth',
          orElse: () => params['qop']!.trim(),
        );
    return _DigestChallenge(
      realm: realm,
      nonce: nonce,
      opaque: params['opaque'],
      algorithm: params['algorithm'],
      qop: qop,
    );
  }

  static _DigestChallenge? tryParseHeaders(
    List<String> headerValues, {
    _DigestHashAlgorithm? preferredAlgorithm,
  }) {
    final challenges = <_DigestChallenge>[];
    for (final headerValue in headerValues) {
      final challenge = tryParse(headerValue);
      if (challenge != null) {
        challenges.add(challenge);
      }
    }
    if (challenges.isEmpty) {
      return null;
    }
    if (preferredAlgorithm != null) {
      for (final challenge in challenges) {
        final algorithm = _DigestHashAlgorithm.tryParse(challenge.algorithm);
        if (algorithm == preferredAlgorithm) {
          return challenge;
        }
      }
    }
    return challenges.first;
  }
}

class _DigestSession {
  _DigestSession(this.challenge);

  final _DigestChallenge challenge;
  int _nonceCount = 0;

  String nextNonceCount() {
    _nonceCount += 1;
    return _nonceCount.toRadixString(16).padLeft(8, '0');
  }
}

enum _DigestHashAlgorithm {
  md5,
  sha256;

  String get label {
    switch (this) {
      case _DigestHashAlgorithm.md5:
        return 'MD5';
      case _DigestHashAlgorithm.sha256:
        return 'SHA-256';
    }
  }

  String get wireName {
    switch (this) {
      case _DigestHashAlgorithm.md5:
        return 'MD5';
      case _DigestHashAlgorithm.sha256:
        return 'SHA-256';
    }
  }

  static _DigestHashAlgorithm fromDigestAlgorithm(
    DigestAlgorithm algorithm,
  ) {
    switch (algorithm) {
      case DigestAlgorithm.md5:
        return _DigestHashAlgorithm.md5;
      case DigestAlgorithm.sha256:
        return _DigestHashAlgorithm.sha256;
    }
  }

  static _DigestHashAlgorithm? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    switch (value.trim().toUpperCase()) {
      case 'MD5':
        return _DigestHashAlgorithm.md5;
      case 'SHA-256':
        return _DigestHashAlgorithm.sha256;
      default:
        return null;
    }
  }
}

enum WebDavFailureKind {
  httpDisabled,
  timeout,
  certificate,
  network,
  digestAlgorithmMismatch,
  digestUnsupportedQop,
  unauthorized,
  forbidden,
  notFound,
  methodNotAllowed,
  conflict,
  payloadTooLarge,
  locked,
  httpStatus,
  directoryDownloadFailed,
}

class WebDavException implements Exception {
  const WebDavException(
    this.kind, {
    this.statusCode,
    this.detail,
    this.serverAlgorithm,
    this.selectedAlgorithm,
    this.qop,
  });

  final WebDavFailureKind kind;
  final int? statusCode;
  final String? detail;
  final String? serverAlgorithm;
  final String? selectedAlgorithm;
  final String? qop;

  String get message {
    switch (kind) {
      case WebDavFailureKind.httpDisabled:
        return 'HTTP 连接已禁用，请在账号设置中允许 HTTP。';
      case WebDavFailureKind.timeout:
        return '请求超时，请检查网络或服务器状态。';
      case WebDavFailureKind.certificate:
        return 'TLS 证书校验失败，可检查证书或开启信任自签名证书。';
      case WebDavFailureKind.network:
        return '网络连接失败：${detail ?? ''}';
      case WebDavFailureKind.digestAlgorithmMismatch:
        return 'Digest 算法不匹配，服务端要求 $serverAlgorithm，当前配置为 $selectedAlgorithm。';
      case WebDavFailureKind.digestUnsupportedQop:
        return 'Digest 认证不支持 qop=$qop。';
      case WebDavFailureKind.unauthorized:
        return '认证失败，请检查用户名、密码或 Token。';
      case WebDavFailureKind.forbidden:
        return '权限不足，当前账号无法访问该资源。';
      case WebDavFailureKind.notFound:
        return '路径不存在，请检查服务地址或默认路径。';
      case WebDavFailureKind.methodNotAllowed:
        return '服务端不支持当前 WebDAV 方法。';
      case WebDavFailureKind.conflict:
        return '路径冲突或父目录不存在。';
      case WebDavFailureKind.payloadTooLarge:
        return '文件超过服务端允许的大小。';
      case WebDavFailureKind.locked:
        return '资源已被锁定。';
      case WebDavFailureKind.httpStatus:
        final code = statusCode ?? 0;
        final detailText = detail?.trim() ?? '';
        if (detailText.isEmpty) {
          return '请求失败，HTTP 状态码：$code。';
        }
        return '请求失败，HTTP 状态码：$code。$detailText';
      case WebDavFailureKind.directoryDownloadFailed:
        return '目录下载失败。';
    }
  }

  static WebDavException fromStatus(int statusCode, String body) {
    switch (statusCode) {
      case 401:
        return const WebDavException(WebDavFailureKind.unauthorized);
      case 403:
        return const WebDavException(WebDavFailureKind.forbidden);
      case 404:
        return const WebDavException(WebDavFailureKind.notFound);
      case 405:
        return const WebDavException(WebDavFailureKind.methodNotAllowed);
      case 409:
        return const WebDavException(WebDavFailureKind.conflict);
      case 413:
        return const WebDavException(WebDavFailureKind.payloadTooLarge);
      case 423:
        return const WebDavException(WebDavFailureKind.locked);
      default:
        return WebDavException(
          WebDavFailureKind.httpStatus,
          statusCode: statusCode,
          detail: body.trim(),
        );
    }
  }

  @override
  String toString() => message;
}

class _WebDavResponse {
  const _WebDavResponse(this.statusCode, this.body, this.bodyBytes);

  final int statusCode;
  final String body;
  final List<int> bodyBytes;

  String get bodyText => body;
}

const _propfindBody = '''
<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:resourcetype/>
    <D:getcontentlength/>
    <D:getlastmodified/>
    <D:getetag/>
    <D:getcontenttype/>
  </D:prop>
</D:propfind>
''';

String _joinPaths(String left, String right) {
  final cleanLeft =
      left.endsWith('/') ? left.substring(0, left.length - 1) : left;
  final cleanRight = right.startsWith('/') ? right.substring(1) : right;
  if (cleanLeft.isEmpty) {
    return '/$cleanRight';
  }
  if (cleanRight.isEmpty) {
    return cleanLeft;
  }
  return '$cleanLeft/$cleanRight';
}

String _normalizeDirectoryPath(String path) {
  final normalized = _normalizePath(path);
  return normalized.endsWith('/') ? normalized : '$normalized/';
}

String _normalizePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed == '/') {
    return '/';
  }
  final prefixed = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return prefixed.replaceAll(RegExp(r'/+'), '/');
}

String _hashHex(_DigestHashAlgorithm algorithm, String value) {
  final bytes = utf8.encode(value);
  return switch (algorithm) {
    _DigestHashAlgorithm.md5 => md5.convert(bytes).toString(),
    _DigestHashAlgorithm.sha256 => sha256.convert(bytes).toString(),
  };
}

String _randomHex(int byteLength) {
  final random = Random.secure();
  final values = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return values.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String _escapeHeaderValue(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
