import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../models/transfer_record.dart';
import '../models/webdav_account.dart';
import '../models/webdav_resource.dart';
import '../services/account_store.dart';
import '../services/app_logger.dart';
import '../services/local_crypto.dart';
import '../services/server_qr_payload.dart';
import '../services/webdav_client.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, AccountStore? store})
      : store = store ?? const AccountStore();

  final AccountStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _servers = <WebDavAccount>[];
  final _transfers = <TransferRecord>[];
  WebDavAccount? _activeServer;
  AppLanguage _language = AppLanguage.zh;
  var _downloadDirectory = '';
  var _selectedIndex = 0;
  var _loading = true;
  String? _loadError;

  AppStrings get strings => AppStrings.of(_language);

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final servers = await widget.store.loadServers();
      final languageCode = await widget.store.loadLanguageCode();
      final downloadDirectory = await widget.store.loadDownloadDirectory();
      final transfers = await widget.store.loadTransfers();
      AppLogger.debug(
        'UI',
        'loaded state servers=${servers.length} transfers=${transfers.length} language=$languageCode downloadDirectorySet=${downloadDirectory.isNotEmpty}',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _servers
          ..clear()
          ..addAll(servers);
        _transfers
          ..clear()
          ..addAll(transfers);
        _language = _resolveInitialLanguage(languageCode);
        _downloadDirectory = downloadDirectory;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('UI', 'load app state failed', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadDirectory = '';
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final loadError = _loadError;
    if (loadError != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.error_outline,
              title: strings.loadFailed,
              message: loadError,
              action: FilledButton.icon(
                onPressed: _loadState,
                icon: const Icon(Icons.refresh),
                label: Text(strings.retry),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;
        if (useRail) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 20),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 32,
                      height: 32,
                    ),
                  ),
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.dns_outlined),
                      selectedIcon: const Icon(Icons.dns),
                      label: Text(strings.serversNav),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.sync_alt_outlined),
                      selectedIcon: const Icon(Icons.sync_alt),
                      label: Text(strings.transfersNav),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.download_done_outlined),
                      selectedIcon: const Icon(Icons.download_done),
                      label: Text(strings.offlineNav),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.tune_outlined),
                      selectedIcon: const Icon(Icons.tune),
                      label: Text(strings.settingsNav),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildSection()),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(_sectionTitle)),
          body: _buildSection(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectDestination,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.dns_outlined),
                selectedIcon: const Icon(Icons.dns),
                label: strings.serversNav,
              ),
              NavigationDestination(
                icon: const Icon(Icons.sync_alt_outlined),
                selectedIcon: const Icon(Icons.sync_alt),
                label: strings.transfersNav,
              ),
              NavigationDestination(
                icon: const Icon(Icons.download_done_outlined),
                selectedIcon: const Icon(Icons.download_done),
                label: strings.offlineNav,
              ),
              NavigationDestination(
                icon: const Icon(Icons.tune_outlined),
                selectedIcon: const Icon(Icons.tune),
                label: strings.settingsNav,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection() {
    switch (_selectedIndex) {
      case 0:
        final activeServer = _activeServer;
        if (activeServer != null) {
          return FileBrowserPage(
            server: activeServer,
            strings: strings,
            downloadDirectory: _downloadDirectory,
            onDownloadDirectoryChanged: _saveDownloadDirectory,
            onTransferChanged: _upsertTransfer,
            onBack: () {
              setState(() {
                _activeServer = null;
              });
            },
          );
        }
        return ServersPage(
          servers: _servers,
          strings: strings,
          onOpen: _openServer,
          onHydrateServer: _hydrateServerForSession,
          onExportServerQr: _exportServerQr,
          onImportServerFromQr: _importServerFromQr,
          onChanged: _replaceServers,
        );
      case 1:
        return TransfersPage(
          strings: strings,
          transfers: _transfers,
          onRetry: _retryTransfer,
          onClearCompleted: _clearCompletedTransfers,
          onOpenFolder: _openLocalFolder,
          onClean: _cleanTransfer,
        );
      case 2:
        return OfflinePage(
          strings: strings,
          downloadDirectory: _downloadDirectory,
          onOpenFolder: _openLocalFolder,
        );
      case 3:
        return SettingsPage(
          language: _language,
          strings: strings,
          appVersion: AppVersion.displayVersion,
          downloadDirectory: _downloadDirectory,
          sessionUnlocked: widget.store.isSessionUnlocked,
          onLanguageChanged: _saveLanguage,
          onDownloadDirectoryChanged: _saveDownloadDirectory,
          onChangeMasterPassphrase: _changeMasterPassphrase,
          onExportServers: _exportServers,
          onImportServers: _importServers,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String get _sectionTitle {
    switch (_selectedIndex) {
      case 0:
        return _activeServer == null
            ? strings.serversTitle
            : strings.filesTitle;
      case 1:
        return strings.transfersTitle;
      case 2:
        return strings.offlineTitle;
      case 3:
        return strings.settingsTitle;
      default:
        return 'Xylos';
    }
  }

  Future<void> _replaceServers(List<WebDavAccount> servers) async {
    if (servers.any((server) => server.secret.isNotEmpty) &&
        !widget.store.isSessionUnlocked) {
      final passphrase = await _promptSessionPassphrase();
      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException('Passphrase is required.');
      }
      await widget.store.unlockSession(passphrase);
    }
    AppLogger.debug('UI', 'save servers count=${servers.length}');
    await widget.store.saveServers(servers);
    setState(() {
      _servers
        ..clear()
        ..addAll(servers);
      if (_activeServer != null &&
          !_servers.any((server) => server.id == _activeServer!.id)) {
        _activeServer = null;
      }
    });
  }

  Future<void> _openServer(WebDavAccount server) async {
    AppLogger.debug(
      'UI',
      'open server alias=${server.name} baseUrl=${server.baseUrl}',
    );
    final hydratedServers = await _unlockAndHydrateServersForSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _servers
        ..clear()
        ..addAll(hydratedServers);
      final hydratedServer = _servers.firstWhere(
        (item) => item.id == server.id,
        orElse: () => server,
      );
      _activeServer = hydratedServer;
      _selectedIndex = 0;
    });
  }

  Future<WebDavAccount> _hydrateServerForSession(WebDavAccount server) async {
    final hydratedServers = await _unlockAndHydrateServersForSession();
    final hydratedServer = hydratedServers.firstWhere(
      (item) => item.id == server.id,
      orElse: () => server,
    );
    if (!mounted) {
      return hydratedServer;
    }
    setState(() {
      _servers
        ..clear()
        ..addAll(hydratedServers);
      if (_activeServer != null) {
        final activeIndex = _servers.indexWhere(
          (item) => item.id == _activeServer!.id,
        );
        if (activeIndex != -1) {
          _activeServer = _servers[activeIndex];
        }
      }
    });
    return hydratedServer;
  }

  Future<List<WebDavAccount>> _unlockAndHydrateServersForSession() async {
    if (!widget.store.isSessionUnlocked) {
      final passphrase = await _promptSessionPassphrase();
      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException('Passphrase is required.');
      }
      await widget.store.unlockSession(passphrase);
    }
    return widget.store.hydrateServersForSession(_servers);
  }

  Future<String?> _promptSessionPassphrase(
      {bool forceUnlockTitle = false}) async {
    final hasVault = await widget.store.hasSecretVault();
    if (!mounted) {
      return null;
    }
    return showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        final passphraseController = TextEditingController();
        final confirmController = TextEditingController();
        var obscure = true;
        var errorText = '';
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                hasVault || forceUnlockTitle
                    ? strings.unlockSecrets
                    : strings.createPassphrase,
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: passphraseController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: strings.configPassphrase,
                        errorText: errorText.isEmpty ? null : errorText,
                      ),
                    ),
                    if (!hasVault) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: strings.confirmPassphrase,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            obscure = !obscure;
                          });
                        },
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        label: Text(strings.togglePassphraseVisibility),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final passphrase = passphraseController.text;
                    if (passphrase.isEmpty) {
                      setState(() {
                        errorText = strings.passphraseRequired;
                      });
                      return;
                    }
                    if (!hasVault && passphrase != confirmController.text) {
                      setState(() {
                        errorText = strings.passphraseMismatch;
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(passphrase);
                  },
                  child: Text(strings.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _promptNewMasterPassphrase() async {
    if (!mounted) {
      return null;
    }
    return showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        final passphraseController = TextEditingController();
        final confirmController = TextEditingController();
        var obscure = true;
        var errorText = '';
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(strings.changeMasterPassphrase),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: passphraseController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: strings.configPassphrase,
                        errorText: errorText.isEmpty ? null : errorText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: strings.confirmPassphrase,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            obscure = !obscure;
                          });
                        },
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        label: Text(strings.togglePassphraseVisibility),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final passphrase = passphraseController.text;
                    if (passphrase.isEmpty) {
                      setState(() {
                        errorText = strings.passphraseRequired;
                      });
                      return;
                    }
                    if (passphrase != confirmController.text) {
                      setState(() {
                        errorText = strings.passphraseMismatch;
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(passphrase);
                  },
                  child: Text(strings.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _changeMasterPassphrase() async {
    final hasVault = await widget.store.hasSecretVault();
    if (!hasVault) {
      final initialPassphrase = await _promptSessionPassphrase();
      if (initialPassphrase == null || initialPassphrase.isEmpty) {
        return null;
      }
      await widget.store.unlockSession(initialPassphrase);
      await widget.store.changeSessionPassphrase(initialPassphrase);
      return strings.masterPassphraseChanged;
    }
    if (!widget.store.isSessionUnlocked) {
      final currentPassphrase = await _promptSessionPassphrase(
        forceUnlockTitle: true,
      );
      if (currentPassphrase == null || currentPassphrase.isEmpty) {
        return null;
      }
      await widget.store.unlockSession(currentPassphrase);
    }
    final newPassphrase = await _promptNewMasterPassphrase();
    if (newPassphrase == null || newPassphrase.isEmpty) {
      return null;
    }
    await widget.store.changeSessionPassphrase(newPassphrase);
    return strings.masterPassphraseChanged;
  }

  Future<void> _saveLanguage(AppLanguage language) async {
    AppLogger.debug('UI', 'save language=${language.code}');
    await widget.store.saveLanguageCode(language.code);
    setState(() {
      _language = language;
    });
  }

  Future<void> _saveDownloadDirectory(String directory) async {
    AppLogger.debug(
      'UI',
      'save download directory set=${directory.trim().isNotEmpty}',
    );
    await widget.store.saveDownloadDirectory(directory.trim());
    setState(() {
      _downloadDirectory = directory.trim();
    });
  }

  AppLanguage _resolveInitialLanguage(String languageCode) {
    if (languageCode.trim().isNotEmpty) {
      return AppLanguage.fromCode(languageCode);
    }
    final systemLanguageCode =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (systemLanguageCode == AppLanguage.zh.code) {
      return AppLanguage.zh;
    }
    return AppLanguage.en;
  }

  Future<String?> _exportServers() async {
    final hydratedServers = await _unlockAndHydrateServersForSession();
    final passphrase = widget.store.sessionPassphrase;
    if (passphrase == null || passphrase.isEmpty) {
      throw const FormatException('Passphrase is required.');
    }
    final plaintext = utf8.encode(
      jsonEncode({
        'servers': [
          for (final server in hydratedServers)
            {
              ...server.toJson(),
              'secret': server.secret,
            },
        ],
      }),
    );
    final encrypted = encryptPayload(
      plaintext,
      passphrase,
      header: 'xylos.server-config|2',
    );
    final payload = <String, Object?>{
      'format': 'xylos.server-config',
      'version': 2,
      'encrypted': true,
      'kdf': encrypted['kdf'],
      'cipher': encrypted['cipher'],
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'salt': encrypted['salt'],
      'nonce': encrypted['nonce'],
      'iterations': encrypted['iterations'],
      'ciphertext': encrypted['ciphertext'],
      'mac': encrypted['mac'],
    };
    final content = const JsonEncoder.withIndent('  ').convert(payload);
    final exportBytes = Uint8List.fromList(utf8.encode(content));
    final isMobilePlatform = Platform.isAndroid || Platform.isIOS;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: strings.exportServers,
      fileName: 'xylos-servers.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: isMobilePlatform ? exportBytes : null,
    );
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    if (!isMobilePlatform) {
      await File(path).writeAsString(content, flush: true);
    }
    return strings.exportSucceeded(path);
  }

  Future<String?> _importServers() async {
    if (!widget.store.isSessionUnlocked) {
      final passphrase = await _promptSessionPassphrase(forceUnlockTitle: true);
      if (passphrase == null || passphrase.isEmpty) {
        return null;
      }
      await widget.store.unlockSession(passphrase);
    }
    final passphrase = widget.store.sessionPassphrase;
    if (passphrase == null || passphrase.isEmpty) {
      throw const FormatException('Passphrase is required.');
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: strings.importServers,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final pickedFile = result?.files.single;
    if (pickedFile == null) {
      return null;
    }
    final path = pickedFile.path?.trim() ?? '';
    final bytes = pickedFile.bytes;
    final content =
        bytes != null ? utf8.decode(bytes) : await File(path).readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid config format.');
    }

    final format = decoded['format'] as String? ?? '';
    final version = decoded['version'];
    if (format != 'xylos.server-config') {
      throw const FormatException('Unsupported config version.');
    }

    if (version != 2) {
      throw const FormatException('Unsupported config version.');
    }
    final decrypted = decryptPayload(
      decoded,
      passphrase,
      header: 'xylos.server-config|2',
    );
    if (decrypted is! Map<String, Object?>) {
      throw const FormatException('Invalid decrypted config.');
    }
    return _restoreServersFromJson(decrypted);
  }

  Future<String> _restoreServersFromJson(Map<String, Object?> decoded) async {
    final rawServers = decoded['servers'];
    if (rawServers is! List) {
      throw const FormatException('Missing servers list.');
    }

    final servers = rawServers
        .map(
          (item) => WebDavAccount.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        )
        .toList();
    await _replaceServers(servers);
    return strings.importSucceeded(servers.length);
  }

  Future<String?> _importServerFromQr() async {
    if (!widget.store.isSessionUnlocked) {
      final passphrase = await _promptSessionPassphrase(forceUnlockTitle: true);
      if (passphrase == null || passphrase.isEmpty) {
        return null;
      }
      await widget.store.unlockSession(passphrase);
    }
    final passphrase = widget.store.sessionPassphrase;
    if (passphrase == null || passphrase.isEmpty) {
      throw const FormatException('Passphrase is required.');
    }
    if (!mounted) {
      return null;
    }
    final content = await showDialog<String?>(
      context: context,
      builder: (context) => QrScannerDialog(strings: strings),
    );
    if (content == null || content.isEmpty) {
      return null;
    }
    final server = decodeServerQrPayload(content, passphrase);
    await _upsertImportedServer(server);
    return strings.importServerSucceeded(server.name);
  }

  Future<void> _upsertImportedServer(WebDavAccount server) async {
    final nextServers = [..._servers];
    final index = nextServers.indexWhere((item) => item.id == server.id);
    if (index == -1) {
      nextServers.add(server);
    } else {
      nextServers[index] = server;
    }
    await _replaceServers(nextServers);
  }

  Future<String> _exportServerQr(WebDavAccount server) async {
    final hydratedServer = await _hydrateServerForSession(server);
    final passphrase = widget.store.sessionPassphrase;
    if (passphrase == null || passphrase.isEmpty) {
      throw const FormatException('Passphrase is required.');
    }
    final payload = encodeServerQrPayload(hydratedServer, passphrase);
    if (!mounted) {
      return strings.serverQrExported;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => ServerQrDialog(
        strings: strings,
        server: hydratedServer,
        payload: payload,
      ),
    );
    return strings.serverQrExported;
  }

  Future<void> _persistTransfers() async {
    await widget.store.saveTransfers(_transfers);
  }

  Future<void> _upsertTransfer(TransferRecord transfer) async {
    final index = _transfers.indexWhere((item) => item.id == transfer.id);
    setState(() {
      if (index == -1) {
        _transfers.insert(0, transfer);
      } else {
        _transfers[index] = transfer;
      }
      _transfers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    await _persistTransfers();
  }

  Future<void> _clearCompletedTransfers() async {
    setState(() {
      _transfers.removeWhere((item) => item.status != TransferStatus.running);
    });
    await _persistTransfers();
  }

  Future<void> _cleanTransfer(TransferRecord transfer) async {
    setState(() {
      _transfers.removeWhere((item) => item.id == transfer.id);
    });
    await _persistTransfers();
  }

  Future<void> _retryTransfer(TransferRecord transfer) async {
    final server = _servers.cast<WebDavAccount?>().firstWhere(
          (item) => item?.name == transfer.serverName,
          orElse: () => null,
        );
    if (server == null) {
      return;
    }

    final retryRecord = transfer.copyWith(
      status: TransferStatus.running,
      finishedAt: null,
      errorMessage: null,
      clearFinishedAt: true,
      clearErrorMessage: true,
    );
    await _upsertTransfer(retryRecord);

    try {
      if (transfer.direction == TransferDirection.download) {
        final localFile = File(transfer.localPath);
        final parentDirectory = localFile.parent;
        if (!await parentDirectory.exists()) {
          await parentDirectory.create(recursive: true);
        }
        final bytes =
            await WebDavClient(server).downloadBytes(transfer.remotePath);
        await localFile.writeAsBytes(bytes, flush: true);
      } else {
        final localFile = File(transfer.localPath);
        await WebDavClient(server).uploadFile(transfer.remotePath, localFile);
      }

      await _upsertTransfer(
        retryRecord.copyWith(
          status: TransferStatus.success,
          finishedAt: DateTime.now(),
          clearErrorMessage: true,
        ),
      );
    } on WebDavException catch (error) {
      final message = strings.webDavError(error);
      await _upsertTransfer(
        retryRecord.copyWith(
          status: TransferStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: message,
        ),
      );
    } on FileSystemException catch (error) {
      await _upsertTransfer(
        retryRecord.copyWith(
          status: TransferStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: error.message,
        ),
      );
    }
  }

  Future<void> _openLocalFolder(String path) async {
    final directoryPath = path.trim();
    if (directoryPath.isEmpty) {
      return;
    }
    final result = await OpenFilex.open(directoryPath);
    if (result.type == ResultType.done || !mounted) {
      return;
    }
    _showSnackBar(context, strings.openFolderFailed(result.message));
  }

  void _selectDestination(int index) {
    setState(() {
      _selectedIndex = index;
      if (index != 0) {
        _activeServer = null;
      }
    });
  }
}

class SettingsPage extends StatelessWidget {
  static final Uri _githubUri = Uri.parse(
    'https://github.com/maoyutofu/xylos-app',
  );
  static final Uri _discussionsUri = Uri.parse(
    'https://github.com/maoyutofu/xylos-app/discussions',
  );

  const SettingsPage({
    super.key,
    required this.language,
    required this.strings,
    required this.appVersion,
    required this.downloadDirectory,
    required this.sessionUnlocked,
    required this.onLanguageChanged,
    required this.onDownloadDirectoryChanged,
    required this.onChangeMasterPassphrase,
    required this.onExportServers,
    required this.onImportServers,
  });

  final AppLanguage language;
  final AppStrings strings;
  final String appVersion;
  final String downloadDirectory;
  final bool sessionUnlocked;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final ValueChanged<String> onDownloadDirectoryChanged;
  final Future<String?> Function() onChangeMasterPassphrase;
  final Future<String?> Function() onExportServers;
  final Future<String?> Function() onImportServers;

  static const double _downloadDirectoryControlHeight = 40;

  bool get _supportsDirectoryPicker => !Platform.isAndroid && !Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SectionHeader(title: strings.settingsTitle),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.language,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AppLanguage>(
                    segments: const [
                      ButtonSegment(
                        value: AppLanguage.zh,
                        label: Text('中文'),
                      ),
                      ButtonSegment(
                        value: AppLanguage.en,
                        label: Text('English'),
                      ),
                    ],
                    selected: {language},
                    onSelectionChanged: (selection) {
                      onLanguageChanged(selection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.downloadDirectory,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _supportsDirectoryPicker
                        ? strings.serverDownloadDirectory
                        : strings.mobileDownloadDirectoryHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: _downloadDirectoryControlHeight,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                downloadDirectory.isEmpty
                                    ? strings.downloadDirectoryNotSet
                                    : downloadDirectory,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_supportsDirectoryPicker) ...[
                        const SizedBox(width: 12),
                        SizedBox(
                          height: _downloadDirectoryControlHeight,
                          child: FilledButton.icon(
                            onPressed: () => _chooseDownloadDirectory(context),
                            icon: const Icon(Icons.folder_open),
                            label: Text(strings.chooseDirectory),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: Text(strings.exportServers),
                  subtitle: Text(
                    sessionUnlocked
                        ? strings.masterPassphraseUnlocked
                        : strings.masterPassphraseLocked,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _runExport(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(strings.importServers),
                  subtitle: Text(
                    sessionUnlocked
                        ? strings.masterPassphraseUnlocked
                        : strings.masterPassphraseLocked,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _runImport(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.password),
                  title: Text(strings.changeMasterPassphrase),
                  subtitle: Text(
                    sessionUnlocked
                        ? strings.masterPassphraseUnlocked
                        : strings.masterPassphraseLocked,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _runChangeMasterPassphrase(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(strings.version),
                  subtitle: Text(appVersion),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(strings.github),
                  subtitle: const Text('github.com/maoyutofu/xylos-app'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternalLink(context, _githubUri),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: Text(strings.discussions),
                  subtitle: const Text(
                    'github.com/maoyutofu/xylos-app/discussions',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternalLink(context, _discussionsUri),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDownloadDirectory(BuildContext context) async {
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: strings.chooseDirectory,
    );
    if (directory == null || directory.trim().isEmpty) {
      return;
    }
    onDownloadDirectoryChanged(directory);
  }

  Future<void> _openExternalLink(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.openFailed(uri.toString()))));
  }

  Future<void> _runConfigAction(
    BuildContext context,
    Future<String?> Function() action,
  ) async {
    try {
      final message = await action();
      if (message == null || !context.mounted) {
        return;
      }
      _showSnackBar(context, message);
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, strings.configActionFailed(error.message));
    } on FileSystemException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, strings.configActionFailed(error.message));
    }
  }

  Future<void> _runExport(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    await _runConfigAction(context, onExportServers);
  }

  Future<void> _runImport(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    await _runConfigAction(context, onImportServers);
  }

  Future<void> _runChangeMasterPassphrase(BuildContext context) async {
    if (!context.mounted) {
      return;
    }
    await _runConfigAction(context, onChangeMasterPassphrase);
  }
}

class ServerEditorDialog extends StatefulWidget {
  const ServerEditorDialog({
    super.key,
    required this.server,
    required this.servers,
    required this.strings,
  });

  final WebDavAccount? server;
  final List<WebDavAccount> servers;
  final AppStrings strings;

  @override
  State<ServerEditorDialog> createState() => _ServerEditorDialogState();
}

class _ServerEditorDialogState extends State<ServerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _aliasController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _secretController;
  AuthType _authType = AuthType.basic;
  DigestAlgorithm _digestAlgorithm = DigestAlgorithm.md5;
  bool _allowHttp = false;
  bool _trustSelfSignedCert = false;

  AppStrings get strings => widget.strings;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _aliasController = TextEditingController(text: server?.name ?? '');
    _baseUrlController = TextEditingController(text: server?.baseUrl ?? '');
    _usernameController = TextEditingController(text: server?.username ?? '');
    _secretController = TextEditingController(text: server?.secret ?? '');
    _authType = server?.authType ?? AuthType.basic;
    _digestAlgorithm = server?.digestAlgorithm ?? DigestAlgorithm.md5;
    _allowHttp = server?.allowHttp ?? false;
    _trustSelfSignedCert = server?.trustSelfSignedCert ?? false;
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _baseUrlController.dispose();
    _usernameController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.server == null ? strings.addServer : strings.editServer),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _aliasController,
                  decoration: InputDecoration(labelText: strings.serverAlias),
                  validator: _validateAlias,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _baseUrlController,
                  decoration: InputDecoration(
                    labelText: strings.serverUrl,
                    hintText: 'https://example.com/dav',
                  ),
                  keyboardType: TextInputType.url,
                  validator: _validateBaseUrl,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AuthType>(
                  value: _authType,
                  decoration: InputDecoration(labelText: strings.authType),
                  items: [
                    for (final type in AuthType.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _authType = value;
                    });
                  },
                ),
                if (_authType == AuthType.basic ||
                    _authType == AuthType.digest) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(labelText: strings.username),
                    validator: _required,
                  ),
                ],
                if (_authType == AuthType.digest) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DigestAlgorithm>(
                    value: _digestAlgorithm,
                    decoration: InputDecoration(
                      labelText: strings.digestAlgorithm,
                    ),
                    items: [
                      for (final type in DigestAlgorithm.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _digestAlgorithm = value;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secretController,
                  decoration: InputDecoration(
                    labelText: _authType == AuthType.bearer
                        ? 'Token'
                        : _authType == AuthType.basic
                            ? strings.password
                            : strings.password,
                  ),
                  obscureText: true,
                  validator: _required,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.allowHttp),
                  subtitle: Text(strings.allowHttpDescription),
                  value: _allowHttp,
                  onChanged: (value) {
                    setState(() {
                      _allowHttp = value;
                    });
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.trustSelfSignedCert),
                  subtitle: Text(strings.trustSelfSignedCertDescription),
                  value: _trustSelfSignedCert,
                  onChanged: (value) {
                    setState(() {
                      _trustSelfSignedCert = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(strings.save),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      AppLogger.debug('UI', 'server form validation failed');
      return;
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    AppLogger.debug(
      'UI',
      'submit server alias=${_aliasController.text.trim()} baseUrl=${_baseUrlController.text.trim()} defaultPath=/ auth=${_authType.name} usernameSet=${_usernameController.text.trim().isNotEmpty} secretSet=${_secretController.text.isNotEmpty} allowHttp=$_allowHttp trustSelfSignedCert=$_trustSelfSignedCert',
    );
    Navigator.of(context).pop(
      WebDavAccount(
        id: widget.server?.id ?? 'server-$now',
        name: _aliasController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        authType: _authType,
        digestAlgorithm: _digestAlgorithm,
        username:
            _authType == AuthType.bearer ? '' : _usernameController.text.trim(),
        secret: _secretController.text,
        defaultPath: '/',
        allowHttp: _allowHttp,
        trustSelfSignedCert: _trustSelfSignedCert,
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return strings.requiredField;
    }
    return null;
  }

  String? _validateAlias(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) {
      return requiredError;
    }

    final alias = value!.trim().toLowerCase();
    final currentServerId = widget.server?.id;
    final duplicated = widget.servers.any((server) {
      if (server.id == currentServerId) {
        return false;
      }
      return server.name.trim().toLowerCase() == alias;
    });
    if (duplicated) {
      return strings.duplicateServerAlias;
    }
    return null;
  }

  String? _validateBaseUrl(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) {
      return requiredError;
    }
    final uri = Uri.tryParse(value!.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return strings.invalidUrl;
    }
    if (uri.scheme == 'http' && !_allowHttp) {
      return strings.httpRequiresOptIn;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return strings.unsupportedScheme;
    }
    return null;
  }
}

class TransfersPage extends StatelessWidget {
  const TransfersPage({
    super.key,
    required this.strings,
    required this.transfers,
    required this.onRetry,
    required this.onClearCompleted,
    required this.onOpenFolder,
    required this.onClean,
  });

  final AppStrings strings;
  final List<TransferRecord> transfers;
  final ValueChanged<TransferRecord> onRetry;
  final Future<void> Function() onClearCompleted;
  final Future<void> Function(String path) onOpenFolder;
  final Future<void> Function(TransferRecord transfer) onClean;

  @override
  Widget build(BuildContext context) {
    final supportsQrImport = Platform.isAndroid || Platform.isIOS;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: strings.transfersTitle,
              action: TextButton(
                onPressed: transfers.isEmpty ? null : onClearCompleted,
                child: Text(strings.clearCompleted),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: transfers.isEmpty
                  ? EmptyState(
                      icon: Icons.sync_alt,
                      title: strings.transfersEmptyTitle,
                      message: strings.transfersEmptyMessage,
                    )
                  : ListView.separated(
                      itemCount: transfers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final transfer = transfers[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: Icon(_transferIcon(transfer.direction)),
                            title: Text(_lastPathSegment(transfer.remotePath)),
                            subtitle: Text(
                              '${transfer.serverName} · ${_transferDirectionLabel(strings, transfer.direction)} · ${_transferStatusLabel(strings, transfer.status)}',
                            ),
                            trailing: PopupMenuButton<_TransferEntryAction>(
                              tooltip: strings.openFolder,
                              onSelected: (action) {
                                switch (action) {
                                  case _TransferEntryAction.openFolder:
                                    onOpenFolder(
                                      _parentDirectoryPath(transfer.localPath),
                                    );
                                  case _TransferEntryAction.retry:
                                    onRetry(transfer);
                                  case _TransferEntryAction.clean:
                                    onClean(transfer);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: _TransferEntryAction.openFolder,
                                  child: ListTile(
                                    leading: const Icon(Icons.folder_open),
                                    title: Text(strings.openFolder),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                if (transfer.status == TransferStatus.failed)
                                  PopupMenuItem(
                                    value: _TransferEntryAction.retry,
                                    child: ListTile(
                                      leading: const Icon(Icons.refresh),
                                      title: Text(strings.retry),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: _TransferEntryAction.clean,
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.cleaning_services_outlined),
                                    title: Text(strings.clean),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TransferEntryAction {
  openFolder,
  retry,
  clean;
}

class OfflinePage extends StatefulWidget {
  const OfflinePage({
    super.key,
    required this.strings,
    required this.downloadDirectory,
    required this.onOpenFolder,
  });

  final AppStrings strings;
  final String downloadDirectory;
  final Future<void> Function(String path) onOpenFolder;

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  var _loading = true;
  var _serverPath = '';
  var _rootPath = '';
  List<FileSystemEntity> _entries = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _rootPath = _normalizeLocalPath(widget.downloadDirectory);
    _loadRoot();
  }

  @override
  void didUpdateWidget(covariant OfflinePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadDirectory != widget.downloadDirectory) {
      _rootPath = _normalizeLocalPath(widget.downloadDirectory);
      _serverPath = '';
      _loadRoot();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _serverPath.isEmpty
        ? widget.strings.offlineTitle
        : '${_lastPathSegment(_serverPath)} · ${widget.strings.localFilesTitle}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: title),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: widget.strings.parentDirectory,
                  onPressed: _canNavigateBack ? _navigateBack : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: widget.strings.refresh,
                  onPressed: _loading ? null : _loadRoot,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey(_currentLocalPath),
                    initialValue: _currentLocalPath,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                    onFieldSubmitted: _openPathFromInput,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: widget.strings.loadFailed,
        message: _error!,
      );
    }
    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.download_done_outlined,
        title: widget.strings.offlineEmptyTitle,
        message: widget.strings.offlineEmptyMessage,
      );
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final stat = entry.statSync();
        final isDirectory = entry is Directory;
        return ListTile(
          leading: _OfflineEntryPreview(entry: entry),
          title: Text(_lastPathSegment(entry.path)),
          subtitle: Text(
            isDirectory
                ? widget.strings.directory
                : _formatSize(stat.size, widget.strings),
          ),
          trailing: PopupMenuButton<_OfflineEntryAction>(
            tooltip: widget.strings.openFolder,
            onSelected: (action) {
              switch (action) {
                case _OfflineEntryAction.openFolder:
                  final targetPath = isDirectory
                      ? entry.path
                      : _parentDirectoryPath(entry.path);
                  widget.onOpenFolder(targetPath);
                case _OfflineEntryAction.delete:
                  _deleteLocalEntry(entry);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _OfflineEntryAction.openFolder,
                child: ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(widget.strings.openFolder),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _OfflineEntryAction.delete,
                child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(widget.strings.delete),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          onTap: () =>
              isDirectory ? _openDirectory(entry.path) : _openLocal(entry.path),
        );
      },
    );
  }

  Future<void> _loadRoot() async {
    await _loadEntries(_currentLocalPath);
  }

  Future<void> _loadEntries(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (path.isEmpty) {
        setState(() {
          _entries = const [];
        });
        return;
      }
      final directory = Directory(path);
      if (!await directory.exists()) {
        setState(() {
          _entries = const [];
        });
        return;
      }
      final entries = await directory.list().toList();
      entries.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) {
          return aDir ? -1 : 1;
        }
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
      });
    } on FileSystemException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = const [];
        _error = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openDirectory(String path) {
    final normalizedPath = _normalizeLocalPath(path);
    setState(() {
      _serverPath = normalizedPath;
    });
    _loadEntries(normalizedPath);
  }

  void _openPathFromInput(String value) {
    final normalizedPath = _normalizeLocalPath(value);
    setState(() {
      _serverPath = normalizedPath == _rootPath ? '' : normalizedPath;
    });
    _loadEntries(normalizedPath);
  }

  Future<void> _openLocal(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type == ResultType.done || !mounted) {
      return;
    }
    _showSnackBar(context, widget.strings.openFailed(result.message));
  }

  Future<void> _deleteLocalEntry(FileSystemEntity entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(widget.strings.delete),
          content: Text(
            '${widget.strings.deleteResourceConfirm(_lastPathSegment(entry.path))}\n${widget.strings.deleteLocalOnlyMessage}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(widget.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(widget.strings.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      if (entry is Directory) {
        await entry.delete(recursive: true);
      } else {
        await entry.delete();
      }
      if (!mounted) {
        return;
      }
      _showSnackBar(context, widget.strings.deleteSucceeded);
      await _loadEntries(_currentLocalPath);
    } on FileSystemException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(context, error.message);
    }
  }

  void _navigateBack() {
    if (!_canNavigateBack) {
      return;
    }
    final currentPath = _currentLocalPath;
    if (currentPath == _rootPath) {
      setState(() {
        _serverPath = '';
      });
      _loadEntries(_rootPath);
      return;
    }
    final current = currentPath.endsWith(Platform.pathSeparator)
        ? currentPath.substring(0, currentPath.length - 1)
        : currentPath;
    final index = current.lastIndexOf(Platform.pathSeparator);
    final parent = index <= 0 ? _rootPath : current.substring(0, index);
    setState(() {
      _serverPath = parent == _rootPath ? '' : parent;
    });
    _loadEntries(parent);
  }

  String get _currentLocalPath => _serverPath.isEmpty ? _rootPath : _serverPath;

  bool get _canNavigateBack {
    final currentPath = _currentLocalPath;
    return currentPath.isNotEmpty && currentPath != _rootPath;
  }
}

enum _OfflineEntryAction {
  openFolder,
  delete;
}

enum _ServerTileAction {
  exportQr,
  edit,
  delete;
}

class _OfflineEntryPreview extends StatelessWidget {
  const _OfflineEntryPreview({required this.entry});

  final FileSystemEntity entry;

  @override
  Widget build(BuildContext context) {
    final isDirectory = entry is Directory;
    final path = entry.path;
    if (isDirectory) {
      return const _OfflinePreviewFrame(
        child: _LocalResourceIconPlaceholder(
          icon: Icons.folder,
          isDirectory: true,
          iconSize: 24,
        ),
      );
    }
    if (_isLocalImagePath(path)) {
      return _OfflinePreviewFrame(
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _LocalResourceIconPlaceholder(
            icon: Icons.broken_image_outlined,
            isDirectory: false,
            iconSize: 24,
          ),
        ),
      );
    }
    if (_isLocalVideoPath(path)) {
      return const _OfflinePreviewFrame(
        child: _LocalResourceIconPlaceholder(
          icon: Icons.videocam_outlined,
          isDirectory: false,
          iconSize: 24,
        ),
      );
    }
    return const _OfflinePreviewFrame(
      child: _LocalResourceIconPlaceholder(
        icon: Icons.insert_drive_file_outlined,
        isDirectory: false,
        iconSize: 24,
      ),
    );
  }
}

class _OfflinePreviewFrame extends StatelessWidget {
  const _OfflinePreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }
}

class _LocalResourceIconPlaceholder extends StatelessWidget {
  const _LocalResourceIconPlaceholder({
    required this.icon,
    required this.isDirectory,
    required this.iconSize,
  });

  final IconData icon;
  final bool isDirectory;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isDirectory
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = isDirectory
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Icon(icon, size: iconSize, color: foregroundColor),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class ServerQrDialog extends StatelessWidget {
  const ServerQrDialog({
    super.key,
    required this.strings,
    required this.server,
    required this.payload,
  });

  final AppStrings strings;
  final WebDavAccount server;
  final String payload;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(strings.exportServerQr),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              server.name,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            QrImageView(
              data: payload,
              size: 240,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              strings.serverQrHint,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
    );
  }
}

class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({super.key, required this.strings});

  final AppStrings strings;

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.scanServerQr),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  onDetect: (capture) {
                    if (_handled) {
                      return;
                    }
                    final value = capture.barcodes.first.rawValue?.trim() ?? '';
                    if (value.isEmpty) {
                      return;
                    }
                    _handled = true;
                    Navigator.of(context).pop(value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.strings.scanServerQrHint,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.strings.cancel),
        ),
      ],
    );
  }
}

enum AppLanguage {
  zh('zh'),
  en('en');

  const AppLanguage(this.code);

  final String code;

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => AppLanguage.zh,
    );
  }
}

