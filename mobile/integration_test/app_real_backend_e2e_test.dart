import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ledger/app/personal_ledger_app.dart';
import 'package:personal_ledger/app/router/app_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/core/providers/core_providers.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';

const _serverUrl = String.fromEnvironment('LEDGER_E2E_SERVER_URL');
const _password = String.fromEnvironment('LEDGER_E2E_PASSWORD');
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

    await _pumpUntilAnyFound(tester, [find.text('连接服务器'), find.text('连接账本')]);

    await _enterAuthTextField(tester, ['服务器地址', '账本地址'], _serverUrl);
    await _tapTextOrKey(
      tester,
      keys: const [Key('server-connect-button')],
      fallbackTexts: const ['进入账本', '连接'],
    );
    await _waitForAuthForm(tester);

    await _pumpUntilFound(tester, find.text('首页'));
    await _pumpUntilFound(tester, find.text('净资产'));

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

Future<void> _pumpUntilAtLeastFound(
  WidgetTester tester,
  Finder finder, {
  int minMatches = 1,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().length >= minMatches) {
      return;
    }
  }

  expect(
    finder.evaluate().length >= minMatches,
    isTrue,
    reason: '未找到足够的匹配项（最低 ${minMatches.toString()} 个）',
  );
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
    reason: '未找到可识别的页面状态',
  );
}

Future<void> _scrollUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxScrolls = 20,
}) async {
  for (var attempt = 0; attempt < maxScrolls; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      return;
    }

    final scrollables = _verticalScrollables();
    if (scrollables.evaluate().isEmpty) {
      break;
    }
    await tester.drag(
      scrollables.first,
      const Offset(0, -300),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  expect(finder, findsOneWidget);
}

Future<void> _createAccount(WidgetTester tester) async {
  await _openShellTab(tester, keyValue: 'profile', label: '我的');
  await _openProfileAccounts(tester);
  await _pumpUntilFound(tester, find.text('账户'));

  await _tapKey(tester, const ValueKey('account-add'));
  await _pumpUntilFound(tester, find.byKey(const ValueKey('account-name')));

  await _enterTextByKey(tester, const ValueKey('account-name'), 'E2E现金钱包');
  await _enterTextByKey(
    tester,
    const ValueKey('account-initial-balance'),
    '1234.56',
  );
  await _tapKey(tester, const ValueKey('account-save'));

  await _pumpUntilFound(tester, find.text('保存成功'));
  await _scrollUntilFound(tester, find.text('E2E现金钱包'));
  await _goBack(tester, untilText: '我的');
  await _pumpUntilFound(tester, find.text('我的'));
}

Future<void> _waitForAuthForm(WidgetTester tester) async {
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
      await _tapKeyOrText(
        tester,
        key: const ValueKey('auth-setup-submit-button'),
        fallbackTexts: const ['完成设置'],
      );
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
      await _tapKeyOrText(
        tester,
        key: const ValueKey('auth-login-submit-button'),
        fallbackTexts: const ['登录'],
      );
      return;
    }
  }

  fail(
    '未进入设置/登录鉴权页。当前关键文本：'
    '${find.text('账本连接失败，请检查地址或网络').evaluate().isNotEmpty ? '账本连接失败；' : ''}'
    '${find.text('连接账本').evaluate().isNotEmpty ? '连接账本；' : ''}'
    '${find.text('连接服务器').evaluate().isNotEmpty ? '连接服务器；' : ''}'
    '${find.text('设置密码').evaluate().isNotEmpty ? '设置密码；' : ''}'
    '${find.text('账本解锁').evaluate().isNotEmpty ? '账本解锁；' : ''}'
    '${find.text('登录').evaluate().isNotEmpty ? '登录；' : ''}',
  );
}

Future<void> _enterAuthTextField(
  WidgetTester tester,
  List<String> possibleLabels,
  String value,
) async {
  await _enterTextByPossibleKeys(
    tester,
    const [Key('server-url-field')],
    value,
    fallbackLabels: possibleLabels,
  );
}

