import 'dart:convert';

enum AuthType {
  basic,
  digest,
  bearer;

  String get label {
    switch (this) {
      case AuthType.basic:
        return 'Basic';
      case AuthType.digest:
        return 'Digest';
      case AuthType.bearer:
        return 'Bearer Token';
    }
  }

  static AuthType fromName(String value) {
    return AuthType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AuthType.basic,
    );
  }
}

enum DigestAlgorithm {
  md5,
  sha256;

  String get label {
    switch (this) {
      case DigestAlgorithm.md5:
        return 'MD5';
      case DigestAlgorithm.sha256:
        return 'SHA-256';
    }
  }

  String get wireName {
    switch (this) {
      case DigestAlgorithm.md5:
        return 'MD5';
      case DigestAlgorithm.sha256:
        return 'SHA-256';
    }
  }

  static DigestAlgorithm fromName(String value) {
    return DigestAlgorithm.values.firstWhere(
      (item) => item.name == value,
      orElse: () => DigestAlgorithm.md5,
    );
  }
}

class WebDavAccount {
  const WebDavAccount({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.authType,
    required this.digestAlgorithm,
    required this.username,
    required this.secret,
    required this.defaultPath,
    required this.allowHttp,
    required this.trustSelfSignedCert,
  });

  final String id;
  final String name;
  final String baseUrl;
  final AuthType authType;
  final DigestAlgorithm digestAlgorithm;
  final String username;
  final String secret;
  final String defaultPath;
  final bool allowHttp;
  final bool trustSelfSignedCert;

  WebDavAccount copyWith({
    String? id,
    String? name,
    String? baseUrl,
    AuthType? authType,
    DigestAlgorithm? digestAlgorithm,
    String? username,
    String? secret,
    String? defaultPath,
    bool? allowHttp,
    bool? trustSelfSignedCert,
  }) {
    return WebDavAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      authType: authType ?? this.authType,
      digestAlgorithm: digestAlgorithm ?? this.digestAlgorithm,
      username: username ?? this.username,
      secret: secret ?? this.secret,
      defaultPath: defaultPath ?? this.defaultPath,
      allowHttp: allowHttp ?? this.allowHttp,
      trustSelfSignedCert: trustSelfSignedCert ?? this.trustSelfSignedCert,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'authType': authType.name,
      'digestAlgorithm': digestAlgorithm.name,
      'username': username,
      'defaultPath': defaultPath,
      'allowHttp': allowHttp,
      'trustSelfSignedCert': trustSelfSignedCert,
    };
  }

  factory WebDavAccount.fromJson(Map<String, Object?> json) {
    return WebDavAccount(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      authType: AuthType.fromName(json['authType'] as String? ?? ''),
      digestAlgorithm: DigestAlgorithm.fromName(
        json['digestAlgorithm'] as String? ?? '',
      ),
      username: json['username'] as String? ?? '',
      secret: json['secret'] as String? ?? '',
      defaultPath: json['defaultPath'] as String? ?? '/',
      allowHttp: json['allowHttp'] as bool? ?? false,
      trustSelfSignedCert: json['trustSelfSignedCert'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  static WebDavAccount decode(String value) {
    return WebDavAccount.fromJson(jsonDecode(value) as Map<String, Object?>);
  }
}