enum FileSortField {
  name,
  type,
  size,
  modified;
}

enum FileViewMode {
  list,
  grid;
}

class AppStrings {
  const AppStrings._({
    required this.serversNav,
    required this.transfersNav,
    required this.offlineNav,
    required this.settingsNav,
    required this.serversTitle,
    required this.filesTitle,
    required this.transfersTitle,
    required this.offlineTitle,
    required this.settingsTitle,
    required this.addServer,
    required this.editServer,
    required this.deleteServer,
    required this.deleteServerConfirmTemplate,
    required this.serverAlias,
    required this.noServersTitle,
    required this.noServersMessage,
    required this.backToServers,
    required this.testConnection,
    required this.connectionTestSucceeded,
    required this.refresh,
    required this.sortBy,
    required this.sortByName,
    required this.sortByType,
    required this.sortBySize,
    required this.sortByModified,
    required this.listView,
    required this.gridView,
    required this.uploadFile,
    required this.uploadFromFiles,
    required this.uploadFromMedia,
    required this.uploadSucceeded,
    required this.uploadBatchSucceededTemplate,
    required this.uploadBatchResultTemplate,
    required this.uploadBatchFailedFilesTemplate,
    required this.uploadFailedFilesTitle,
    required this.localFileNotFound,
    required this.createDirectory,
    required this.createDirectorySucceeded,
    required this.directoryName,
    required this.deleteSucceeded,
    required this.deleteResourceConfirmTemplate,
    required this.deleteLocalOnlyMessage,
    required this.download,
    required this.downloadSucceededTemplate,
    required this.downloadAlreadyExistsTemplate,
    required this.openFailedTemplate,
    required this.serverDownloadDirectory,
    required this.mobileDownloadDirectoryHint,
    required this.downloadDirectory,
    required this.downloadDirectoryNotSet,
    required this.chooseDirectory,
    required this.downloadDirectoryRequired,
    required this.currentPath,
    required this.loadFailed,
    required this.emptyDirectory,
    required this.emptyDirectoryMessage,
    required this.parentDirectory,
    required this.directory,
    required this.unknownSize,
    required this.transfersPlaceholder,
    required this.offlinePlaceholder,
    required this.transfersEmptyTitle,
    required this.transfersEmptyMessage,
    required this.clearCompleted,
    required this.clean,
    required this.retry,
    required this.statusRunning,
    required this.statusSuccess,
    required this.statusFailed,
    required this.uploadLabel,
    required this.downloadLabel,
    required this.offlineEmptyTitle,
    required this.offlineEmptyMessage,
    required this.localFilesTitle,
    required this.openFolder,
    required this.openFolderFailedTemplate,
    required this.language,
    required this.exportServers,
    required this.importServers,
    required this.exportServerQr,
    required this.scanServerQr,
    required this.serverQrHint,
    required this.scanServerQrHint,
    required this.serverQrExported,
    required this.importServerSucceededTemplate,
    required this.exportSucceededTemplate,
    required this.importSucceededTemplate,
    required this.configActionFailedTemplate,
    required this.configPassphrase,
    required this.confirmPassphrase,
    required this.togglePassphraseVisibility,
    required this.passphraseRequired,
    required this.passphraseMismatch,
    required this.unlockSecrets,
    required this.createPassphrase,
    required this.changeMasterPassphrase,
    required this.masterPassphraseChanged,
    required this.masterPassphraseUnlocked,
    required this.masterPassphraseLocked,
    required this.version,
    required this.github,
    required this.discussions,
    required this.serverUrl,
    required this.authType,
    required this.digestAlgorithm,
    required this.username,
    required this.password,
    required this.allowHttp,
    required this.allowHttpDescription,
    required this.trustSelfSignedCert,
    required this.trustSelfSignedCertDescription,
    required this.cancel,
    required this.close,
    required this.delete,
    required this.save,
    required this.requiredField,
    required this.duplicateServerAlias,
    required this.invalidUrl,
    required this.httpRequiresOptIn,
    required this.unsupportedScheme,
    required this.pendingSuffix,
    required this.webDavHttpDisabled,
    required this.webDavTimeout,
    required this.webDavCertificate,
    required this.webDavNetworkTemplate,
    required this.webDavDigestAlgorithmMismatchTemplate,
    required this.webDavDigestUnsupportedQopTemplate,
    required this.webDavUnauthorized,
    required this.webDavForbidden,
    required this.webDavNotFound,
    required this.webDavMethodNotAllowed,
    required this.webDavConflict,
    required this.webDavPayloadTooLarge,
    required this.webDavLocked,
    required this.webDavHttpStatusTemplate,
    required this.webDavHttpStatusWithDetailTemplate,
    required this.webDavDirectoryDownloadFailed,
  });

