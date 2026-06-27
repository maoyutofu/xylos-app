import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xylos/models/webdav_account.dart';
import 'package:xylos/main.dart';
import 'package:xylos/models/transfer_record.dart';
import 'package:xylos/services/account_store.dart';
import 'package:xylos/services/server_qr_payload.dart';
import 'package:xylos/services/webdav_client.dart';
import 'package:xylos/ui/app_theme.dart';
import 'package:xylos/ui/home_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.localeTestValue = const Locale('zh');
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.clearLocaleTestValue();
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxTicks = 20,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < maxTicks; i++) {
      await tester.pump(step);
      if (condition()) {
        return;
      }
    }
  }

  Future<void> pumpApp(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await pumpUntil(
      tester,
      () =>
          find.text('服务器').evaluate().isNotEmpty ||
          find.text('Servers').evaluate().isNotEmpty ||
          find.text('加载失败').evaluate().isNotEmpty ||
          find.text('Load Failed').evaluate().isNotEmpty,
    );
  }

  Future<void> pumpDefaultApp(
    WidgetTester tester, {
    List<WebDavAccount> servers = const [],
    String languageCode = '',
    String downloadDirectory = '/tmp/xylos-test',
    List<TransferRecord> transfers = const [],
  }) async {
    await pumpApp(
      tester,
      XylosApp(
        store: _FakeAccountStore(
          servers: servers,
          languageCode: languageCode,
          downloadDirectory: downloadDirectory,
          transfers: transfers,
        ),
      ),
    );
  }

  ThemeData testTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kAppPrimaryColor,
      brightness: Brightness.light,
    ).copyWith(
      primary: kAppPrimaryColor,
      secondary: kAppPrimaryColor,
      tertiary: kAppPrimaryColor,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      extensions: const [XylosTheme.light],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kAppPrimaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kAppPrimaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: kAppPrimaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kAppButtonRadius),
          ),
        ),
      ),
    );
  }

  WebDavAccount testServer({
    required String id,
    required String name,
    String baseUrl = 'https://dav.example.com',
  }) {
    return WebDavAccount(
      id: id,
      name: name,
      baseUrl: baseUrl,
      authType: AuthType.basic,
      digestAlgorithm: DigestAlgorithm.md5,
      username: 'admin',
      secret: '',
      defaultPath: '/',
      allowHttp: false,
      trustSelfSignedCert: false,
    );
  }

  testWidgets('renders WebDAV client shell', (WidgetTester tester) async {
    await pumpDefaultApp(tester);

    expect(find.text('服务器'), findsWidgets);
    expect(find.text('暂无服务器'), findsOneWidget);
    expect(find.text('添加服务器'), findsWidgets);
    expect(find.text('传输'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('文件'), findsNothing);
    expect(find.text('账号'), findsNothing);
  });

  testWidgets('switches to transfer section', (WidgetTester tester) async {
    await pumpDefaultApp(tester);

    await tester.tap(find.text('传输'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('传输中心'), findsOneWidget);
    expect(find.text('暂无传输记录'), findsOneWidget);
    expect(find.text('上传和下载任务会显示在这里。'), findsOneWidget);
  });

  testWidgets('opens server files from server list',
      (WidgetTester tester) async {
    const server = WebDavAccount(
      id: 'server-test',
      name: 'Local NAS',
      baseUrl: 'http://127.0.0.1:8080/dav',
      authType: AuthType.basic,
      digestAlgorithm: DigestAlgorithm.md5,
      username: 'admin',
      secret: '',
      defaultPath: '/',
      allowHttp: true,
      trustSelfSignedCert: false,
    );
    SharedPreferences.setMockInitialValues({
      'xylos.servers.v1': [server.encode()],
    });

    await pumpDefaultApp(tester, servers: const [server]);

    expect(find.text('Local NAS'), findsOneWidget);

    await tester.tap(find.text('Local NAS'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('skips malformed stored state during startup', () async {
    SharedPreferences.setMockInitialValues({
      'xylos.servers.v1': ['not-json'],
      'xylos.transfers.v1': ['not-json'],
    });
    const store = AccountStore();
    final servers = await store.loadServers();
    final transfers = await store.loadTransfers();

    expect(servers, isEmpty);
    expect(transfers, isEmpty);
  });

  testWidgets('shows recoverable error when startup state loading fails',
      (WidgetTester tester) async {
    await pumpApp(
      tester,
      const MaterialApp(home: HomePage(store: _FailingAccountStore())),
    );
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.textContaining('startup failed'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('switches interface language to English',
      (WidgetTester tester) async {
    await pumpDefaultApp(tester);

    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Servers'), findsWidgets);
    expect(find.text('Transfers'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    await tester.tap(find.text('Servers').first);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Add Server'), findsWidgets);
  });

  testWidgets('server editor shows username for digest auth only',
      (WidgetTester tester) async {
    await pumpApp(
      tester,
      MaterialApp(
        theme: testTheme(),
        home: const Scaffold(
          body: ServerEditorDialog(
            server: null,
            strings: AppStrings.zh,
            servers: [],
          ),
        ),
      ),
    );

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<AuthType>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Bearer Token').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('用户名'), findsNothing);
    expect(find.text('Token'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<AuthType>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Digest').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('Digest 哈希算法'), findsOneWidget);
    expect(find.text('MD5'), findsOneWidget);
  });

  test('localizes WebDAV errors in English', () {
    expect(
      AppStrings.en.webDavError(
        const WebDavException(WebDavFailureKind.unauthorized),
      ),
      'Authentication failed. Check the username, password, or token.',
    );
    expect(
      AppStrings.en.webDavError(
        const WebDavException(
          WebDavFailureKind.httpStatus,
          statusCode: 500,
          detail: '服务器错误',
        ),
      ),
      'Request failed with HTTP status 500.',
    );
    expect(
      AppStrings.en.webDavError(
        const WebDavException(
          WebDavFailureKind.httpStatus,
          statusCode: 500,
          detail: 'Internal Server Error',
        ),
      ),
      'Request failed with HTTP status 500. Internal Server Error',
    );
  });

  test('encodes and decodes encrypted server QR payload', () {
    const server = WebDavAccount(
      id: 'server-qr',
      name: 'Office NAS',
      baseUrl: 'https://dav.example.com/files',
      authType: AuthType.digest,
      digestAlgorithm: DigestAlgorithm.sha256,
      username: 'alice',
      secret: 's3cr3t',
      defaultPath: '/',
      allowHttp: false,
      trustSelfSignedCert: true,
    );

    final payload = encodeServerQrPayload(server, 'passphrase');
    final decoded = decodeServerQrPayload(payload, 'passphrase');

    expect(payload, startsWith(serverQrPayloadPrefix));
    expect(decoded.name, server.name);
    expect(decoded.baseUrl, server.baseUrl);
    expect(decoded.secret, server.secret);
    expect(decoded.authType, server.authType);
  });

  test('renames imported servers when aliases already exist', () {
    final servers = mergeImportedServers(
      [
        testServer(id: 'server-1', name: 'NAS'),
        testServer(id: 'server-2', name: 'NAS (2)'),
      ],
      [
        testServer(id: 'server-3', name: 'NAS'),
        testServer(id: 'server-4', name: 'nas'),
      ],
    );

    expect(servers.map((server) => server.name), [
      'NAS',
      'NAS (2)',
      'NAS (3)',
      'nas (4)',
    ]);
  });

  test('updates imported servers with matching ids', () {
    final servers = mergeImportedServers(
      [
        testServer(id: 'server-1', name: 'NAS'),
        testServer(id: 'server-2', name: 'Office'),
      ],
      [
        testServer(
          id: 'server-1',
          name: 'Backup',
          baseUrl: 'https://backup.example.com',
        ),
      ],
    );

    expect(servers, hasLength(2));
    expect(servers.first.name, 'Backup');
    expect(servers.first.baseUrl, 'https://backup.example.com');
  });

  testWidgets('hides QR import on desktop and keeps server actions visible',
      (WidgetTester tester) async {
    const server = WebDavAccount(
      id: 'server-qr-ui',
      name: 'Local NAS',
      baseUrl: 'https://dav.example.com',
      authType: AuthType.basic,
      digestAlgorithm: DigestAlgorithm.md5,
      username: 'admin',
      secret: '',
      defaultPath: '/',
      allowHttp: false,
      trustSelfSignedCert: false,
    );

    await pumpDefaultApp(tester, servers: const [server]);

    expect(find.text('扫码导入'), findsNothing);
    expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  test('stores server secrets only in local encrypted vault after unlock',
      () async {
    const server = WebDavAccount(
      id: 'server-test',
      name: 'Local NAS',
      baseUrl: 'https://example.com/dav',
      authType: AuthType.basic,
      digestAlgorithm: DigestAlgorithm.md5,
      username: 'admin',
      secret: 'password',
      defaultPath: '/',
      allowHttp: false,
      trustSelfSignedCert: false,
    );

    await const AccountStore().unlockSession('test-passphrase');
    await const AccountStore().saveServers([server]);

    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList('xylos.servers.v1')!;
    expect(values.single, isNot(contains('secret')));
    expect(values.single, isNot(contains('password')));
    final vault = prefs.getString('xylos.secretVault.v1');
    expect(vault, isNotNull);
    expect(vault, isNot(contains('password')));

    final loaded = await const AccountStore().loadServers();
    expect(loaded.single.secret, isEmpty);
    await const AccountStore().unlockSession('test-passphrase');
    final hydrated = await const AccountStore().hydrateServer(loaded.single);
    expect(hydrated.secret, 'password');
  });
}

class _FailingAccountStore extends AccountStore {
  const _FailingAccountStore();

  @override
  Future<List<WebDavAccount>> loadServers() {
    throw const FormatException('startup failed');
  }
}

class _FakeAccountStore extends AccountStore {
  const _FakeAccountStore({
    this.servers = const [],
    this.languageCode = '',
    this.downloadDirectory = '/tmp/xylos-test',
    this.transfers = const [],
  });

  final List<WebDavAccount> servers;
  final String languageCode;
  final String downloadDirectory;
  final List<TransferRecord> transfers;

  @override
  bool get isSessionUnlocked => true;

  @override
  Future<List<WebDavAccount>> loadServers() async => servers;

  @override
  Future<String> loadLanguageCode() async => languageCode;

  @override
  Future<String> loadDownloadDirectory() async => downloadDirectory;

  @override
  Future<List<TransferRecord>> loadTransfers() async => transfers;

  @override
  Future<List<WebDavAccount>> hydrateServersForSession(
    List<WebDavAccount> servers,
  ) async =>
      servers;
}
