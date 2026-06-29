import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../services/account_store.dart';
import 'app_theme.dart';
import 'home_page.dart';

class ConsentGate extends StatefulWidget {
  const ConsentGate({super.key, required this.store});

  final AccountStore store;

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  var _loading = true;
  var _accepted = false;
  AppLanguage _language = AppLanguage.zh;

  @override
  void initState() {
    super.initState();
    _loadConsentState();
  }

  Future<void> _loadConsentState() async {
    final accepted = await widget.store.hasAcceptedCurrentLegalTerms();
    final languageCode = await widget.store.loadLanguageCode();
    final language = _resolveInitialLanguage(languageCode);
    if (!mounted) {
      return;
    }
    setState(() {
      _accepted = accepted;
      _language = language;
      _loading = false;
    });
  }

  AppLanguage _resolveInitialLanguage(String languageCode) {
    if (languageCode.trim().isNotEmpty) {
      return AppLanguage.fromCode(languageCode);
    }
    final systemLanguageCode =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return systemLanguageCode == AppLanguage.zh.code
        ? AppLanguage.zh
        : AppLanguage.en;
  }

  Future<void> _acceptTerms() async {
    await widget.store.saveLanguageCode(_language.code);
    await widget.store.acceptCurrentLegalTerms();
    if (!mounted) {
      return;
    }
    setState(() {
      _accepted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_accepted) {
      return HomePage(store: widget.store);
    }
    return LegalConsentPage(
      language: _language,
      onLanguageChanged: (language) {
        setState(() {
          _language = language;
        });
      },
      onAccepted: _acceptTerms,
    );
  }
}

class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.onAccepted,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final Future<void> Function() onAccepted;

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  var _checked = false;
  var _submitting = false;