  final String serversNav;
  final String transfersNav;
  final String offlineNav;
  final String settingsNav;
  final String serversTitle;
  final String filesTitle;
  final String transfersTitle;
  final String offlineTitle;
  final String settingsTitle;
  final String addServer;
  final String editServer;
  final String deleteServer;
  final String deleteServerConfirmTemplate;
  final String serverAlias;
  final String noServersTitle;
  final String noServersMessage;
  final String backToServers;
  final String testConnection;
  final String connectionTestSucceeded;
  final String refresh;
  final String sortBy;
  final String sortByName;
  final String sortByType;
  final String sortBySize;
  final String sortByModified;
  final String listView;
  final String gridView;
  final String uploadFile;
  final String uploadFromFiles;
  final String uploadFromMedia;
  final String uploadSucceeded;
  final String uploadBatchSucceededTemplate;
  final String uploadBatchResultTemplate;
  final String uploadBatchFailedFilesTemplate;
  final String uploadFailedFilesTitle;
  final String localFileNotFound;
  final String createDirectory;
  final String createDirectorySucceeded;
  final String directoryName;
  final String deleteSucceeded;
  final String deleteResourceConfirmTemplate;
  final String deleteLocalOnlyMessage;
  final String download;
  final String downloadSucceededTemplate;
  final String downloadAlreadyExistsTemplate;
  final String openFailedTemplate;
  final String serverDownloadDirectory;
  final String mobileDownloadDirectoryHint;
  final String downloadDirectory;
  final String downloadDirectoryNotSet;
  final String chooseDirectory;
  final String downloadDirectoryRequired;
  final String currentPath;
  final String loadFailed;
  final String emptyDirectory;
  final String emptyDirectoryMessage;
  final String parentDirectory;
  final String directory;
  final String unknownSize;
  final String transfersPlaceholder;
  final String offlinePlaceholder;
  final String transfersEmptyTitle;
  final String transfersEmptyMessage;
  final String clearCompleted;
  final String clean;
  final String retry;
  final String statusRunning;
  final String statusSuccess;
  final String statusFailed;
  final String uploadLabel;
  final String downloadLabel;
  final String offlineEmptyTitle;
  final String offlineEmptyMessage;
  final String localFilesTitle;
  final String openFolder;
  final String openFolderFailedTemplate;
  final String language;
  final String exportServers;
  final String importServers;
  final String exportServerQr;
  final String scanServerQr;
  final String serverQrHint;
  final String scanServerQrHint;
  final String serverQrExported;
  final String importServerSucceededTemplate;
  final String exportSucceededTemplate;
  final String importSucceededTemplate;
  final String configActionFailedTemplate;
  final String configPassphrase;
  final String confirmPassphrase;
  final String togglePassphraseVisibility;
  final String passphraseRequired;
  final String passphraseMismatch;
  final String unlockSecrets;
  final String createPassphrase;
  final String changeMasterPassphrase;
  final String masterPassphraseChanged;
  final String masterPassphraseUnlocked;
  final String masterPassphraseLocked;
  final String version;
  final String github;
  final String discussions;
  final String serverUrl;
  final String authType;
  final String digestAlgorithm;
  final String username;
  final String password;
  final String allowHttp;
  final String allowHttpDescription;
  final String trustSelfSignedCert;
  final String trustSelfSignedCertDescription;
  final String cancel;
  final String close;
  final String delete;
  final String save;
  final String requiredField;
  final String duplicateServerAlias;
  final String invalidUrl;
  final String httpRequiresOptIn;
  final String unsupportedScheme;
  final String pendingSuffix;
  final String webDavHttpDisabled;
  final String webDavTimeout;
  final String webDavCertificate;
  final String webDavNetworkTemplate;
  final String webDavDigestAlgorithmMismatchTemplate;
  final String webDavDigestUnsupportedQopTemplate;
  final String webDavUnauthorized;
  final String webDavForbidden;
  final String webDavNotFound;
  final String webDavMethodNotAllowed;
  final String webDavConflict;
  final String webDavPayloadTooLarge;
  final String webDavLocked;
  final String webDavHttpStatusTemplate;
  final String webDavHttpStatusWithDetailTemplate;
  final String webDavDirectoryDownloadFailed;

