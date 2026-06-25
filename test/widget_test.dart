import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xylos/models/webdav_account.dart';
import 'package:xylos/main.dart';
import 'package:xylos/services/account_store.dart';
import 'package:xylos/services/webdav_client.dart';
import 'package:xylos/ui/home_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders WebDAV client shell', (WidgetTester tester) async {
    await tester.pumpWidget(const XylosApp());
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(const XylosApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('传输'));
    await tester.pumpAndSettle();

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
      secret: 'password',
      defaultPath: '/',
      allowHttp: true,
      trustSelfSignedCert: false,
    );
    SharedPreferences.setMockInitialValues({
      'xylos.servers.v1': [server.encode()],
    });

    await tester.pumpWidget(const XylosApp());
    await tester.pumpAndSettle();

    expect(find.text('Local NAS'), findsOneWidget);

    await tester.tap(find.text('Local NAS'));
    await tester.pump();

    expect(find.text('Local NAS · 文件'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('当前路径'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('skips malformed stored state during startup',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'xylos.servers.v1': ['not-json'],
      'xylos.transfers.v1': ['not-json'],
    });

    await tester.pumpWidget(const XylosApp());
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('暂无服务器'), findsOneWidget);
    expect(find.text('添加服务器'), findsWidgets);
  });

  testWidgets('shows recoverable error when startup state loading fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomePage(store: _FailingAccountStore())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.textContaining('startup failed'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('switches interface language to English',
      (WidgetTester tester) async {
    await tester.pumpWidget(const XylosApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Servers'), findsWidgets);
    expect(find.text('Transfers'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    await tester.tap(find.text('Servers').first);
    await tester.pumpAndSettle();

    expect(find.text('Add Server'), findsWidgets);
  });

  testWidgets('server editor shows username for digest auth only',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ServerEditorDialog(
            server: null,
            strings: AppStrings.zh,
            servers: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<AuthType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearer Token').last);
    await tester.pumpAndSettle();

    expect(find.text('用户名'), findsNothing);
    expect(find.text('Token'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<AuthType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Digest').last);
    await tester.pumpAndSettle();

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
