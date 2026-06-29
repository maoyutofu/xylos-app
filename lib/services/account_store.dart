import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transfer_record.dart';
import '../models/webdav_account.dart';
import 'app_logger.dart';
import 'local_crypto.dart';

class AccountStore {
  const AccountStore();

  static const _serversKey = 'xylos.servers.v1';
  static const _connectionKey = 'xylos.connection.v1';
  static const _legacyAccountsKey = 'xylos.accounts.v1';
  static const _languageKey = 'xylos.language.v1';
  static const _downloadDirectoryKey = 'xylos.downloadDirectory.v1';
  static const _transfersKey = 'xylos.transfers.v1';
  static const _secretVaultKey = 'xylos.secretVault.v1';
  static const _secretVaultHeader = 'xylos.secret-vault|1';
  static const _acceptedLegalTermsVersionKey = 'xylos.legal.acceptedVersion.v1';
  static const _currentLegalTermsVersion = '2026-06-29';

  static String? _sessionPassphrase;
  static final Map<String, String> _sessionSecrets = <String, String>{};

  bool get isSessionUnlocked => _sessionPassphrase != null;
  String? get sessionPassphrase => _sessionPassphrase;

  Future<bool> hasSecretVault() async {
    final prefs = await SharedPreferences.getInstance();
    final vault = prefs.getString(_secretVaultKey);
    return vault != null && vault.trim().isNotEmpty;
  }

