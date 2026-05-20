import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ledger/app/personal_ledger_app.dart';
import 'package:personal_ledger/core/providers/core_providers.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';

const _serverUrl = String.fromEnvironment('LEDGER_E2E_SERVER_URL');
const _password = String.fromEnvironment(
  'LEDGER_E2E_PASSWORD',
  defaultValue: 'LedgerE2ePass123!',
);
const _useInMemoryStorage = bool.fromEnvironment(
  'LEDGER_E2E_USE_IN_MEMORY_STORAGE',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connects to a real backend, initializes auth, and loads home', (
    tester,
  ) async {
    if (_serverUrl.isEmpty) {
      fail('LEDGER_E2E_SERVER_URL is required for real backend E2E');
    }
    if (_password.length < 8) {
      fail('LEDGER_E2E_PASSWORD must be at least 8 characters');
    }

    final storage = _useInMemoryStorage
        ? _MemorySecureStorageService()
        : SecureStorageService();
    await storage.clearAll();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _useInMemoryStorage
            ? [secureStorageServiceProvider.overrideWithValue(storage)]
            : const [],
        child: const PersonalLedgerApp(),
      ),
    );

    await _pumpUntilFound(tester, find.text('连接服务器'));

    await tester.enterText(find.widgetWithText(TextField, '服务器地址'), _serverUrl);
    await tester.tap(find.text('连接'));

    await _pumpUntilFound(tester, find.text('首次设置密码'));

    await tester.enterText(find.widgetWithText(TextField, '密码'), _password);
    await tester.enterText(find.widgetWithText(TextField, '确认密码'), _password);
    await tester.tap(find.text('完成设置'));

    await _pumpUntilFound(tester, find.text('首页'));
    await _pumpUntilFound(tester, find.text('净资产'));
    expect(find.text('个人记账'), findsWidgets);
  });
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