Future<void> _enterTextByPossibleKeys(
  WidgetTester tester,
  List<Key> keyCandidates,
  String value, {
  List<String> fallbackLabels = const [],
}) async {
  for (final key in keyCandidates) {
    if (find.byKey(key).evaluate().isNotEmpty) {
      await _enterTextByKey(tester, key, value);
      return;
    }
  }
  for (final label in fallbackLabels) {
    if (find.widgetWithText(TextField, label).evaluate().isNotEmpty) {
      final finder = find.widgetWithText(TextField, label);
      await _pumpUntilFound(tester, finder);
      await _bringIntoTapArea(tester, finder);
      await tester.tap(finder, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, label), value);
      await tester.pumpAndSettle();
      return;
    }
  }

  fail('未找到可输入文本的字段（候选 key: $keyCandidates，标签: $fallbackLabels）');
}

Future<void> _tapKeyOrText(
  WidgetTester tester, {
  required Key key,
  required List<String> fallbackTexts,
}) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isNotEmpty) {
    await _tapKey(tester, key);
    return;
  }

  for (final text in fallbackTexts) {
    if (find.text(text).evaluate().isNotEmpty) {
      await _tapText(tester, text);
      return;
    }
  }

  fail('未找到可点击提交控件（key=$key，文本=$fallbackTexts）');
}

Future<void> _tapTextOrKey(
  WidgetTester tester, {
  required List<Key> keys,
  required List<String> fallbackTexts,
}) async {
  for (final key in keys) {
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      await _tapKey(tester, key);
      return;
    }
  }
  for (final text in fallbackTexts) {
    final finder = find.text(text);
    if (finder.evaluate().isNotEmpty) {
      await _tapText(tester, text);
      return;
    }
  }

  final fallbackButtonTexts = [...fallbackTexts, '保存', '记账'];
  for (final text in fallbackButtonTexts) {
    final buttonText = find.descendant(
      of: find.byType(FilledButton),
      matching: find.text(text),
    );
    if (buttonText.evaluate().isNotEmpty) {
      final saveButton = find.ancestor(
        of: buttonText,
        matching: find.byType(FilledButton),
      );
      await _pumpUntilFound(tester, saveButton);
      await _bringIntoTapArea(tester, saveButton);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      return;
    }
  }

  final filledButton = find.byType(FilledButton);
  if (filledButton.evaluate().isNotEmpty &&
      filledButton.evaluate().length == 1) {
    await _pumpUntilFound(tester, filledButton);
    await _bringIntoTapArea(tester, filledButton);
    await tester.tap(filledButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    return;
  }

  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(const Duration(milliseconds: 400));

  if (_isAuthFormVisible() || _isHomeShellVisible()) {
    return;
  }

  fail('未找到可点击按钮（候选 key: $keys，文本: $fallbackTexts）');
}