  String deleteServerConfirm(String alias) {
    return deleteServerConfirmTemplate.replaceAll('{alias}', alias);
  }

  String deleteResourceConfirm(String name) {
    return deleteResourceConfirmTemplate.replaceAll('{name}', name);
  }

  String downloadSucceeded(String path) {
    return downloadSucceededTemplate.replaceAll('{path}', path);
  }

  String uploadBatchSucceeded(int count) {
    return uploadBatchSucceededTemplate.replaceAll('{count}', '$count');
  }

  String uploadBatchResult(int successCount, int failedCount) {
    return uploadBatchResultTemplate
        .replaceAll('{successCount}', '$successCount')
        .replaceAll('{failedCount}', '$failedCount');
  }

  String uploadBatchFailedFiles(
    int successCount,
    int failedCount,
    String fileNames,
  ) {
    return uploadBatchFailedFilesTemplate
        .replaceAll('{successCount}', '$successCount')
        .replaceAll('{failedCount}', '$failedCount')
        .replaceAll('{fileNames}', fileNames);
  }

  String downloadAlreadyExists(String path) {
    return downloadAlreadyExistsTemplate.replaceAll('{path}', path);
  }

  String openFailed(String message) {
    return openFailedTemplate.replaceAll('{message}', message);
  }

  String openFolderFailed(String message) {
    return openFolderFailedTemplate.replaceAll('{message}', message);
  }

  String exportSucceeded(String path) {
    return exportSucceededTemplate.replaceAll('{path}', path);
  }

  String importSucceeded(int count) {
    return importSucceededTemplate.replaceAll('{count}', '$count');
  }

  String importServerSucceeded(String name) {
    return importServerSucceededTemplate.replaceAll('{name}', name);
  }

  String configActionFailed(String message) {
    return configActionFailedTemplate.replaceAll('{message}', message);
  }

  String webDavError(WebDavException error) {
    switch (error.kind) {
      case WebDavFailureKind.httpDisabled:
        return webDavHttpDisabled;
      case WebDavFailureKind.timeout:
        return webDavTimeout;
      case WebDavFailureKind.certificate:
        return webDavCertificate;
      case WebDavFailureKind.network:
        return webDavNetworkTemplate.replaceAll(
          '{detail}',
          error.detail ?? '',
        );
      case WebDavFailureKind.digestAlgorithmMismatch:
        return webDavDigestAlgorithmMismatchTemplate
            .replaceAll('{serverAlgorithm}', error.serverAlgorithm ?? '')
            .replaceAll('{selectedAlgorithm}', error.selectedAlgorithm ?? '');
      case WebDavFailureKind.digestUnsupportedQop:
        return webDavDigestUnsupportedQopTemplate.replaceAll(
          '{qop}',
          error.qop ?? '',
        );
      case WebDavFailureKind.unauthorized:
        return webDavUnauthorized;
      case WebDavFailureKind.forbidden:
        return webDavForbidden;
      case WebDavFailureKind.notFound:
        return webDavNotFound;
      case WebDavFailureKind.methodNotAllowed:
        return webDavMethodNotAllowed;
      case WebDavFailureKind.conflict:
        return webDavConflict;
      case WebDavFailureKind.payloadTooLarge:
        return webDavPayloadTooLarge;
      case WebDavFailureKind.locked:
        return webDavLocked;
      case WebDavFailureKind.httpStatus:
        final statusCode = '${error.statusCode ?? 0}';
        final detail = error.detail?.trim() ?? '';
        if (detail.isEmpty || _containsHanCharacters(detail)) {
          return webDavHttpStatusTemplate.replaceAll(
            '{statusCode}',
            statusCode,
          );
        }
        return webDavHttpStatusWithDetailTemplate
            .replaceAll('{statusCode}', statusCode)
            .replaceAll('{detail}', detail);
      case WebDavFailureKind.directoryDownloadFailed:
        return webDavDirectoryDownloadFailed;
    }
  }

  String modulePending(String title) => '$title$pendingSuffix';

  static AppStrings of(AppLanguage language) {
    switch (language) {
      case AppLanguage.zh:
        return zh;
      case AppLanguage.en:
        return en;
    }
  }

