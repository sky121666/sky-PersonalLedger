import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ledger/app/personal_ledger_app.dart';
import 'package:personal_ledger/core/providers/core_providers.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';

const _serverUrl = String.fromEnvironment('LEDGER_E2E_SERVER_URL');
const _password = String.fromEnvironment('LEDGER_E2E_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connects to real backend, logs in, and opens quick transaction',
    (tester) async {
      if (_serverUrl.isEmpty) {
        fail('LEDGER_E2E_SERVER_URL is required for real backend smoke test');
      }
      if (_password.length < 8) {
        fail(
          'LEDGER_E2E_PASSWORD is required and must be at least 8 characters',
        );
      }

      final storage = _MemorySecureStorageService();
      await storage.clearAll();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureStorageServiceProvider.overrideWithValue(storage)],
          child: const PersonalLedgerApp(),
        ),
      );

      await _pumpUntilAnyFound(tester, [
        find.byKey(const ValueKey('server-url-field')),
        find.text('连接服务器'),
        find.text('连接账本'),
        find.byKey(const Key('auth-setup-password-field')),
        find.byKey(const Key('auth-login-password-field')),
        find.text('首页'),
      ]);

      if (_isServerConfigVisible()) {
        await _enterTextByPossibleKeys(
          tester,
          const [Key('server-url-field')],
          _serverUrl,
          fallbackLabels: const ['服务器地址', '账本地址'],
        );
        await _tapByKey(tester, const ValueKey('server-connect-button'));
      }

      if (!_isHomeShellVisible()) {
        await _waitForAuthStep(tester);
      }

      await _pumpUntilAnyFound(tester, [
        find.text('首页'),
        find.byKey(const ValueKey('home-recent-transactions-all')),
        find.byKey(const ValueKey('main-shell-quick-transaction')),
      ]);

      await _tapByKey(tester, const ValueKey('main-shell-quick-transaction'));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('transaction-amount')),
      );

      await tester.pump(const Duration(seconds: 12));
    },
  );
}

Future<void> _waitForAuthStep(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));

    if (find
            .byKey(const Key('auth-setup-password-field'))
            .evaluate()
            .isNotEmpty ||
        find
            .byKey(const Key('auth-setup-password-confirm-field'))
            .evaluate()
            .isNotEmpty ||
        find.text('设置密码').evaluate().isNotEmpty) {
      await _enterTextByPossibleKeys(
        tester,
        const [Key('auth-setup-password-field')],
        _password,
        fallbackLabels: const ['密码'],
      );
      await _enterTextByPossibleKeys(
        tester,
        const [Key('auth-setup-password-confirm-field')],
        _password,
        fallbackLabels: const ['确认密码'],
      );
      await _tapByKey(tester, const ValueKey('auth-setup-submit-button'));
      return;
    }

    if (find
            .byKey(const Key('auth-login-password-field'))
            .evaluate()
            .isNotEmpty ||
        find.text('账本解锁').evaluate().isNotEmpty) {
      await _enterTextByPossibleKeys(
        tester,
        const [Key('auth-login-password-field')],
        _password,
        fallbackLabels: const ['密码'],
      );
      await _tapByKey(tester, const ValueKey('auth-login-submit-button'));
      return;
    }
  }

  fail('Neither setup nor login screen appeared');
}

bool _isServerConfigVisible() {
  return find.byKey(const ValueKey('server-url-field')).evaluate().isNotEmpty ||
      find.text('连接账本').evaluate().isNotEmpty ||
      find.text('连接服务器').evaluate().isNotEmpty;
}

bool _isHomeShellVisible() {
  return find.text('首页').evaluate().isNotEmpty ||
      find
          .byKey(const ValueKey('home-recent-transactions-all'))
          .evaluate()
          .isNotEmpty ||
      find
          .byKey(const ValueKey('main-shell-quick-transaction'))
          .evaluate()
          .isNotEmpty;
}

Future<void> _enterTextByPossibleKeys(
  WidgetTester tester,
  List<Key> keyCandidates,
  String value, {
  List<String> fallbackLabels = const [],
}) async {
  for (final key in keyCandidates) {
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(finder, value);
      await tester.pumpAndSettle();
      return;
    }
  }

  for (final label in fallbackLabels) {
    final finder = find.widgetWithText(TextField, label);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(finder, value);
      await tester.pumpAndSettle();
      return;
    }
  }

  fail('未找到可输入文本字段，候选 key=$keyCandidates，标签=$fallbackLabels');
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilAnyFound(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finders.any((finder) => finder.evaluate().isNotEmpty)) {
      return;
    }
  }

  expect(
    finders.any((finder) => finder.evaluate().isNotEmpty),
    isTrue,
    reason: 'None of the expected anchors appeared',
  );
}

Future<void> _tapByKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await _pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _MemorySecureStorageService extends SecureStorageService {
  final Map<String, String> _values = {};

  @override
  Future<String?> readServerUrl() async => _values['server_url'];

  @override
  Future<void> saveServerUrl(String serverUrl) async {
    _values['server_url'] = serverUrl;
  }

  @override
  Future<void> deleteServerUrl() async {
    _values.remove('server_url');
  }

  @override
  Future<String?> readAccessToken() async => _values['access_token'];

  @override
  Future<void> saveAccessToken(String accessToken) async {
    _values['access_token'] = accessToken;
  }

  @override
  Future<String?> readRefreshToken() async => _values['refresh_token'];

  @override
  Future<void> saveRefreshToken(String refreshToken) async {
    _values['refresh_token'] = refreshToken;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _values['access_token'] = accessToken;
    _values['refresh_token'] = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    _values.remove('access_token');
    _values.remove('refresh_token');
  }

  @override
  Future<void> clearAll() async {
    _values.clear();
  }
}