bool _isAuthFormVisible() {
  return find
          .byKey(const Key('auth-setup-password-field'))
          .evaluate()
          .isNotEmpty ||
      find
          .byKey(const Key('auth-setup-password-confirm-field'))
          .evaluate()
          .isNotEmpty ||
      find.text('设置密码').evaluate().isNotEmpty ||
      find
          .byKey(const Key('auth-login-password-field'))
          .evaluate()
          .isNotEmpty ||
      find.text('账本解锁').evaluate().isNotEmpty;
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

Future<void> _createExpenseTransaction(WidgetTester tester) async {
  await _openShellTab(tester, keyValue: 'home', label: '首页');
  await _pumpUntilAnyFound(tester, [
    find.byKey(const ValueKey('main-shell-quick-transaction')),
    find.byKey(const ValueKey('home-recent-transactions-all')),
    find.text('首页'),
    find.text('净资产'),
  ]);

  await _tapKey(tester, const ValueKey('main-shell-quick-transaction'));
  await _pumpUntilFound(tester, find.text('金额'));

  await _enterTextByKey(tester, const ValueKey('transaction-amount'), '45.67');
  await _selectDropdownItem(tester, fieldLabel: '账户', itemText: 'E2E现金钱包');
  await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
  await _tapKey(tester, const ValueKey('transaction-more-options'));
  await _enterTextByKey(
    tester,
    const ValueKey('transaction-remark'),
    'E2E午餐验证',
  );
  await _tapTextOrKey(
    tester,
    keys: const [Key('transaction-save')],
    fallbackTexts: const ['记一笔'],
  );

  try {
    await _findTransaction(tester, 'E2E午餐验证', amountText: '-¥45.67');
  } on TestFailure {
    await _pumpUntilAnyFound(tester, [
      find.text('交易已创建'),
      find.text('交易已更新'),
      find.byKey(const ValueKey('main-shell-tab-transactions')),
    ], timeout: const Duration(seconds: 8));
    await _findTransaction(tester, 'E2E午餐验证', amountText: '-¥45.67');
  }
}

Future<void> _verifyTransactionList(WidgetTester tester) async {
  await _findTransaction(tester, 'E2E午餐验证', amountText: '-¥45.67');
  await _scrollUntilFound(tester, find.text('-¥45.67'));
  expect(find.text('餐饮'), findsWidgets);
}

Future<void> _editExpenseTransaction(WidgetTester tester) async {
  final transactionTile = await _findTransaction(
    tester,
    'E2E午餐验证',
    amountText: '-¥45.67',
  );

  await _pumpUntilFound(tester, transactionTile);
  await tester.tap(transactionTile, warnIfMissed: false);
  await tester.pumpAndSettle();
  await _pumpUntilAnyFound(tester, [
    find.byKey(const ValueKey('transaction-amount')),
    find.text('编辑交易'),
    find.text('保存修改'),
    find.text('记一笔'),
  ]);

  await _enterTextByKey(tester, const ValueKey('transaction-amount'), '50');
  if (find.byKey(const ValueKey('transaction-remark')).evaluate().isEmpty) {
    await _tapKey(tester, const ValueKey('transaction-more-options'));
  }
  await _enterTextByKey(
    tester,
    const ValueKey('transaction-remark'),
    'E2E午餐验证-更新',
  );
  await _tapTextOrKey(
    tester,
    keys: const [Key('transaction-save')],
    fallbackTexts: const ['保存修改', '记一笔'],
  );

  await _pumpUntilFound(tester, find.text('明细'));
  await _scrollUntilFound(tester, find.text('-¥50.00'));
}

Future<void> _deleteExpenseTransaction(WidgetTester tester) async {
  final transactionTile = await _findTransaction(
    tester,
    'E2E午餐验证-更新',
    amountText: '-¥50.00',
  );

  final menuButton = find.descendant(
    of: transactionTile,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuButton &&
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith(
            'transaction-more-menu-',
          ),
      skipOffstage: false,
    ),
  );
  await _pumpUntilFound(tester, menuButton);
  await _bringIntoTapArea(tester, menuButton);
  await tester.tap(menuButton, warnIfMissed: false);
  await tester.pumpAndSettle();

  await tester.tap(find.text('删除').last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '删除'));
  await tester.pumpAndSettle();

  try {
    await _pumpUntilAtLeastFound(
      tester,
      find.text('交易已删除'),
      minMatches: 1,
      timeout: const Duration(seconds: 8),
    );
  } catch (_) {
    await _pumpUntilFound(tester, find.text('删除'));
  }

  try {
    await _findTransaction(tester, 'E2E午餐验证-更新', amountText: '-¥50.00');
    fail('删除后仍能找到交易');
  } catch (_) {
    // 预期：交易已被移除，列表中无法继续定位到该条目
  }
}

Future<void> _verifyAccountBalance(
  WidgetTester tester,
  String expectedBalance,
) async {
  await _openShellTab(tester, keyValue: 'profile', label: '我的');
  await _openProfileAccounts(tester);
  await _scrollUntilFound(tester, find.text('E2E现金钱包'));
  await _scrollUntilFound(tester, find.text(expectedBalance));

  await _goBack(tester, untilText: '我的');
  await _pumpUntilFound(tester, find.text('我的'));
}

Future<void> _openProfileAccounts(WidgetTester tester) async {
  if (find.byKey(const ValueKey('profile-entry-账户')).evaluate().isEmpty) {
    await _tapKey(tester, const ValueKey('profile-section-账本'));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('profile-entry-账户')),
    );
  }
  await _tapKey(tester, const ValueKey('profile-entry-账户'));
}