  static const zh = AppStrings._(
    serversNav: '服务器',
    transfersNav: '传输',
    offlineNav: '离线',
    settingsNav: '设置',
    serversTitle: '服务器',
    filesTitle: '文件',
    transfersTitle: '传输中心',
    offlineTitle: '离线文件',
    settingsTitle: '设置',
    addServer: '添加服务器',
    editServer: '编辑服务器',
    deleteServer: '删除服务器',
    deleteServerConfirmTemplate: '确认删除“{alias}”？此操作不会删除服务端文件。',
    serverAlias: '别名',
    noServersTitle: '暂无服务器',
    noServersMessage: '添加一个 WebDAV 服务器后，点击服务器即可进入文件列表。',
    backToServers: '返回服务器',
    testConnection: '测试连接',
    connectionTestSucceeded: '连接测试成功',
    refresh: '刷新',
    sortBy: '排序',
    sortByName: '按名称排序',
    sortByType: '按类型排序',
    sortBySize: '按大小排序',
    sortByModified: '按时间排序',
    listView: '列表视图',
    gridView: '网格视图',
    uploadFile: '上传文件',
    uploadFromFiles: '从文件选择',
    uploadFromMedia: '从相册选择',
    uploadSucceeded: '上传完成',
    uploadBatchSucceededTemplate: '已上传 {count} 个文件',
    uploadBatchResultTemplate: '上传完成，成功 {successCount} 个，失败 {failedCount} 个',
    uploadBatchFailedFilesTemplate:
        '上传完成，成功 {successCount} 个，失败 {failedCount} 个。失败文件：{fileNames}',
    uploadFailedFilesTitle: '上传失败文件',
    localFileNotFound: '无法读取所选文件',
    createDirectory: '新建目录',
    createDirectorySucceeded: '目录创建成功',
    directoryName: '目录名称',
    deleteSucceeded: '删除成功',
    deleteResourceConfirmTemplate: '确认删除“{name}”？',
    deleteLocalOnlyMessage: '仅删除本地已下载文件，不会删除远程文件。',
    download: '下载',
    downloadSucceededTemplate: '已下载到 {path}',
    downloadAlreadyExistsTemplate: '文件已存在：{path}',
    openFailedTemplate: '打开文件失败：{message}',
    serverDownloadDirectory: '每个服务器会保存到该目录下的同名子目录',
    mobileDownloadDirectoryHint: '移动端使用应用可访问的本地目录，上传文件请通过系统“文件”或“相册”选择器。',
    downloadDirectory: '下载目录',
    downloadDirectoryNotSet: '未设置下载目录',
    chooseDirectory: '选择目录',
    downloadDirectoryRequired: '请先在设置中配置下载目录',
    currentPath: '当前路径',
    loadFailed: '加载失败',
    emptyDirectory: '目录为空',
    emptyDirectoryMessage: '当前远程目录没有文件。',
    parentDirectory: '返回上级目录',
    directory: '目录',
    unknownSize: '未知大小',
    transfersPlaceholder: '上传、下载、失败重试和传输历史将在这里管理。',
    offlinePlaceholder: '已下载文件、本地缓存和离线打开记录将在这里管理。',
    transfersEmptyTitle: '暂无传输记录',
    transfersEmptyMessage: '上传和下载任务会显示在这里。',
    clearCompleted: '清空已完成',
    clean: '清理',
    retry: '重试',
    statusRunning: '进行中',
    statusSuccess: '成功',
    statusFailed: '失败',
    uploadLabel: '上传',
    downloadLabel: '下载',
    offlineEmptyTitle: '暂无本地文件',
    offlineEmptyMessage: '当前下载目录下还没有已下载文件。',
    localFilesTitle: '本地文件',
    openFolder: '打开文件夹',
    openFolderFailedTemplate: '打开文件夹失败：{message}',
    language: '语言',
    exportServers: '导出配置',
    importServers: '导入配置',
    exportServerQr: '二维码导出',
    scanServerQr: '扫码导入',
    serverQrHint: '使用另一台设备上的 Xylos 扫描此二维码，即可导入当前服务器配置。',
    scanServerQrHint: '将二维码放入取景框内，识别后会自动导入服务器配置。',
    serverQrExported: '二维码已生成',
    importServerSucceededTemplate: '已导入服务器“{name}”',
    exportSucceededTemplate: '配置已导出到 {path}',
    importSucceededTemplate: '已导入 {count} 个服务器',
    configActionFailedTemplate: '配置操作失败：{message}',
    configPassphrase: '加密口令',
    confirmPassphrase: '确认口令',
    togglePassphraseVisibility: '显示或隐藏口令',
    passphraseRequired: '请输入口令',
    passphraseMismatch: '两次输入的口令不一致',
    unlockSecrets: '解锁密码',
    createPassphrase: '设置主口令',
    changeMasterPassphrase: '修改主口令',
    masterPassphraseChanged: '主口令已更新',
    masterPassphraseUnlocked: '当前会话已解锁',
    masterPassphraseLocked: '当前会话未解锁',
    version: '版本号',
    github: 'GitHub',
    discussions: '讨论',
    serverUrl: '服务地址',
    authType: '认证方式',
    digestAlgorithm: 'Digest 哈希算法',
    username: '用户名',
    password: '密码',
    allowHttp: '允许 HTTP',
    allowHttpDescription: '仅建议在局域网或测试环境开启',
    trustSelfSignedCert: '信任自签名证书',
    trustSelfSignedCertDescription: '仅对当前服务器生效',
    cancel: '取消',
    close: '关闭',
    delete: '删除',
    save: '保存',
    requiredField: '必填',
    duplicateServerAlias: '服务器别名已存在',
    invalidUrl: '请输入有效 URL',
    httpRequiresOptIn: 'HTTP 地址需要开启“允许 HTTP”',
    unsupportedScheme: '仅支持 HTTP 或 HTTPS',
    pendingSuffix: '模块待实现',
    webDavHttpDisabled: 'HTTP 连接已禁用，请在账号设置中允许 HTTP。',
    webDavTimeout: '请求超时，请检查网络或服务器状态。',
    webDavCertificate: 'TLS 证书校验失败，可检查证书或开启信任自签名证书。',
    webDavNetworkTemplate: '网络连接失败：{detail}',
    webDavDigestAlgorithmMismatchTemplate:
        'Digest 算法不匹配，服务端要求 {serverAlgorithm}，当前配置为 {selectedAlgorithm}。',
    webDavDigestUnsupportedQopTemplate: 'Digest 认证不支持 qop={qop}。',
    webDavUnauthorized: '认证失败，请检查用户名、密码或 Token。',
    webDavForbidden: '权限不足，当前账号无法访问该资源。',
    webDavNotFound: '路径不存在，请检查服务地址或默认路径。',
    webDavMethodNotAllowed: '服务端不支持当前 WebDAV 方法。',
    webDavConflict: '路径冲突或父目录不存在。',
    webDavPayloadTooLarge: '文件超过服务端允许的大小。',
    webDavLocked: '资源已被锁定。',
    webDavHttpStatusTemplate: '请求失败，HTTP 状态码：{statusCode}。',
    webDavHttpStatusWithDetailTemplate: '请求失败，HTTP 状态码：{statusCode}。{detail}',
    webDavDirectoryDownloadFailed: '目录下载失败。',
  );

  static const en = AppStrings._(
    serversNav: 'Servers',
    transfersNav: 'Transfers',
    offlineNav: 'Offline',
    settingsNav: 'Settings',
    serversTitle: 'Servers',
    filesTitle: 'Files',
    transfersTitle: 'Transfers',
    offlineTitle: 'Offline Files',
    settingsTitle: 'Settings',
    addServer: 'Add Server',
    editServer: 'Edit Server',
    deleteServer: 'Delete Server',
    deleteServerConfirmTemplate:
        'Delete "{alias}"? This will not delete files on the server.',
    serverAlias: 'Alias',
    noServersTitle: 'No Servers',
    noServersMessage:
        'Add a WebDAV server, then click a server to browse its files.',
    backToServers: 'Back to Servers',
    testConnection: 'Test Connection',
    connectionTestSucceeded: 'Connection test succeeded',
    refresh: 'Refresh',
    sortBy: 'Sort',
    sortByName: 'Sort by Name',
    sortByType: 'Sort by Type',
    sortBySize: 'Sort by Size',
    sortByModified: 'Sort by Time',
    listView: 'List View',
    gridView: 'Grid View',
    uploadFile: 'Upload File',
    uploadFromFiles: 'Choose from Files',
    uploadFromMedia: 'Choose from Photos',
    uploadSucceeded: 'Upload completed',
    uploadBatchSucceededTemplate: 'Uploaded {count} files',
    uploadBatchResultTemplate:
        'Upload finished: {successCount} succeeded, {failedCount} failed',
    uploadBatchFailedFilesTemplate:
        'Upload finished: {successCount} succeeded, {failedCount} failed. Failed files: {fileNames}',
    uploadFailedFilesTitle: 'Failed uploads',
    localFileNotFound: 'Unable to read the selected file',
    createDirectory: 'New Folder',
    createDirectorySucceeded: 'Folder created',
    directoryName: 'Folder name',
    deleteSucceeded: 'Deleted',
    deleteResourceConfirmTemplate: 'Delete "{name}"?',
    deleteLocalOnlyMessage:
        'This only deletes the local downloaded file and will not delete the remote file.',
    download: 'Download',
    downloadSucceededTemplate: 'Downloaded to {path}',
    downloadAlreadyExistsTemplate: 'File already exists: {path}',
    openFailedTemplate: 'Failed to open file: {message}',
    serverDownloadDirectory:
        'Each server is saved in a matching subfolder under this folder',
    mobileDownloadDirectoryHint:
        'On mobile, downloads use an app-accessible local folder. Upload files through the system Files or Photos picker.',
    downloadDirectory: 'Download Folder',
    downloadDirectoryNotSet: 'Download folder is not set',
    chooseDirectory: 'Choose Folder',
    downloadDirectoryRequired: 'Set a download folder in Settings first',
    currentPath: 'Current Path',
    loadFailed: 'Load Failed',
    emptyDirectory: 'Empty Directory',
    emptyDirectoryMessage: 'There are no files in this remote directory.',
    parentDirectory: 'Parent directory',
    directory: 'Directory',
    unknownSize: 'Unknown size',
    transfersPlaceholder:
        'Uploads, downloads, retries, and transfer history will be managed here.',
    offlinePlaceholder:
        'Downloaded files, local cache, and offline open history will be managed here.',
    transfersEmptyTitle: 'No Transfers',
    transfersEmptyMessage: 'Upload and download tasks will appear here.',
    clearCompleted: 'Clear Completed',
    clean: 'Clean',
    retry: 'Retry',
    statusRunning: 'Running',
    statusSuccess: 'Success',
    statusFailed: 'Failed',
    uploadLabel: 'Upload',
    downloadLabel: 'Download',
    offlineEmptyTitle: 'No Local Files',
    offlineEmptyMessage: 'There are no downloaded files in the current folder.',
    localFilesTitle: 'Local Files',
    openFolder: 'Open Folder',
    openFolderFailedTemplate: 'Failed to open folder: {message}',
    language: 'Language',
    exportServers: 'Export Config',
    importServers: 'Import Config',
    exportServerQr: 'Export QR Code',
    scanServerQr: 'Scan QR Code',
    serverQrHint:
        'Scan this QR code with Xylos on another device to import this server configuration.',
    scanServerQrHint:
        'Place the QR code inside the frame. The server configuration will import automatically after detection.',
    serverQrExported: 'QR code generated',
    importServerSucceededTemplate: 'Imported server "{name}"',
    exportSucceededTemplate: 'Configuration exported to {path}',
    importSucceededTemplate: 'Imported {count} servers',
    configActionFailedTemplate: 'Configuration action failed: {message}',
    configPassphrase: 'Passphrase',
    confirmPassphrase: 'Confirm Passphrase',
    togglePassphraseVisibility: 'Show or hide passphrase',
    passphraseRequired: 'Enter a passphrase',
    passphraseMismatch: 'Passphrases do not match',
    unlockSecrets: 'Unlock Secrets',
    createPassphrase: 'Set Master Passphrase',
    changeMasterPassphrase: 'Change Master Passphrase',
    masterPassphraseChanged: 'Master passphrase updated',
    masterPassphraseUnlocked: 'Current session is unlocked',
    masterPassphraseLocked: 'Current session is locked',
    version: 'Version',
    github: 'GitHub',
    discussions: 'Discussions',
    serverUrl: 'Server URL',
    authType: 'Authentication',
    digestAlgorithm: 'Digest Hash Algorithm',
    username: 'Username',
    password: 'Password',
    allowHttp: 'Allow HTTP',
    allowHttpDescription:
        'Recommended only for local networks or test environments',
    trustSelfSignedCert: 'Trust Self-Signed Certificate',
    trustSelfSignedCertDescription: 'Applies only to this server',
    cancel: 'Cancel',
    close: 'Close',
    delete: 'Delete',
    save: 'Save',
    requiredField: 'Required',
    duplicateServerAlias: 'Server alias already exists',
    invalidUrl: 'Enter a valid URL',
    httpRequiresOptIn: 'HTTP URLs require enabling "Allow HTTP"',
    unsupportedScheme: 'Only HTTP and HTTPS are supported',
    pendingSuffix: ' module pending',
    webDavHttpDisabled:
        'HTTP connections are disabled. Enable HTTP in the server settings.',
    webDavTimeout: 'The request timed out. Check the network or server status.',
    webDavCertificate:
        'TLS certificate validation failed. Check the certificate or trust self-signed certificates.',
    webDavNetworkTemplate: 'Network connection failed: {detail}',
    webDavDigestAlgorithmMismatchTemplate:
        'Digest algorithm mismatch. The server requires {serverAlgorithm}, but the current setting is {selectedAlgorithm}.',
    webDavDigestUnsupportedQopTemplate:
        'Digest authentication does not support qop={qop}.',
    webDavUnauthorized:
        'Authentication failed. Check the username, password, or token.',
    webDavForbidden:
        'Permission denied. This account cannot access the resource.',
    webDavNotFound: 'Path not found. Check the server URL or default path.',
    webDavMethodNotAllowed:
        'The server does not support the current WebDAV method.',
    webDavConflict: 'Path conflict or parent folder does not exist.',
    webDavPayloadTooLarge: 'The file exceeds the size allowed by the server.',
    webDavLocked: 'The resource is locked.',
    webDavHttpStatusTemplate: 'Request failed with HTTP status {statusCode}.',
    webDavHttpStatusWithDetailTemplate:
        'Request failed with HTTP status {statusCode}. {detail}',
    webDavDirectoryDownloadFailed: 'Folder download failed.',
  );
}