  Future<List<WebDavAccount>> loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_serversKey);
    if (values != null) {
      final servers = await _decodeServers(values);
      return servers;
    }

    final singleConnection = prefs.getString(_connectionKey);
    if (singleConnection != null) {
      final servers = await _decodeServers([singleConnection]);
      await saveServers(servers);
      await prefs.remove(_connectionKey);
      return servers;
    }

    final legacyAccounts = prefs.getStringList(_legacyAccountsKey);
    if (legacyAccounts == null) {
      return const [];
    }
    final servers = await _decodeServers(legacyAccounts);
    await saveServers(servers);
    return servers;
  }

  Future<void> unlockSession(String passphrase) async {
    final prefs = await SharedPreferences.getInstance();
    final vault = prefs.getString(_secretVaultKey);
    _sessionSecrets.clear();
    if (vault != null && vault.trim().isNotEmpty) {
      final decoded = jsonDecode(vault);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Invalid local secret vault.');
      }
      final payload = decryptPayload(
        decoded,
        passphrase,
        header: _secretVaultHeader,
      );
      if (payload is! Map<String, Object?>) {
        throw const FormatException('Invalid local secret vault.');
      }
      final secrets = payload['secrets'];
      if (secrets is! Map) {
        throw const FormatException('Invalid local secret vault.');
      }
      for (final entry in secrets.entries) {
        final key = entry.key.toString();
        final value = entry.value?.toString() ?? '';
        if (key.isNotEmpty) {
          _sessionSecrets[key] = value;
        }
      }
    }
    _sessionPassphrase = passphrase;
  }

  Future<void> changeSessionPassphrase(String passphrase) async {
    if (_sessionPassphrase == null) {
      throw const FormatException('Secrets session is locked.');
    }
    _sessionPassphrase = passphrase;
    await _persistSecretVault();
  }

  Future<void> saveServers(List<WebDavAccount> servers) async {
    final prefs = await SharedPreferences.getInstance();
    final previousValues = prefs.getStringList(_serversKey) ?? const [];
    final previousServerIds = _decodeServerIds(previousValues);
    final currentIds = servers.map((server) => server.id).toSet();

    for (final previousId in previousServerIds) {
      if (!currentIds.contains(previousId)) {
        _sessionSecrets.remove(previousId);
      }
    }
    for (final server in servers) {
      if (server.secret.isNotEmpty) {
        _sessionSecrets[server.id] = server.secret;
      }
    }

    await prefs.setStringList(
      _serversKey,
      servers.map((server) => server.encode()).toList(),
    );
    await prefs.remove(_connectionKey);
    await prefs.remove(_legacyAccountsKey);

    if (_sessionPassphrase != null) {
      await _persistSecretVault();
    }
  }

  Future<void> clearServers() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionSecrets.clear();
    await prefs.remove(_serversKey);
    await prefs.remove(_connectionKey);
    await prefs.remove(_legacyAccountsKey);
    await prefs.remove(_secretVaultKey);
  }

  Future<List<WebDavAccount>> _decodeServers(List<String> values) async {
    final servers = <WebDavAccount>[];
    for (final value in values) {
      try {
        servers.add(WebDavAccount.decode(value));
      } on FormatException catch (error, stackTrace) {
        AppLogger.error(
          'AccountStore',
          'skip malformed server record',
          error,
          stackTrace,
        );
      } on TypeError catch (error, stackTrace) {
        AppLogger.error(
          'AccountStore',
          'skip invalid server record',
          error,
          stackTrace,
        );
      }
    }
    return servers;
  }

  Future<WebDavAccount> hydrateServer(WebDavAccount server) async {
    if (!isSessionUnlocked) {
      throw const FormatException('Secrets session is locked.');
    }
    return server.copyWith(secret: _sessionSecrets[server.id] ?? server.secret);
  }

  Future<List<WebDavAccount>> hydrateServersForSession(
    List<WebDavAccount> servers,
  ) async {
    if (!isSessionUnlocked) {
      throw const FormatException('Secrets session is locked.');
    }
    return servers
        .map(
          (server) => server.copyWith(
              secret: _sessionSecrets[server.id] ?? server.secret),
        )
        .toList();
  }

  Set<String> _decodeServerIds(List<String> values) {
    final serverIds = <String>{};
    for (final value in values) {
      try {
        final server = WebDavAccount.decode(value);
        if (server.id.isNotEmpty) {
          serverIds.add(server.id);
        }
      } on FormatException catch (error, stackTrace) {
        AppLogger.error(
          'AccountStore',
          'skip malformed server record while reading ids',
          error,
          stackTrace,
        );
      } on TypeError catch (error, stackTrace) {
        AppLogger.error(
          'AccountStore',
          'skip invalid server record while reading ids',
          error,
          stackTrace,
        );
      }
    }
    return serverIds;
  }

  Future<void> _persistSecretVault() async {
    final passphrase = _sessionPassphrase;
    if (passphrase == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = encryptPayload(
      utf8.encode(
        jsonEncode({
          'secrets': _sessionSecrets,
        }),
      ),
      passphrase,
      header: _secretVaultHeader,
    );
    await prefs.setString(_secretVaultKey, jsonEncode(payload));
  }

  Future<String> loadLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? '';
  }

  Future<void> saveLanguageCode(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
  }

  Future<bool> hasAcceptedCurrentLegalTerms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_acceptedLegalTermsVersionKey) ==
        _currentLegalTermsVersion;
  }

  Future<void> acceptCurrentLegalTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _acceptedLegalTermsVersionKey,
      _currentLegalTermsVersion,
    );
  }

  Future<String> loadDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDirectory = prefs.getString(_downloadDirectoryKey);
    if (savedDirectory != null && savedDirectory.trim().isNotEmpty) {
      final directory = savedDirectory.trim();
      try {
        await Directory(directory).create(recursive: true);
        return directory;
      } on FileSystemException {
        // Fall back to a platform-managed directory on mobile when a previously
        // persisted path is no longer writable.
      }
    }
    return resolveDefaultDownloadDirectory();
  }

  Future<void> saveDownloadDirectory(String directory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadDirectoryKey, directory);
  }

  Future<List<TransferRecord>> loadTransfers() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_transfersKey) ?? const [];
    return _decodeTransfers(values);
  }

  List<TransferRecord> _decodeTransfers(List<String> values) {
    final transfers = <TransferRecord>[];
    for (final value in values) {
      try {
        transfers.add(TransferRecord.decode(value));
      } on FormatException catch (error, stackTrace) {
        AppLogger.error(
          'AccountStore',
          'skip malformed transfer record',
          error,
          stackTrace,
        );
      } on TypeError catch (error, stackTrace) {
        AppLogger.error(
          'AccountStore',
          'skip invalid transfer record',
          error,
          stackTrace,
        );
      }
    }
    return transfers;
  }

  Future<void> saveTransfers(List<TransferRecord> transfers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _transfersKey,
      transfers.map((transfer) => transfer.encode()).toList(),
    );
  }

  static String get defaultDownloadDirectory {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) {
      return 'xylos_appdata';
    }
    if (home.endsWith(Platform.pathSeparator)) {
      return '${home}xylos_appdata';
    }
    return '$home${Platform.pathSeparator}xylos_appdata';
  }

  static Future<String> resolveDefaultDownloadDirectory() async {
    try {
      late final String path;
      if (Platform.isAndroid) {
        final externalDirectory = await getExternalStorageDirectory();
        if (externalDirectory != null) {
          path = externalDirectory.path;
        } else {
          path = (await getApplicationDocumentsDirectory()).path;
        }
      } else if (Platform.isIOS) {
        path = (await getApplicationDocumentsDirectory()).path;
      } else {
        path = defaultDownloadDirectory;
      }
      await Directory(path).create(recursive: true);
      return path;
    } on MissingPluginException {
      return defaultDownloadDirectory;
    } on UnsupportedError {
      return defaultDownloadDirectory;
    } on FileSystemException {
      return defaultDownloadDirectory;
    }
  }
}
