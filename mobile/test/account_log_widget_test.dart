import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/account_logs/data/account_log_repository.dart';
import 'package:personal_ledger/features/account_logs/presentation/account_log_page.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';

void main() {
  group('AccountLogPage', () {
    testWidgets('展示账户摘要和账户流水', (tester) async {
      final repository = _FakeAccountLogRepository();
      await _pumpPage(
        tester,
        repository,
        accountId: 'account-cash',
        account: _account(),
      );

      expect(find.text('现金流水'), findsOneWidget);
      expect(find.text('当前余额 ¥1280.00'), findsOneWidget);
      expect(find.text('收入'), findsOneWidget);
      expect(find.text('+¥500.00'), findsOneWidget);
      expect(find.text('工资入账'), findsOneWidget);
    });

    testWidgets('全量流水展示账户名称并支持加载更多', (tester) async {
      final repository = _FakeAccountLogRepository(
        pages: {
          1: AccountLogListResult(
            list: [_log(id: 'log-1', account: _account())],
            total: 2,
            page: 1,
            pageSize: 1,
          ),
          2: AccountLogListResult(
            list: [
              _log(
                id: 'log-2',
                type: AccountLogType.expense,
                balanceBefore: 1280,
                balanceAfter: 1200,
                remark: '午餐',
                account: _account(),
              ),
            ],
            total: 2,
            page: 2,
            pageSize: 1,
          ),
        },
      );
      await _pumpPage(tester, repository);

      expect(find.text('账户流水'), findsOneWidget);
      expect(find.text('现金'), findsOneWidget);
      expect(find.text('加载更多'), findsOneWidget);

      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();

      expect(repository.listPages, [1, 2]);
      expect(find.text('支出'), findsOneWidget);
      expect(find.text('-¥80.00'), findsOneWidget);
      expect(find.text('午餐'), findsOneWidget);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeAccountLogRepository()..listErrors = {1: 1};
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('流水加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.listPages, [1, 1]);
      expect(find.text('工资入账'), findsOneWidget);
    });

    testWidgets('没有流水时展示空状态', (tester) async {
      final repository = _FakeAccountLogRepository(
        pages: {1: AccountLogListResult.empty()},
      );
      await _pumpPage(tester, repository);

      expect(find.text('暂无流水记录'), findsOneWidget);
      expect(find.text('交易、还款或余额调整后会自动生成账户流水。'), findsOneWidget);
    });

    testWidgets('加载更多失败时展示错误且保留已有流水', (tester) async {
      final repository = _FakeAccountLogRepository(
        pages: {
          1: AccountLogListResult(
            list: [_log(id: 'log-1', account: _account())],
            total: 2,
            page: 1,
            pageSize: 1,
          ),
        },
      )..listErrors = {2: 1};
      await _pumpPage(tester, repository);

      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();

      expect(repository.listPages, [1, 2]);
      expect(find.textContaining('流水加载失败'), findsOneWidget);
      expect(find.text('工资入账'), findsOneWidget);
      expect(find.text('加载更多'), findsOneWidget);
    });

    testWidgets('刷新后恢复为最新流水列表', (tester) async {
      final repository = _FakeAccountLogRepository(
        pageSequences: {
          1: [
            AccountLogListResult(
              list: [_log(id: 'log-1', account: _account())],
              total: 1,
              page: 1,
              pageSize: 50,
            ),
            AccountLogListResult(
              list: [
                _log(
                  id: 'log-2',
                  type: AccountLogType.expense,
                  balanceBefore: 1280,
                  balanceAfter: 1200,
                  remark: '午餐',
                  account: _account(),
                ),
              ],
              total: 1,
              page: 1,
              pageSize: 50,
            ),
          ],
        },
      );
      await _pumpPage(tester, repository);

      expect(find.text('工资入账'), findsOneWidget);

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();

      expect(repository.listPages, [1, 1]);
      expect(find.text('工资入账'), findsNothing);
      expect(find.text('午餐'), findsOneWidget);
      expect(find.text('-¥80.00'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeAccountLogRepository repository, {
  String? accountId,
  Account? account,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [accountLogRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: AccountLogPage(accountId: accountId, account: account),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAccountLogRepository implements AccountLogRepository {
  _FakeAccountLogRepository({
    Map<int, AccountLogListResult>? pages,
    Map<int, List<AccountLogListResult>>? pageSequences,
  })
    : pages =
          pages ??
          {
            1: AccountLogListResult(
              list: [_log(account: _account())],
              total: 1,
              page: 1,
              pageSize: 50,
            ),
          },
      pageSequences = pageSequences ?? const {};

  final Map<int, AccountLogListResult> pages;
  final Map<int, List<AccountLogListResult>> pageSequences;
  final List<int> listPages = [];
  final List<int> accountPages = [];
  Map<int, int> listErrors = const {};
  final Map<int, int> _sequenceIndexes = {};

  @override
  Future<AccountLogListResult> list({int page = 1, int pageSize = 50}) async {
    listPages.add(page);
    _throwIfConfigured(page);
    final sequence = pageSequences[page];
    if (sequence != null && sequence.isNotEmpty) {
      final index = _sequenceIndexes[page] ?? 0;
      _sequenceIndexes[page] = index + 1;
      return sequence[index.clamp(0, sequence.length - 1)];
    }
    return pages[page] ?? AccountLogListResult.empty(page: page);
  }

  @override
  Future<AccountLogListResult> listByAccountId(
    String accountId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    accountPages.add(page);
    _throwIfConfigured(page);
    return pages[page] ?? AccountLogListResult.empty(page: page);
  }

  void _throwIfConfigured(int page) {
    final remaining = listErrors[page] ?? 0;
    if (remaining <= 0) {
      return;
    }
    listErrors = {...listErrors, page: remaining - 1};
    throw StateError('流水加载失败');
  }
}

Account _account() {
  return const Account(
    id: 'account-cash',
    name: '现金',
    type: 'cash',
    icon: '💰',
    color: '#10B981',
    initialBalance: 1000,
    currentBalance: 1280,
    isArchived: false,
    sortOrder: 1,
  );
}

AccountLogItem _log({
  String id = 'log-1',
  AccountLogType type = AccountLogType.income,
  double balanceBefore = 780,
  double balanceAfter = 1280,
  String remark = '工资入账',
  Account? account,
}) {
  return AccountLogItem(
    id: id,
    accountId: 'account-cash',
    type: type,
    amount: (balanceAfter - balanceBefore).abs(),
    balanceBefore: balanceBefore,
    balanceAfter: balanceAfter,
    createdAt: DateTime(2026, 5, 1, 9),
    remark: remark,
    account: account,
  );
}