bool _containsHanCharacters(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

String _formatSize(int? bytes, AppStrings strings) {
  if (bytes == null) {
    return strings.unknownSize;
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

String _lastPathSegment(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/') && normalized.length > 1
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final segments = trimmed.split('/').where((item) => item.isNotEmpty).toList();
  if (segments.isEmpty) {
    return trimmed.isEmpty ? '/' : trimmed;
  }
  return segments.last;
}

String _transferDirectionLabel(
  AppStrings strings,
  TransferDirection direction,
) {
  switch (direction) {
    case TransferDirection.upload:
      return strings.uploadLabel;
    case TransferDirection.download:
      return strings.downloadLabel;
  }
}

String _transferStatusLabel(AppStrings strings, TransferStatus status) {
  switch (status) {
    case TransferStatus.running:
      return strings.statusRunning;
    case TransferStatus.success:
      return strings.statusSuccess;
    case TransferStatus.failed:
      return strings.statusFailed;
  }
}

IconData _transferIcon(TransferDirection direction) {
  switch (direction) {
    case TransferDirection.upload:
      return Icons.upload_file;
    case TransferDirection.download:
      return Icons.download;
  }
}

String _joinRemotePath(String directory, String name) {
  final cleanName = name.trim().replaceAll(RegExp(r'^/+'), '');
  if (directory == '/' || directory.trim().isEmpty) {
    return '/$cleanName';
  }
  final cleanDirectory = directory.endsWith('/') ? directory : '$directory/';
  return '$cleanDirectory$cleanName';
}

String _joinLocalPath(String directory, String name) {
  final cleanName = _safeLocalFileName(name);
  if (directory.endsWith(Platform.pathSeparator)) {
    return '$directory$cleanName';
  }
  return '$directory${Platform.pathSeparator}$cleanName';
}

String _normalizeLocalPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return Directory(trimmed).absolute.path;
}

String _parentDirectoryPath(String path) {
  final separator = Platform.pathSeparator;
  final trimmed = path.endsWith(separator) && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final index = trimmed.lastIndexOf(separator);
  if (index <= 0) {
    return trimmed;
  }
  return trimmed.substring(0, index);
}

String _safeLocalFileName(String name) {
  final trimmed = name.trim();
  final fallback = trimmed.isEmpty ? 'download' : trimmed;
  return fallback.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _serverDownloadDirectory(String rootDirectory, WebDavAccount server) {
  return _joinLocalPath(rootDirectory, server.name);
}

String _localPathForRemoteResource(
  String rootDirectory,
  WebDavAccount server,
  WebDavResource resource,
) {
  final segments = resource.path
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  var localPath = _serverDownloadDirectory(rootDirectory, server);
  if (segments.isEmpty) {
    return _joinLocalPath(localPath, resource.name);
  }
  for (final segment in segments) {
    localPath = _joinLocalPath(localPath, segment);
  }
  return localPath;
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class ServersPage extends StatelessWidget {
  const ServersPage({
    super.key,
    required this.servers,
    required this.strings,
    required this.onOpen,
    required this.onHydrateServer,
    required this.onExportServerQr,
    required this.onImportServerFromQr,
    required this.onChanged,
  });

  final List<WebDavAccount> servers;
  final AppStrings strings;
  final Future<void> Function(WebDavAccount server) onOpen;
  final Future<WebDavAccount> Function(WebDavAccount server) onHydrateServer;
  final Future<String> Function(WebDavAccount server) onExportServerQr;
  final Future<String?> Function() onImportServerFromQr;
  final ValueChanged<List<WebDavAccount>> onChanged;

  @override
  Widget build(BuildContext context) {
    final supportsQrImport = Platform.isAndroid || Platform.isIOS;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: strings.serversTitle,
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (supportsQrImport)
                    OutlinedButton.icon(
                      onPressed: () => _runImportServerQr(context),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(strings.scanServerQr),
                    ),
                  FilledButton.icon(
                    onPressed: () => _openEditor(context),
                    icon: const Icon(Icons.add),
                    label: Text(strings.addServer),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: servers.isEmpty
                  ? EmptyState(
                      icon: Icons.dns_outlined,
                      title: strings.noServersTitle,
                      message: strings.noServersMessage,
                      action: FilledButton.icon(
                        onPressed: () => _openEditor(context),
                        icon: const Icon(Icons.add),
                        label: Text(strings.addServer),
                      ),
                    )
                  : ListView.separated(
                      itemCount: servers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final server = servers[index];
                        return ServerTile(
                          server: server,
                          strings: strings,
                          onOpen: () => onOpen(server),
                          onEdit: () => _openEditor(context, server: server),
                          onDelete: () => _deleteServer(context, server),
                          onExportQr: () => _runExportServerQr(context, server),
                          onHydrateServer: onHydrateServer,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    WebDavAccount? server,
  }) async {
    final hydratedServer =
        server == null ? null : await onHydrateServer(server);
    if (!context.mounted) {
      return;
    }
    final result = await showDialog<WebDavAccount>(
      context: context,
      builder: (context) => ServerEditorDialog(
        server: hydratedServer,
        servers: servers,
        strings: strings,
      ),
    );
    if (result == null) {
      return;
    }

    final nextServers = [...servers];
    final index = nextServers.indexWhere((item) => item.id == result.id);
    if (index == -1) {
      nextServers.add(result);
    } else {
      nextServers[index] = result;
    }
    onChanged(nextServers);
  }

  Future<void> _deleteServer(
    BuildContext context,
    WebDavAccount server,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.deleteServer),
          content: Text(strings.deleteServerConfirm(server.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }
    onChanged(servers.where((item) => item.id != server.id).toList());
  }

  Future<void> _runExportServerQr(
    BuildContext context,
    WebDavAccount server,
  ) async {
    try {
      final message = await onExportServerQr(server);
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, message);
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, strings.configActionFailed(error.message));
    }
  }

  Future<void> _runImportServerQr(BuildContext context) async {
    try {
      final message = await onImportServerFromQr();
      if (message == null || !context.mounted) {
        return;
      }
      _showSnackBar(context, message);
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, strings.configActionFailed(error.message));
    }
  }
}

class ServerTile extends StatefulWidget {
  const ServerTile({
    super.key,
    required this.server,
    required this.strings,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onExportQr,
    required this.onHydrateServer,
  });

  final WebDavAccount server;
  final AppStrings strings;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExportQr;
  final Future<WebDavAccount> Function(WebDavAccount server) onHydrateServer;

  @override
  State<ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<ServerTile> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final strings = widget.strings;
    final isCompactLayout = MediaQuery.sizeOf(context).width < 640;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.dns),
        title: Text(server.name),
        subtitle: isCompactLayout ? null : Text(server.baseUrl),
        onTap: widget.onOpen,
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: strings.testConnection,
              onPressed: _testing ? null : _testServer,
              icon: _testing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
            ),
            PopupMenuButton<_ServerTileAction>(
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                switch (action) {
                  case _ServerTileAction.exportQr:
                    widget.onExportQr();
                  case _ServerTileAction.edit:
                    widget.onEdit();
                  case _ServerTileAction.delete:
                    widget.onDelete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ServerTileAction.exportQr,
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(strings.exportServerQr),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _ServerTileAction.edit,
                  child: ListTile(
                    leading: const Icon(Icons.edit),
                    title: Text(strings.editServer),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _ServerTileAction.delete,
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(strings.deleteServer),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testServer() async {
    setState(() {
      _testing = true;
    });

    try {
      final hydratedServer = await widget.onHydrateServer(widget.server);
      AppLogger.debug(
        'UI',
        'test server alias=${widget.server.name} baseUrl=${widget.server.baseUrl}',
      );
      await WebDavClient(hydratedServer).testConnection();
      if (!mounted) {
        return;
      }
      _showSnackBar(context, widget.strings.connectionTestSucceeded);
    } on WebDavException catch (error) {
      AppLogger.error(
          'UI', 'test server failed alias=${widget.server.name}', error);
      if (!mounted) {
        return;
      }
      _showSnackBar(context, widget.strings.webDavError(error));
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }
}

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({
    super.key,
    required this.server,
    required this.strings,
    required this.downloadDirectory,
    required this.onDownloadDirectoryChanged,
    required this.onTransferChanged,
    required this.onBack,
  });

  final WebDavAccount server;
  final AppStrings strings;
  final String downloadDirectory;
  final ValueChanged<String> onDownloadDirectoryChanged;
  final Future<void> Function(TransferRecord) onTransferChanged;
  final VoidCallback onBack;

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  final ImagePicker _imagePicker = ImagePicker();
  var _path = '/';
  var _resources = <WebDavResource>[];
  var _loading = false;
  var _mutating = false;
  var _sortField = FileSortField.name;
  var _sortAscending = true;
  var _viewMode = FileViewMode.list;
  String? _error;

  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _path = '/';
    _loadPath();
  }

  @override
  void didUpdateWidget(covariant FileBrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.id != widget.server.id) {
      _path = '/';
      _resources = [];
      _error = null;
      _loadPath();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '${widget.server.name} · ${strings.filesTitle}',
              action: Wrap(
                spacing: 8,
                children: [
                  PopupMenuButton<FileSortField>(
                    tooltip: strings.sortBy,
                    icon: const Icon(Icons.sort),
                    initialValue: _sortField,
                    onSelected: _changeSort,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: FileSortField.name,
                        child: Text(strings.sortByName),
                      ),
                      PopupMenuItem(
                        value: FileSortField.type,
                        child: Text(strings.sortByType),
                      ),
                      PopupMenuItem(
                        value: FileSortField.size,
                        child: Text(strings.sortBySize),
                      ),
                      PopupMenuItem(
                        value: FileSortField.modified,
                        child: Text(strings.sortByModified),
                      ),
                    ],
                  ),
                  IconButton.filledTonal(
                    tooltip: _viewMode == FileViewMode.list
                        ? strings.gridView
                        : strings.listView,
                    onPressed: _toggleViewMode,
                    icon: Icon(
                      _viewMode == FileViewMode.list
                          ? Icons.grid_view
                          : Icons.view_list,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: strings.uploadFile,
                    onPressed: _mutating ? null : _uploadFile,
                    icon: const Icon(Icons.upload_file),
                  ),
                  IconButton.filledTonal(
                    tooltip: strings.createDirectory,
                    onPressed: _mutating ? null : _createDirectory,
                    icon: const Icon(Icons.create_new_folder),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: strings.parentDirectory,
                  onPressed: _navigateBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: strings.refresh,
                  onPressed: _loading ? null : _loadPath,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey(_path),
                    initialValue: _path,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                    onFieldSubmitted: (value) {
                      _path = value.trim().isEmpty ? '/' : value.trim();
                      _loadPath();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildFileList()),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    final strings = widget.strings;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: strings.loadFailed,
        message: _error!,
      );
    }

    if (_resources.isEmpty) {
      return EmptyState(
        icon: Icons.folder_open,
        title: strings.emptyDirectory,
        message: strings.emptyDirectoryMessage,
      );
    }

    if (_viewMode == FileViewMode.grid) {
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.88,
        ),
        itemCount: _resources.length,
        itemBuilder: (context, index) {
          final resource = _resources[index];
          return FileGridTile(
            resource: resource,
            strings: strings,
            imageSource: _imageSource(resource),
            mutating: _mutating,
            onOpen: () => _openResource(resource),
            onDownload: () => _download(resource),
            onDelete: () => _deleteResource(resource),
          );
        },
      );
    }

    return ListView.separated(
      itemCount: _resources.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final resource = _resources[index];
        return ListTile(
          leading: FileResourceLeading(
            resource: resource,
            imageSource: _imageSource(resource),
          ),
          title: Text(resource.name),
          subtitle: Text(_resourceSubtitle(resource)),
          trailing: FileActionsMenu(
            strings: strings,
            mutating: _mutating,
            onDownload: () => _download(resource),
            onDelete: () => _deleteResource(resource),
          ),
          onTap: () => _openResource(resource),
        );
      },
    );
  }

  Future<void> _loadPath() async {
    AppLogger.debug(
      'UI',
      'load path=$_path alias=${widget.server.name} baseUrl=${widget.server.baseUrl}',
    );
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resources = await WebDavClient(widget.server).list(_path);
      if (!mounted) {
        return;
      }
      AppLogger.debug('UI', 'loaded path=$_path resources=${resources.length}');
      setState(() {
        _resources = _sortedResources(resources);
      });
    } on WebDavException catch (error) {
      AppLogger.error('UI', 'load path failed path=$_path', error);
      if (!mounted) {
        return;
      }
      setState(() {
        _resources = [];
        _error = widget.strings.webDavError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _changeSort(FileSortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
      _resources = _sortedResources(_resources);
    });
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == FileViewMode.list
          ? FileViewMode.grid
          : FileViewMode.list;
    });
  }

  List<WebDavResource> _sortedResources(List<WebDavResource> resources) {
    final sorted = [...resources];
    sorted.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      final result = switch (_sortField) {
        FileSortField.name =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        FileSortField.type => _resourceType(a).compareTo(_resourceType(b)),
        FileSortField.size => (a.size ?? -1).compareTo(b.size ?? -1),
        FileSortField.modified =>
          (a.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            b.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
      };

      if (result == 0) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? result : -result;
    });
    return sorted;
  }

  String _resourceType(WebDavResource resource) {
    if (resource.isDirectory) {
      return 'directory';
    }
    final contentType = resource.contentType;
    if (contentType != null && contentType.isNotEmpty) {
      return contentType.toLowerCase();
    }
    final dot = resource.name.lastIndexOf('.');
    if (dot == -1 || dot == resource.name.length - 1) {
      return '';
    }
    return resource.name.substring(dot + 1).toLowerCase();
  }

  RemoteImageSource? _imageSource(WebDavResource resource) {
    if (!_isImageResource(resource)) {
      return null;
    }
    final client = WebDavClient(widget.server);
    return RemoteImageSource(
      loader: () async {
        final bytes = await client.downloadBytes(resource.path);
        return Uint8List.fromList(bytes);
      },
    );
  }

  Future<void> _uploadFile() async {
    final pickedUploads = _isMobilePlatform
        ? await _pickUploadFilesForMobile()
        : await _pickFileUploads();
    await _uploadPickedFiles(pickedUploads);
  }

  Future<void> _uploadPickedFiles(List<_PickedUploadFile> pickedUploads) async {
    if (pickedUploads.isEmpty) {
      return;
    }
    final isBatch = pickedUploads.length > 1;
    var successCount = 0;
    var failedCount = 0;
    final failedUploads = <_PickedUploadFile>[];

    for (final pickedUpload in pickedUploads) {
      final remotePath = _joinRemotePath(_path, pickedUpload.name);
      final localPath = pickedUpload.path ?? pickedUpload.name;
      final transfer = _createTransferRecord(
        direction: TransferDirection.upload,
        remotePath: remotePath,
        localPath: localPath,
      );

      final result = await _runMutation(
        transfer: transfer,
        action: () async {
          final path = pickedUpload.path;
          if (path != null) {
            await WebDavClient(widget.server)
                .uploadFile(remotePath, File(path));
            return;
          }

          final bytes = pickedUpload.bytes;
          if (bytes == null) {
            throw FileSystemException(widget.strings.localFileNotFound);
          }
          await WebDavClient(widget.server).uploadBytes(remotePath, bytes);
        },
        successMessage: widget.strings.uploadSucceeded,
        showSuccessSnackBar: !isBatch,
      );
      if (result.succeeded) {
        successCount += 1;
      } else {
        failedCount += 1;
        failedUploads.add(pickedUpload);
      }
    }
    if (mounted && isBatch) {
      final message = failedCount == 0
          ? widget.strings.uploadBatchSucceeded(successCount)
          : _uploadBatchFailureMessage(
              successCount,
              failedCount,
              failedUploads.map((item) => item.name).toList(),
            );
      _showSnackBar(context, message);
      if (failedCount > 0) {
        final shouldRetry = await _showUploadFailedFilesDialog(
          failedUploads.map((item) => item.name).toList(),
        );
        if (shouldRetry == true && mounted) {
          await _uploadPickedFiles(failedUploads);
        }
      }
    }
  }

  String _uploadBatchFailureMessage(
    int successCount,
    int failedCount,
    List<String> failedNames,
  ) {
    final previewNames = failedNames.take(3).join(', ');
    final hasMore = failedNames.length > 3;
    final fileNames = hasMore ? '$previewNames...' : previewNames;
    return widget.strings.uploadBatchFailedFiles(
      successCount,
      failedCount,
      fileNames,
    );
  }

  Future<bool?> _showUploadFailedFilesDialog(List<String> failedNames) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(widget.strings.uploadFailedFilesTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(failedNames.join('\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(widget.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(widget.strings.retry),
            ),
          ],
        );
      },
    );
  }

  Future<List<_PickedUploadFile>> _pickUploadFilesForMobile() async {
    final source = await showModalBottomSheet<_UploadSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(widget.strings.uploadFromFiles),
                onTap: () => Navigator.of(context).pop(_UploadSource.files),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(widget.strings.uploadFromMedia),
                onTap: () => Navigator.of(context).pop(_UploadSource.media),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) {
      return const [];
    }
    return switch (source) {
      _UploadSource.files => _pickFileUploads(),
      _UploadSource.media => _pickMediaUploads(),
    };
  }

  Future<List<_PickedUploadFile>> _pickFileUploads() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    final pickedFiles = result?.files ?? const [];
    if (pickedFiles.isEmpty) {
      return const [];
    }
    return pickedFiles
        .map(
          (pickedFile) => _PickedUploadFile(
            name: pickedFile.name,
            path: pickedFile.path,
            bytes: pickedFile.bytes,
          ),
        )
        .toList();
  }

  Future<List<_PickedUploadFile>> _pickMediaUploads() async {
    final pickedFiles = await _imagePicker.pickMultiImage();
    return pickedFiles
        .map(
          (pickedFile) => _PickedUploadFile(
            name: pickedFile.name,
            path: pickedFile.path,
          ),
        )
        .toList();
  }

  Future<void> _createDirectory() async {
    final name = await _promptText(
      title: widget.strings.createDirectory,
      label: widget.strings.directoryName,
    );
    if (name == null || name.trim().isEmpty) {
      return;
    }

    final remotePath = _joinRemotePath(_path, name.trim());
    await _runMutation(
      action: () => WebDavClient(widget.server).createDirectory(remotePath),
      successMessage: widget.strings.createDirectorySucceeded,
    );
  }

  Future<void> _deleteResource(WebDavResource resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(widget.strings.delete),
          content: Text(widget.strings.deleteResourceConfirm(resource.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(widget.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(widget.strings.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    await _runMutation(
      action: () => WebDavClient(widget.server).delete(resource.path),
      successMessage: widget.strings.deleteSucceeded,
    );
  }

  Future<void> _download(WebDavResource resource) async {
    if (resource.isDirectory) {
      final result = await _downloadDirectory(resource);
      if (result == null || !mounted) {
        return;
      }
      _showSnackBar(
        context,
        result.reused
            ? widget.strings.downloadAlreadyExists(result.file.path)
            : widget.strings.downloadSucceeded(result.file.path),
      );
      return;
    }

    final result = await _downloadResource(resource);
    if (result == null || !mounted) {
      return;
    }
    _showSnackBar(
      context,
      result.reused
          ? widget.strings.downloadAlreadyExists(result.file.path)
          : widget.strings.downloadSucceeded(result.file.path),
    );
  }

  Future<void> _openResource(WebDavResource resource) async {
    if (resource.isDirectory) {
      _openDirectory(resource.path);
      return;
    }

    final result = await _downloadResource(resource);
    if (result == null || !mounted) {
      return;
    }

    await _openLocalFile(result.file);
  }

  Future<void> _openLocalFile(File file) async {
    AppLogger.debug('UI', 'open local file path=${file.path}');
    final result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done) {
      return;
    }

    AppLogger.error(
      'UI',
      'open local file failed path=${file.path} type=${result.type.name}',
      result.message,
    );
    if (mounted) {
      _showSnackBar(context, widget.strings.openFailed(result.message));
    }
  }

  Future<DownloadResult?> _downloadResource(WebDavResource resource) async {
    final directoryPath = await _resolveDownloadDirectoryPath();
    if (directoryPath.isEmpty) {
      if (mounted) {
        _showSnackBar(context, widget.strings.downloadDirectoryRequired);
      }
      return null;
    }
    return _downloadToDirectory(resource, directoryPath);
  }

  Future<DownloadResult?> _downloadDirectory(WebDavResource resource) async {
    final directoryPath = await _resolveDownloadDirectoryPath();
    if (directoryPath.isEmpty) {
      if (mounted) {
        _showSnackBar(context, widget.strings.downloadDirectoryRequired);
      }
      return null;
    }
    return _downloadDirectoryToRoot(resource, directoryPath);
  }

  Future<String> _resolveDownloadDirectoryPath() async {
    final directoryPath = widget.downloadDirectory.trim();
    if (directoryPath.isNotEmpty) {
      return directoryPath;
    }
    if (_isMobilePlatform) {
      final fallback = await AccountStore.resolveDefaultDownloadDirectory();
      widget.onDownloadDirectoryChanged(fallback);
      return fallback;
    }
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: widget.strings.chooseDirectory,
    );
    if (selected == null || selected.trim().isEmpty) {
      return '';
    }
    widget.onDownloadDirectoryChanged(selected);
    return selected;
  }

  Future<DownloadResult?> _downloadDirectoryToRoot(
    WebDavResource resource,
    String rootDirectory,
  ) async {
    final transfer = _createTransferRecord(
      direction: TransferDirection.download,
      remotePath: resource.path,
      localPath:
          _localPathForRemoteResource(rootDirectory, widget.server, resource),
    );
    await widget.onTransferChanged(transfer);

    setState(() {
      _mutating = true;
      _error = null;
    });

    try {
      final localDirectory = Directory(
        _localPathForRemoteResource(rootDirectory, widget.server, resource),
      );
      if (!await localDirectory.exists()) {
        await localDirectory.create(recursive: true);
      }
      await _downloadDirectoryChildren(resource.path, rootDirectory);
      await widget.onTransferChanged(
        transfer.copyWith(
          status: TransferStatus.success,
          finishedAt: DateTime.now(),
        ),
      );
      return DownloadResult(file: File(localDirectory.path), reused: false);
    } on WebDavException catch (error) {
      final message = widget.strings.webDavError(error);
      await widget.onTransferChanged(
        transfer.copyWith(
          status: TransferStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: message,
        ),
      );
      if (mounted) {
        _showSnackBar(context, message);
      }
      return null;
    } on FileSystemException catch (error) {
      await widget.onTransferChanged(
        transfer.copyWith(
          status: TransferStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: error.message,
        ),
      );
      if (mounted) {
        _showSnackBar(context, error.message);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _mutating = false;
        });
      }
    }
  }

  Future<void> _downloadDirectoryChildren(
    String remotePath,
    String rootDirectory,
  ) async {
    final children = await WebDavClient(widget.server).list(remotePath);
    for (final child in children) {
      if (child.isDirectory) {
        final localDirectory = Directory(
          _localPathForRemoteResource(
            rootDirectory,
            widget.server,
            child,
          ),
        );
        if (!await localDirectory.exists()) {
          await localDirectory.create(recursive: true);
        }
        await _downloadDirectoryChildren(child.path, rootDirectory);
      } else {
        final result = await _downloadToDirectory(
          child,
          rootDirectory,
          allowDirectoryRetry: false,
        );
        if (result == null) {
          throw const WebDavException(
            WebDavFailureKind.directoryDownloadFailed,
          );
        }
      }
    }
  }

  Future<DownloadResult?> _downloadToDirectory(
    WebDavResource resource,
    String rootDirectory, {
    bool allowDirectoryRetry = true,
  }) async {
    final localPath = _localPathForRemoteResource(
      rootDirectory,
      widget.server,
      resource,
    );
    final transfer = _createTransferRecord(
      direction: TransferDirection.download,
      remotePath: resource.path,
      localPath: localPath,
    );
    await widget.onTransferChanged(transfer);

    setState(() {
      _mutating = true;
      _error = null;
    });

    try {
      final localFile = File(localPath);
      final parentDirectory = localFile.parent;
      if (!await parentDirectory.exists()) {
        await parentDirectory.create(recursive: true);
      }

      if (await localFile.exists() &&
          await _matchesRemoteSize(localFile, resource)) {
        AppLogger.debug(
          'UI',
          'reuse local file path=${localFile.path} remotePath=${resource.path}',
        );
        await widget.onTransferChanged(
          transfer.copyWith(
            status: TransferStatus.success,
            finishedAt: DateTime.now(),
          ),
        );
        return DownloadResult(file: localFile, reused: true);
      }

      AppLogger.debug(
        'UI',
        'download resource remotePath=${resource.path} localPath=${localFile.path}',
      );
      final bytes = await WebDavClient(widget.server).downloadBytes(
        resource.path,
      );
      await localFile.writeAsBytes(bytes, flush: true);
      await widget.onTransferChanged(
        transfer.copyWith(
          status: TransferStatus.success,
          finishedAt: DateTime.now(),
        ),
      );
      return DownloadResult(file: localFile, reused: false);
    } on WebDavException catch (error) {
      AppLogger.error('UI', 'download failed path=${resource.path}', error);
      final message = widget.strings.webDavError(error);
      await widget.onTransferChanged(
        transfer.copyWith(
          status: TransferStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: message,
        ),
      );
      if (mounted) {
        _showSnackBar(context, message);
      }
      return null;
    } on FileSystemException catch (error, stackTrace) {
      AppLogger.error(
        'UI',
        'local download write failed path=${resource.path}',
        error,
        stackTrace,
      );
      await widget.onTransferChanged(
        transfer.copyWith(
          status: TransferStatus.failed,
          finishedAt: DateTime.now(),
          errorMessage: error.message,
        ),
      );
      if (mounted &&
          !_isMobilePlatform &&
          allowDirectoryRetry &&
          _isPermissionDenied(error)) {
        setState(() {
          _mutating = false;
        });
        final selected = await FilePicker.platform.getDirectoryPath(
          dialogTitle: widget.strings.chooseDirectory,
        );
        if (selected != null && selected.trim().isNotEmpty) {
          widget.onDownloadDirectoryChanged(selected);
          return _downloadToDirectory(
            resource,
            selected,
            allowDirectoryRetry: false,
          );
        }
      }
      if (mounted) {
        _showSnackBar(context, error.message);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _mutating = false;
        });
      }
    }
  }

  Future<bool> _matchesRemoteSize(File file, WebDavResource resource) async {
    final remoteSize = resource.size;
    if (remoteSize == null) {
      return true;
    }
    return await file.length() == remoteSize;
  }

  bool _isPermissionDenied(FileSystemException error) {
    final errorCode = error.osError?.errorCode;
    if (errorCode == 1 || errorCode == 13) {
      return true;
    }
    final message = error.message.toLowerCase();
    return message.contains('operation not permitted') ||
        message.contains('permission denied');
  }

  Future<_MutationResult> _runMutation({
    TransferRecord? transfer,
    required Future<void> Function() action,
    required String successMessage,
    bool showSuccessSnackBar = true,
  }) async {
    if (transfer != null) {
      await widget.onTransferChanged(transfer);
    }
    setState(() {
      _mutating = true;
      _error = null;
    });

    try {
      await action();
      if (transfer != null) {
        await widget.onTransferChanged(
          transfer.copyWith(
            status: TransferStatus.success,
            finishedAt: DateTime.now(),
          ),
        );
      }
      if (!mounted) {
        return const _MutationResult.success();
      }
      if (showSuccessSnackBar) {
        _showSnackBar(context, successMessage);
      }
      await _loadPath();
      return const _MutationResult.success();
    } on WebDavException catch (error) {
      AppLogger.error('UI', 'file operation failed path=$_path', error);
      final message = widget.strings.webDavError(error);
      if (transfer != null) {
        await widget.onTransferChanged(
          transfer.copyWith(
            status: TransferStatus.failed,
            finishedAt: DateTime.now(),
            errorMessage: message,
          ),
        );
      }
      if (!mounted) {
        return _MutationResult.failure(message);
      }
      _showSnackBar(context, message);
      return _MutationResult.failure(message);
    } on FileSystemException catch (error) {
      AppLogger.error('UI', 'local file operation failed', error);
      if (transfer != null) {
        await widget.onTransferChanged(
          transfer.copyWith(
            status: TransferStatus.failed,
            finishedAt: DateTime.now(),
            errorMessage: error.message,
          ),
        );
      }
      if (!mounted) {
        return _MutationResult.failure(error.message);
      }
      _showSnackBar(context, error.message);
      return _MutationResult.failure(error.message);
    } finally {
      if (mounted) {
        setState(() {
          _mutating = false;
        });
      }
    }
  }

  Future<String?> _promptText({
    required String title,
    required String label,
  }) async {
    var input = '';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            decoration: InputDecoration(labelText: label),
            autofocus: true,
            onChanged: (value) {
              input = value;
            },
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(input),
              child: Text(widget.strings.save),
            ),
          ],
        );
      },
    );
  }

  void _openDirectory(String path) {
    AppLogger.debug('UI', 'open directory path=$path');
    setState(() {
      _path = path;
    });
    _loadPath();
  }

  void _navigateBack() {
    if (_path == '/') {
      AppLogger.debug('UI', 'back to servers from root');
      widget.onBack();
      return;
    }
    _goParent();
  }

  void _goParent() {
    final trimmed = _path.endsWith('/') && _path.length > 1
        ? _path.substring(0, _path.length - 1)
        : _path;
    final slash = trimmed.lastIndexOf('/');
    setState(() {
      _path = slash <= 0 ? '/' : trimmed.substring(0, slash + 1);
    });
    AppLogger.debug('UI', 'go parent path=$_path');
    _loadPath();
  }

  String _resourceSubtitle(WebDavResource resource) {
    final strings = widget.strings;
    final parts = <String>[];
    parts.add(resource.isDirectory
        ? strings.directory
        : _formatSize(resource.size, strings));
    if (resource.lastModified != null) {
      parts.add(resource.lastModified!.toLocal().toString().split('.').first);
    }
    return parts.join(' · ');
  }

  TransferRecord _createTransferRecord({
    required TransferDirection direction,
    required String remotePath,
    required String localPath,
  }) {
    final now = DateTime.now();
    return TransferRecord(
      id: 'transfer-${now.microsecondsSinceEpoch}',
      serverName: widget.server.name,
      remotePath: remotePath,
      localPath: localPath,
      direction: direction,
      status: TransferStatus.running,
      createdAt: now,
    );
  }
}

