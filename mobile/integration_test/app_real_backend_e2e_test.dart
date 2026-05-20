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

  testWidgets('connects to a real backend and completes a ledger entry flow', (
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

    await _createAccount(tester);
    await _createExpenseTransaction(tester);
    await _verifyTransactionList(tester);
    await _verifyAccountBalance(tester, '¥1188.89');
    await _editExpenseTransaction(tester);
    await _verifyAccountBalance(tester, '¥1184.56');
    await _deleteExpenseTransaction(tester);
    await _verifyAccountBalance(tester, '¥1234.56');
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

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }

  expect(finder, findsNothing);
}

Future<void> _createAccount(WidgetTester tester) async {
  await _tapText(tester, '我的');
  await _pumpUntilFound(tester, find.text('账户管理'));

  await _tapText(tester, '账户管理');
  await _pumpUntilFound(tester, find.text('账户'));

  await _tapText(tester, '新增账户');
  await _pumpUntilFound(tester, find.byKey(const ValueKey('account-name')));

  await tester.enterText(find.byKey(const ValueKey('account-name')), 'E2E现金钱包');
  await tester.enterText(
    find.byKey(const ValueKey('account-initial-balance')),
    '1234.56',
  );
  await _tapKey(tester, const ValueKey('account-save'));

  await _pumpUntilFound(tester, find.text('E2E现金钱包'));
  await _goBack(tester, untilText: '我的');
  await _pumpUntilFound(tester, find.text('我的'));
}

Future<void> _createExpenseTransaction(WidgetTester tester) async {
  await _tapText(tester, '首页');
  await _pumpUntilFound(tester, find.text('净资产'));

  await _tapText(tester, '记一笔');
  await _pumpUntilFound(tester, find.text('金额'));

  await tester.enterText(
    find.byKey(const ValueKey('transaction-amount')),
    '45.67',
  );
  await _selectDropdownItem(tester, fieldLabel: '账户', itemText: 'E2E现金钱包');
  await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
  await tester.enterText(
    find.byKey(const ValueKey('transaction-remark')),
    'E2E午餐验证',
  );
  await _tapKey(tester, const ValueKey('transaction-save'));

  await _pumpUntilFound(tester, find.text('交易已创建'));
}

Future<void> _verifyTransactionList(WidgetTester tester) async {
  await _tapText(tester, '明细');
  await _pumpUntilFound(tester, find.text('E2E午餐验证'));
  await _pumpUntilFound(tester, find.text('-¥45.67'));
  expect(find.text('餐饮'), findsWidgets);
}

Future<void> _editExpenseTransaction(WidgetTester tester) async {
  await _tapText(tester, '明细');
  await _pumpUntilFound(tester, find.text('E2E午餐验证'));

  await tester.tap(_transactionTileByRemark('E2E午餐验证'));
  await tester.pumpAndSettle();
  await _pumpUntilFound(tester, find.text('编辑交易'));

  await tester.enterText(
    find.byKey(const ValueKey('transaction-amount')),
    '50',
  );
  await tester.enterText(
    find.byKey(const ValueKey('transaction-remark')),
    'E2E午餐验证-更新',
  );
  await _tapKey(tester, const ValueKey('transaction-save'));

  await _pumpUntilFound(tester, find.text('明细'));
  await _pumpUntilFound(tester, find.text('E2E午餐验证-更新'));
  await _pumpUntilFound(tester, find.text('-¥50.00'));
}

Future<void> _deleteExpenseTransaction(WidgetTester tester) async {
  await _tapText(tester, '明细');
  await _pumpUntilFound(tester, find.text('E2E午餐验证-更新'));

  final menuButton = find.descendant(
    of: _transactionTileByRemark('E2E午餐验证-更新'),
    matching: find.byType(PopupMenuButton<String>),
  );
  await _pumpUntilFound(tester, menuButton);
  await tester.tap(menuButton);
  await tester.pumpAndSettle();

  await tester.tap(find.text('删除').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '删除'));
  await tester.pumpAndSettle();

  await _pumpUntilFound(tester, find.text('交易已删除'));
  await _pumpUntilGone(tester, find.text('E2E午餐验证-更新'));
}

Future<void> _verifyAccountBalance(
  WidgetTester tester,
  String expectedBalance,
) async {
  await _tapText(tester, '我的');
  await _pumpUntilFound(tester, find.text('账户管理'));

  await _tapText(tester, '账户管理');
  await _pumpUntilFound(tester, find.text('E2E现金钱包'));
  await _pumpUntilFound(tester, find.text(expectedBalance));

  await _goBack(tester, untilText: '我的');
  await _pumpUntilFound(tester, find.text('我的'));
}

Finder _transactionTileByRemark(String remark) {
  return find
      .ancestor(of: find.text(remark), matching: find.byType(ListTile))
      .last;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await _pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder.last);
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await _dismissKeyboard(tester);
  final finder = find.byKey(key);
  final scrollables = _verticalScrollables();
  if (scrollables.evaluate().isNotEmpty && finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: scrollables.last,
      maxScrolls: 20,
    );
  }
  await _pumpUntilFound(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _goBack(WidgetTester tester, {String? untilText}) async {
  for (var attempt = 0; attempt < 3; attempt += 1) {
    if (_isTextVisible(untilText)) {
      return;
    }

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    if (_isTextVisible(untilText)) {
      return;
    }

    final backButton = find.byTooltip('Back');
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton.last, warnIfMissed: false);
      await tester.pumpAndSettle();
      if (_isTextVisible(untilText)) {
        return;
      }
    }

    await tester.pageBack();
    await tester.pumpAndSettle();
  }
}

bool _isTextVisible(String? text) {
  return text == null || find.text(text).evaluate().isNotEmpty;
}

Finder _verticalScrollables() {
  return find.byWidgetPredicate((widget) {
    return widget is Scrollable &&
        (widget.axisDirection == AxisDirection.down ||
            widget.axisDirection == AxisDirection.up);
  });
}

Future<void> _selectDropdownItem(
  WidgetTester tester, {
  required String fieldLabel,
  required String itemText,
}) async {
  final dropdown = find.ancestor(
    of: find.text(fieldLabel),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await _pumpUntilFound(tester, dropdown);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

Future<void> _dismissKeyboard(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
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