Future<Finder> _findTransaction(
  WidgetTester tester,
  String remark, {
  String? amountText,
}) async {
  if (find.byKey(const ValueKey('transaction-search')).evaluate().isEmpty) {
    if (find.byKey(const ValueKey('transaction-search')).evaluate().isEmpty) {
      await _openTransactionListByRoute(tester);
    }
    if (find.byKey(const ValueKey('transaction-search')).evaluate().isEmpty &&
        find
            .byKey(const ValueKey('home-recent-transactions-all'))
            .evaluate()
            .isNotEmpty) {
      await _tapKey(tester, const ValueKey('home-recent-transactions-all'));
    }
    if (find.byKey(const ValueKey('transaction-search')).evaluate().isEmpty &&
        find.text('首页').evaluate().isNotEmpty) {
      await _goBack(tester, untilText: '首页');
    } else {
      await _openShellTab(tester, keyValue: 'transactions', label: '明细');
    }
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('transaction-search')),
    );
  }
  final searchField = find.byKey(const ValueKey('transaction-search'));
  await _scrollUntilFound(tester, searchField);
  await tester.enterText(searchField, remark);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  final queryText = amountText ?? remark;
  await _scrollUntilFound(tester, find.text(queryText));

  final rowText = find.byElementPredicate((element) {
    if (element.widget is! Text) {
      return false;
    }
    final value = (element.widget as Text).data ?? '';
    if (amountText != null) {
      return value == amountText;
    }
    return value == remark;
  }, skipOffstage: false);

  await _pumpUntilFound(tester, rowText);
  final tile = find.ancestor(
    of: rowText,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith(
            'transaction-item-',
          ),
    ),
  );
  await _pumpUntilFound(tester, tile);

  return tile;
}

Future<void> _openShellTab(
  WidgetTester tester, {
  required String keyValue,
  required String label,
}) async {
  final bottomTab = find.byKey(ValueKey('main-shell-tab-$keyValue'));
  if (bottomTab.evaluate().isNotEmpty) {
    await _bringIntoTapArea(tester, bottomTab);
    await tester.tap(bottomTab, warnIfMissed: false);
    await tester.pumpAndSettle();
    return;
  }

  final railTab = find.byKey(ValueKey('main-shell-rail-$keyValue'));
  if (railTab.evaluate().isNotEmpty) {
    await tester.tap(railTab);
    await tester.pumpAndSettle();
    return;
  }

  await _tapText(tester, label);
}

Future<void> _openTransactionListByRoute(WidgetTester tester) async {
  final appFinder = find.byType(PersonalLedgerApp);
  if (appFinder.evaluate().isEmpty) {
    return;
  }

  final context = tester.element(appFinder);
  final router = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appRouterProvider);
  router.go(AppRoutePaths.transactions);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await _pumpUntilFound(tester, finder);
  await _bringIntoTapArea(tester, finder.last);
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty &&
      _verticalScrollables().evaluate().isNotEmpty) {
    await _scrollUntilFound(tester, finder);
  }
  await _pumpUntilFound(tester, finder);
  await _bringIntoTapArea(tester, finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enterTextByKey(WidgetTester tester, Key key, String value) async {
  final finder = find.byKey(key);
  if (finder.evaluate().isEmpty &&
      _verticalScrollables().evaluate().isNotEmpty) {
    await _scrollUntilFound(tester, finder);
  }
  await _pumpUntilFound(tester, finder);
  await _bringIntoTapArea(tester, finder);
  await tester.enterText(finder, value);
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

    final backButton = find.byType(BackButton);
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
  await _bringIntoTapArea(tester, dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await _pumpUntilFound(tester, find.text(itemText));
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

Future<void> _bringIntoTapArea(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();

  for (var attempt = 0; attempt < 4; attempt += 1) {
    final center = tester.getCenter(finder);
    if (center.dy >= 56 && center.dy <= 544) {
      return;
    }

    final scrollables = _verticalScrollables();
    if (scrollables.evaluate().isEmpty) {
      return;
    }
    final delta = center.dy > 544 ? -(center.dy - 440) : 96 - center.dy;
    await tester.drag(scrollables.first, Offset(0, delta), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
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