  @override
  Widget build(BuildContext context) {
    final strings = LegalConsentStrings.of(widget.language);
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: theme.xylos.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: EdgeInsets.all(isCompact ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: theme.smallRadius,
                        child: Image.asset(
                          'assets/icon.png',
                          width: 36,
                          height: 36,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.title,
                              style: TextStyle(
                                color: theme.xylos.text,
                                fontSize: isCompact ? 20 : 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              strings.subtitle,
                              style: TextStyle(
                                color: theme.xylos.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SegmentedButton<AppLanguage>(
                        segments: const [
                          ButtonSegment(
                            value: AppLanguage.zh,
                            label: Text('中文'),
                          ),
                          ButtonSegment(
                            value: AppLanguage.en,
                            label: Text('EN'),
                          ),
                        ],
                        selected: {widget.language},
                        onSelectionChanged: (selection) {
                          widget.onLanguageChanged(selection.first);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.xylos.surface,
                        border: Border.all(color: theme.xylos.moduleBorder),
                        borderRadius: theme.smallRadius,
                      ),
                      child: DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            TabBar(
                              labelColor: theme.colorScheme.primary,
                              unselectedLabelColor: theme.xylos.muted,
                              indicatorColor: theme.colorScheme.primary,
                              tabs: [
                                Tab(text: strings.userAgreementTab),
                                Tab(text: strings.privacyPolicyTab),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _LegalDocumentView(
                                    sections: strings.userAgreementSections,
                                  ),
                                  _LegalDocumentView(
                                    sections: strings.privacyPolicySections,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.xylos.surface,
                      border: Border.all(color: theme.xylos.moduleBorder),
                      borderRadius: theme.smallRadius,
                    ),
                    child: CheckboxListTile(
                      value: _checked,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        strings.checkboxLabel,
                        style: TextStyle(
                          color: theme.xylos.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        strings.checkboxHint,
                        style: TextStyle(color: theme.xylos.muted),
                      ),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              setState(() {
                                _checked = value ?? false;
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _submitting ? null : _exitApp,
                        child: Text(strings.exit),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _checked && !_submitting ? _submit : null,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(strings.agreeAndContinue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
    });
    try {
      await widget.onAccepted();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _exitApp() {
    if (Platform.isAndroid) {
      const MethodChannel('space.xylos.app/system')
          .invokeMethod<void>('moveToBackground');
      return;
    }
    SystemNavigator.pop();
  }
}

class _LegalDocumentView extends StatelessWidget {
  const _LegalDocumentView({required this.sections});

  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scrollbar(
      thumbVisibility: true,
      child: ListView.separated(
        padding: const EdgeInsets.all(18),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final section = sections[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: TextStyle(
                  color: theme.xylos.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              ...section.paragraphs.map(
                (paragraph) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    paragraph,
                    style: TextStyle(
                      color: theme.xylos.text,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LegalSection {
  const LegalSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class LegalConsentStrings {
  const LegalConsentStrings({
    required this.title,
    required this.subtitle,
    required this.userAgreementTab,
    required this.privacyPolicyTab,
    required this.checkboxLabel,
    required this.checkboxHint,
    required this.exit,
    required this.agreeAndContinue,
    required this.userAgreementSections,
    required this.privacyPolicySections,
  });

  final String title;
  final String subtitle;
  final String userAgreementTab;
  final String privacyPolicyTab;
  final String checkboxLabel;
  final String checkboxHint;
  final String exit;
  final String agreeAndContinue;
  final List<LegalSection> userAgreementSections;
  final List<LegalSection> privacyPolicySections;

  static LegalConsentStrings of(AppLanguage language) {
    switch (language) {
      case AppLanguage.zh:
        return zh;
      case AppLanguage.en:
        return en;
    }
  }

  static final zh = LegalConsentStrings(
    title: '用户协议与隐私条款',
    subtitle: 'Xylos ${AppVersion.displayVersion}',
    userAgreementTab: '用户协议',
    privacyPolicyTab: '隐私条款',
    checkboxLabel: '我已阅读并同意《用户协议》和《隐私条款》',
    checkboxHint: '不同意将无法继续使用 Xylos。',
    exit: '不同意并退出',
    agreeAndContinue: '同意并继续',
    userAgreementSections: const [
      LegalSection(
        title: '1. 协议范围',
        paragraphs: [
          '本用户协议适用于你下载、安装、访问或使用 Xylos 应用及相关功能的行为。',
          'Xylos 是一款 WebDAV 文件管理工具，用于连接你自行配置的服务器，浏览、上传、下载、删除和管理文件。你需要自行确认服务器、账号、网络环境及文件内容的合法性和可用性。',
        ],
      ),
      LegalSection(
        title: '2. 使用条件',
        paragraphs: [
          '你应具备使用本应用所需的民事行为能力，或已取得监护人、组织管理员或账号所有者的授权。',
          '你应妥善保管 WebDAV 地址、用户名、密码、令牌、主口令和本地导出的配置文件。因你主动披露、设备丢失、系统环境不安全或第三方服务问题造成的损失，由你自行承担。',
        ],
      ),
      LegalSection(
        title: '3. 用户行为',
        paragraphs: [
          '你不得使用本应用访问、上传、下载、传播、备份或处理违法、侵权、恶意、欺诈、破坏性或未经授权的数据。',
          '你不得利用本应用攻击服务器、绕过访问控制、干扰网络服务、批量探测账号、传播恶意代码，或从事任何违反适用法律法规和第三方服务规则的行为。',
        ],
      ),
      LegalSection(
        title: '4. 第三方服务',
        paragraphs: [
          'Xylos 连接的 WebDAV 服务由你或第三方提供。本应用不控制第三方服务器的稳定性、权限策略、计费、数据保存、备份、删除或安全措施。',
          '你在第三方服务器上的文件处理行为可能同时受该第三方服务条款、隐私政策和所在地区法律约束。',
        ],
      ),
      LegalSection(
        title: '5. 数据与备份',
        paragraphs: [
          '删除、覆盖、移动、同步或批量传输文件前，请自行确认操作对象和备份情况。本应用不会承诺自动恢复被你或服务器删除、覆盖或损坏的数据。',
          '本应用可能在本地保存服务器配置、传输记录、下载目录和已下载文件。你可以通过系统文件管理、应用设置或卸载应用清理相关数据。',
        ],
      ),
      LegalSection(
        title: '6. 免责声明',
        paragraphs: [
          '在法律允许的最大范围内，Xylos 按现状提供，不对持续可用、完全无错误、满足特定目的、与全部服务器兼容或数据绝对安全作出保证。',
          '因网络中断、服务器故障、账号权限、证书配置、用户误操作、第三方服务变化、设备系统限制或不可抗力造成的损失，本应用开发者不承担超出适用法律强制要求的责任。',
        ],
      ),
      LegalSection(
        title: '7. 协议更新',
        paragraphs: [
          '我们可能根据功能变化、合规要求或运营需要更新本协议。重要更新可能会在应用内再次提示你阅读并同意。',
          '如你不同意更新后的条款，应停止使用本应用。',
        ],
      ),
      LegalSection(
        title: '8. 联系与反馈',
        paragraphs: [
          '如你对本协议或应用功能有疑问，可通过项目主页、应用内提供的反馈渠道或发布页面联系我们。',
          '本协议为通用模板，不构成法律意见。如应用用于商业发布、特定地区上架或处理敏感数据，请在发布前咨询专业法律顾问。',
        ],
      ),
    ],
    privacyPolicySections: const [
      LegalSection(
        title: '1. 我们处理的数据',
        paragraphs: [
          '为实现 WebDAV 文件管理功能，Xylos 可能在你的设备本地处理你输入的服务器地址、别名、用户名、认证方式、密码或令牌、证书信任设置、下载目录、传输记录和语言偏好。',
          '当你连接 WebDAV 服务器时，本应用会向你配置的服务器发送必要请求，并接收目录列表、文件元数据、文件内容和服务器响应。相关数据由你选择的服务器处理。',
        ],
      ),
      LegalSection(
        title: '2. 本地存储',
        paragraphs: [
          '服务器配置、语言偏好、下载目录、传输记录和协议同意状态可能保存在设备本地。',
          '如你设置主口令，部分敏感配置会以加密形式保存。请牢记主口令；遗忘主口令可能导致无法恢复本地保存的敏感信息。',
        ],
      ),
      LegalSection(
        title: '3. 网络传输',
        paragraphs: [
          '本应用仅在你配置并发起连接、上传、下载、删除、创建目录、刷新目录或测试连接时，与相应 WebDAV 服务器通信。',
          '如果你选择使用 HTTP 或信任自签名证书，传输安全性可能低于标准 HTTPS 证书环境。请仅在可信网络和你理解风险的情况下启用。',
        ],
      ),
      LegalSection(
        title: '4. 权限使用',
        paragraphs: [
          '本应用可能根据平台需要请求文件选择、照片选择、相机扫码、网络访问和本地存储相关权限。',
          '相机权限用于扫描服务器配置二维码；文件和照片权限用于选择上传文件或保存/打开下载文件。本应用不会因这些权限而主动读取无关文件。',
        ],
      ),
      LegalSection(
        title: '5. 第三方共享',
        paragraphs: [
          '本应用不会主动将你的服务器配置、账号密码、文件内容或传输记录上传到开发者服务器。',
          '你连接的 WebDAV 服务器、操作系统、应用商店、崩溃报告工具或网络服务提供方可能依据其自身规则处理相关数据。请阅读相应第三方的隐私政策。',
        ],
      ),
      LegalSection(
        title: '6. 数据导入导出',
        paragraphs: [
          '当你导出配置或生成二维码时，导出的文件或二维码可能包含服务器地址、账号信息或敏感凭据。请只在可信设备和可信对象之间分享。',
          '当你导入配置或扫描二维码时，请确认来源可信，避免导入恶意服务器地址或错误凭据。',
        ],
      ),
      LegalSection(
        title: '7. 数据删除',
        paragraphs: [
          '你可以在应用内删除服务器配置、清理传输记录或删除本地下载文件。也可以通过系统设置清除应用数据或卸载应用。',
          '删除本地配置不会自动删除远程服务器上的文件；删除远程文件则取决于你在应用内执行的具体 WebDAV 操作。',
        ],
      ),
      LegalSection(
        title: '8. 未成年人',
        paragraphs: [
          '未成年人应在监护人指导和同意下使用本应用。监护人应关注其连接的服务器、上传下载内容和账号权限。',
        ],
      ),
      LegalSection(
        title: '9. 隐私条款更新',
        paragraphs: [
          '我们可能根据功能变化、平台要求或法律法规更新本隐私条款。重要更新可能会在应用内再次提示。',
          '继续使用本应用表示你接受更新后的隐私条款。',
        ],
      ),
    ],
  );

  static final en = LegalConsentStrings(
    title: 'Terms and Privacy',
    subtitle: 'Xylos ${AppVersion.displayVersion}',
    userAgreementTab: 'Terms',
    privacyPolicyTab: 'Privacy',
    checkboxLabel: 'I have read and agree to the Terms and Privacy Policy',
    checkboxHint: 'You cannot continue using Xylos unless you agree.',
    exit: 'Decline and Exit',
    agreeAndContinue: 'Agree and Continue',
    userAgreementSections: const [
      LegalSection(
        title: '1. Scope',
        paragraphs: [
          'These Terms apply to your download, installation, access to, and use of the Xylos app and its related features.',
          'Xylos is a WebDAV file management tool. It lets you connect to servers you configure, browse, upload, download, delete, and manage files. You are responsible for ensuring that your servers, accounts, network environment, and files are lawful and available.',
        ],
      ),
      LegalSection(
        title: '2. Eligibility and Account Security',
        paragraphs: [
          'You must have the legal capacity to use the app, or have authorization from a guardian, organization administrator, or account owner.',
          'You are responsible for protecting WebDAV URLs, usernames, passwords, tokens, master passphrases, and exported configuration files. Losses caused by disclosure, device loss, unsafe system environments, or third-party service issues are your responsibility.',
        ],
      ),
      LegalSection(
        title: '3. Acceptable Use',
        paragraphs: [
          'You must not use the app to access, upload, download, distribute, back up, or process unlawful, infringing, malicious, fraudulent, destructive, or unauthorized data.',
          'You must not use the app to attack servers, bypass access controls, disrupt network services, probe accounts, distribute malware, or violate applicable laws or third-party service rules.',
        ],
      ),
      LegalSection(
        title: '4. Third-Party Services',
        paragraphs: [
          'The WebDAV services connected through Xylos are provided by you or third parties. The app does not control third-party server stability, permissions, billing, storage, backups, deletion, or security measures.',
          'Your file operations on third-party servers may also be governed by that service provider’s terms, privacy policy, and applicable laws.',
        ],
      ),
      LegalSection(
        title: '5. Data and Backups',
        paragraphs: [
          'Before deleting, overwriting, moving, syncing, or transferring files in bulk, you should verify the target files and maintain your own backups. The app does not promise automatic recovery for data deleted, overwritten, or damaged by you or a server.',
          'The app may store server configurations, transfer history, download folders, and downloaded files locally. You can clear related data through system file management, app settings, or by uninstalling the app.',
        ],
      ),
      LegalSection(
        title: '6. Disclaimer',
        paragraphs: [
          'To the maximum extent permitted by law, Xylos is provided as is, without warranties that it will be continuously available, error-free, fit for a particular purpose, compatible with every server, or absolutely secure.',
          'The developer is not liable beyond mandatory legal requirements for losses caused by network outages, server failures, account permissions, certificate configuration, user error, third-party service changes, device or OS limitations, or force majeure events.',
        ],
      ),
      LegalSection(
        title: '7. Updates',
        paragraphs: [
          'We may update these Terms due to feature changes, compliance requirements, or operational needs. Material updates may be presented in the app for your review and acceptance.',
          'If you do not agree to updated terms, you should stop using the app.',
        ],
      ),
      LegalSection(
        title: '8. Contact and Notes',
        paragraphs: [
          'If you have questions about these Terms or the app, contact us through the project homepage, in-app feedback channels, or release page.',
          'These Terms are a general template and do not constitute legal advice. For commercial release, app store distribution in specific regions, or sensitive data processing, consult qualified legal counsel before publishing.',
        ],
      ),
    ],
    privacyPolicySections: const [
      LegalSection(
        title: '1. Data We Process',
        paragraphs: [
          'To provide WebDAV file management features, Xylos may process server URLs, aliases, usernames, authentication methods, passwords or tokens, certificate trust settings, download folders, transfer history, and language preferences on your device.',
          'When you connect to a WebDAV server, the app sends necessary requests to the server you configured and receives directory listings, file metadata, file contents, and server responses. That data is processed by the server you choose.',
        ],
      ),
      LegalSection(
        title: '2. Local Storage',
        paragraphs: [
          'Server configurations, language preferences, download folders, transfer history, and consent status may be stored locally on your device.',
          'If you set a master passphrase, certain sensitive configurations are stored in encrypted form. Keep the passphrase safe; forgetting it may prevent recovery of locally stored sensitive information.',
        ],
      ),
      LegalSection(
        title: '3. Network Transfers',
        paragraphs: [
          'The app communicates with the relevant WebDAV server only when you configure and initiate connection, upload, download, delete, folder creation, refresh, or connection testing actions.',
          'If you enable HTTP or trust a self-signed certificate, transport security may be weaker than a standard HTTPS certificate environment. Enable these options only on trusted networks and when you understand the risks.',
        ],
      ),
      LegalSection(
        title: '4. Permissions',
        paragraphs: [
          'Depending on the platform, the app may request permissions related to file picking, photo picking, camera scanning, network access, and local storage.',
          'Camera permission is used to scan server configuration QR codes. File and photo permissions are used to select upload files or save/open downloaded files. The app does not actively read unrelated files because of these permissions.',
        ],
      ),
      LegalSection(
        title: '5. Third-Party Sharing',
        paragraphs: [
          'The app does not intentionally upload your server configurations, account credentials, file contents, or transfer history to a developer-operated server.',
          'Your WebDAV server, operating system, app store, crash reporting tools, or network providers may process related data under their own rules. Review the privacy policies of those third parties.',
        ],
      ),
      LegalSection(
        title: '6. Import and Export',
        paragraphs: [
          'When you export configurations or generate QR codes, the exported file or QR code may contain server addresses, account information, or sensitive credentials. Share them only between trusted devices and trusted recipients.',
          'When importing configurations or scanning QR codes, verify that the source is trustworthy to avoid importing malicious server URLs or incorrect credentials.',
        ],
      ),
      LegalSection(
        title: '7. Deletion',
        paragraphs: [
          'You can delete server configurations, clear transfer history, or delete local downloaded files in the app. You can also clear app data or uninstall the app through system settings.',
          'Deleting local configurations does not automatically delete files on remote servers. Remote deletion depends on the specific WebDAV operation you perform in the app.',
        ],
      ),
      LegalSection(
        title: '8. Minors',
        paragraphs: [
          'Minors should use the app with guardian guidance and consent. Guardians should pay attention to connected servers, uploaded or downloaded content, and account permissions.',
        ],
      ),
      LegalSection(
        title: '9. Privacy Updates',
        paragraphs: [
          'We may update this Privacy Policy due to feature changes, platform requirements, or applicable laws. Material updates may be presented in the app.',
          'Continuing to use the app means you accept the updated Privacy Policy.',
        ],
      ),
    ],
  );
}