class FileResourceLeading extends StatelessWidget {
  const FileResourceLeading({
    super.key,
    required this.resource,
    required this.imageSource,
  });

  final WebDavResource resource;
  final RemoteImageSource? imageSource;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FileResourcePreview(
          resource: resource,
          imageSource: imageSource,
          iconSize: 24,
        ),
      ),
    );
  }
}

class FileGridTile extends StatelessWidget {
  const FileGridTile({
    super.key,
    required this.resource,
    required this.strings,
    required this.imageSource,
    required this.mutating,
    required this.onOpen,
    required this.onDownload,
    required this.onDelete,
  });

  final WebDavResource resource;
  final AppStrings strings;
  final RemoteImageSource? imageSource;
  final bool mutating;
  final VoidCallback? onOpen;
  final VoidCallback? onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FileResourcePreview(
                resource: resource,
                imageSource: imageSource,
                iconSize: 40,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          resource.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          resource.isDirectory
                              ? strings.directory
                              : _formatSize(resource.size, strings),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FileActionsMenu(
                    strings: strings,
                    mutating: mutating,
                    onDownload: onDownload,
                    onDelete: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FileActionsMenu extends StatelessWidget {
  const FileActionsMenu({
    super.key,
    required this.strings,
    required this.mutating,
    required this.onDownload,
    required this.onDelete,
  });

  final AppStrings strings;
  final bool mutating;
  final VoidCallback? onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FileAction>(
      tooltip: strings.delete,
      enabled: !mutating,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _FileAction.download:
            onDownload?.call();
          case _FileAction.delete:
            onDelete();
        }
      },
      itemBuilder: (context) => [
        if (onDownload != null)
          PopupMenuItem(
            value: _FileAction.download,
            child: ListTile(
              leading: const Icon(Icons.download),
              title: Text(strings.download),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: _FileAction.delete,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(strings.delete),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

enum _FileAction {
  download,
  delete;
}

enum _UploadSource {
  files,
  media;
}

class _PickedUploadFile {
  const _PickedUploadFile({
    required this.name,
    this.path,
    this.bytes,
  });

  final String name;
  final String? path;
  final Uint8List? bytes;
}

class _MutationResult {
  const _MutationResult._({
    required this.succeeded,
    this.message,
  });

  const _MutationResult.success() : this._(succeeded: true);

  const _MutationResult.failure(String message)
      : this._(succeeded: false, message: message);

  final bool succeeded;
  final String? message;
}

class FileResourcePreview extends StatelessWidget {
  const FileResourcePreview({
    super.key,
    required this.resource,
    required this.imageSource,
    required this.iconSize,
  });

  final WebDavResource resource;
  final RemoteImageSource? imageSource;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final source = imageSource;
    if (source == null) {
      return ResourceIconPlaceholder(resource: resource, iconSize: iconSize);
    }

    final loader = source.loader;
    if (loader != null) {
      return FutureBuilder<Uint8List>(
        future: loader(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ResourceIconPlaceholder(
              resource: resource,
              iconSize: iconSize,
              loading: true,
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            AppLogger.error(
              'UI',
              'online image preview failed path=${resource.path}',
              snapshot.error,
              snapshot.stackTrace,
            );
            return ResourceIconPlaceholder(
              resource: resource,
              iconSize: iconSize,
            );
          }
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        },
      );
    }

    return Image.network(
      source.uri.toString(),
      headers: source.headers,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return ResourceIconPlaceholder(
          resource: resource,
          iconSize: iconSize,
          loading: true,
        );
      },
      errorBuilder: (context, error, stackTrace) {
        AppLogger.error(
          'UI',
          'online image preview failed path=${resource.path}',
          error,
          stackTrace,
        );
        return ResourceIconPlaceholder(resource: resource, iconSize: iconSize);
      },
    );
  }
}

class RemoteImageSource {
  const RemoteImageSource({
    this.uri,
    this.headers = const {},
    this.loader,
  });

  final Uri? uri;
  final Map<String, String> headers;
  final Future<Uint8List> Function()? loader;
}

class DownloadResult {
  const DownloadResult({
    required this.file,
    required this.reused,
  });

  final File file;
  final bool reused;
}

class ResourceIconPlaceholder extends StatelessWidget {
  const ResourceIconPlaceholder({
    super.key,
    required this.resource,
    required this.iconSize,
    this.loading = false,
  });

  final WebDavResource resource;
  final double iconSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = resource.isDirectory
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = resource.isDirectory
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: loading
            ? SizedBox.square(
                dimension: iconSize * 0.7,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _resourceIcon(resource),
                size: iconSize,
                color: foregroundColor,
              ),
      ),
    );
  }
}

bool _isImageResource(WebDavResource resource) {
  if (resource.isDirectory) {
    return false;
  }

  final contentType = resource.contentType?.toLowerCase().split(';').first;
  if (contentType != null && contentType.trim().startsWith('image/')) {
    return true;
  }

  final dot = resource.name.lastIndexOf('.');
  if (dot == -1 || dot == resource.name.length - 1) {
    return false;
  }
  final extension = resource.name.substring(dot + 1).toLowerCase();
  return const {
    'apng',
    'avif',
    'bmp',
    'gif',
    'jpeg',
    'jpg',
    'png',
    'webp',
  }.contains(extension);
}

bool _isLocalImagePath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1 || dot == path.length - 1) {
    return false;
  }
  final extension = path.substring(dot + 1).toLowerCase();
  return const {
    'apng',
    'avif',
    'bmp',
    'gif',
    'jpeg',
    'jpg',
    'png',
    'webp',
  }.contains(extension);
}

bool _isLocalVideoPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1 || dot == path.length - 1) {
    return false;
  }
  final extension = path.substring(dot + 1).toLowerCase();
  return _isVideoExtension(extension);
}

bool _isVideoResource(WebDavResource resource) {
  if (resource.isDirectory) {
    return false;
  }

  final contentType = resource.contentType?.toLowerCase().split(';').first;
  if (contentType != null && contentType.trim().startsWith('video/')) {
    return true;
  }

  final dot = resource.name.lastIndexOf('.');
  if (dot == -1 || dot == resource.name.length - 1) {
    return false;
  }
  final extension = resource.name.substring(dot + 1).toLowerCase();
  return _isVideoExtension(extension);
}

bool _isVideoExtension(String extension) {
  return const {
    'avi',
    'm4v',
    'mkv',
    'mov',
    'mp4',
    'mpeg',
    'mpg',
    'webm',
  }.contains(extension);
}

IconData _resourceIcon(WebDavResource resource) {
  if (resource.isDirectory) {
    return Icons.folder;
  }
  if (_isImageResource(resource)) {
    return Icons.image_outlined;
  }
  if (_isVideoResource(resource)) {
    return Icons.videocam_outlined;
  }
  return Icons.insert_drive_file_outlined;
}
