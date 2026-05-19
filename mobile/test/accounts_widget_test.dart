import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/accounts/presentation/accounts_page.dart';

void main() {
  group('AccountsPage', () {
    test('解析后端账户负债字段', () {
      final account = Account.fromJson({
        'id': 'mortgage',
        'name': '住房贷款',
        'type': 'mortgage',
        'icon': 'home',
        'color': '#EF4444',
        'initial_balance': 500000,
        'current_balance': 480000,
        'payment_day': 20,
        'billing_day': 1,
        'credit_limit': '800000',
        'interest_rate': 3.25,
        'total_paid': 20000,
        'start_date': '2026-01-01T00:00:00Z',
        'target_date': '2056-01-01T00:00:00Z',
        'remark': '首套房商贷',
        'is_archived': false,
        'sort_order': 2,
      });

      expect(account.paymentDay, 20);
      expect(account.billingDay, 1);
      expect(account.creditLimit, 800000);
      expect(account.interestRate, 3.25);
      expect(account.totalPaid, 20000);
      expect(account.startDate, '2026-01-01');
      expect(account.targetDate, '2056-01-01');
      expect(account.remark, '首套房商贷');
    });

    testWidgets('展示完整账户类型标签', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      expect(find.text('银行卡'), findsOneWidget);
      expect(find.text('房贷'), findsOneWidget);
      expect(find.text('Apple Pay'), findsOneWidget);
    });

    testWidgets('新增负债账户时提交负债字段', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增账户'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('account-name')), '房贷');
      await tester.tap(find.byKey(const ValueKey('account-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('房贷').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-initial-balance')),
        '500000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-payment-day')),
        '20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-billing-day')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-credit-limit')),
        '800000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-interest-rate')),
        '3.25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-start-date')),
        '2026-01-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-target-date')),
        '2056-01-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-remark')),
        '首套房商贷',
      );
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      final payload = repository.createCalls.single.toJson();
      expect(payload['type'], 'mortgage');
      expect(payload['initial_balance'], 500000);
      expect(payload['payment_day'], 20);
      expect(payload['billing_day'], 1);
      expect(payload['credit_limit'], 800000);
      expect(payload['interest_rate'], 3.25);
      expect(payload['start_date'], '2026-01-01');
      expect(payload['target_date'], '2056-01-01');
      expect(payload['remark'], '首套房商贷');
      expect(find.text('保存成功'), findsOneWidget);
    });

    testWidgets('编辑负债账户时保留负债字段', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-name')),
        '自住房贷款',
      );
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'mortgage');
      final payload = repository.updateCalls.single.$2.toJson();
      expect(payload['name'], '自住房贷款');
      expect(payload['payment_day'], 20);
      expect(payload['billing_day'], 1);
      expect(payload['credit_limit'], 800000);
      expect(payload['interest_rate'], 3.25);
      expect(payload['start_date'], '2026-01-01');
      expect(payload['target_date'], '2056-01-01');
      expect(payload['remark'], '首套房商贷');
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeAccountRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [accountRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: AccountsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAccountRepository implements AccountRepository {
  var accounts = <Account>[
    const Account(
      id: 'bank-card',
      name: '招商银行',
      type: 'bank_card',
      icon: '💳',
      color: '#3B82F6',
      initialBalance: 1000,
      currentBalance: 1200,
      isArchived: false,
      sortOrder: 1,
    ),
    const Account(
      id: 'mortgage',
      name: '住房贷款',
      type: 'mortgage',
      icon: '🏠',
      color: '#EF4444',
      initialBalance: 500000,
      currentBalance: 480000,
      paymentDay: 20,
      billingDay: 1,
      creditLimit: 800000,
      interestRate: 3.25,
      startDate: '2026-01-01',
      targetDate: '2056-01-01',
      remark: '首套房商贷',
      isArchived: false,
      sortOrder: 2,
    ),
    const Account(
      id: 'apple-pay',
      name: '手机钱包',
      type: 'apple_pay',
      icon: '📱',
      color: '#111827',
      initialBalance: 0,
      currentBalance: 300,
      isArchived: false,
      sortOrder: 3,
    ),
  ];

  final List<CreateAccountRequest> createCalls = [];
  final List<(String, UpdateAccountRequest)> updateCalls = [];
  final List<String> deleteCalls = [];
  final List<(String, bool)> archiveCalls = [];

  @override
  Future<void> archive(String id, bool isArchived) async {
    archiveCalls.add((id, isArchived));
    accounts = [
      for (final account in accounts)
        if (account.id == id)
          Account(
            id: account.id,
            name: account.name,
            type: account.type,
            icon: account.icon,
            color: account.color,
            initialBalance: account.initialBalance,
            currentBalance: account.currentBalance,
            paymentDay: account.paymentDay,
            billingDay: account.billingDay,
            creditLimit: account.creditLimit,
            interestRate: account.interestRate,
            totalPaid: account.totalPaid,
            startDate: account.startDate,
            targetDate: account.targetDate,
            paidOffAt: account.paidOffAt,
            remark: account.remark,
            isArchived: isArchived,
            sortOrder: account.sortOrder,
          )
        else
          account,
    ];
  }

  @override
  Future<Account> create(CreateAccountRequest request) async {
    createCalls.add(request);
    final account = Account(
      id: 'account-${accounts.length + 1}',
      name: request.name,
      type: request.type,
      icon: request.icon,
      color: request.color,
      initialBalance: request.initialBalance,
      currentBalance: request.initialBalance,
      isArchived: false,
      sortOrder: accounts.length + 1,
    );
    accounts = [...accounts, account];
    return account;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    accounts = accounts.where((account) => account.id != id).toList();
  }

  @override
  Future<Account> getById(String id) async {
    return accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<AccountListResult> list({bool includeArchived = true}) async {
    return AccountListResult(
      accounts: includeArchived
          ? accounts
          : accounts.where((account) => !account.isArchived).toList(),
      totalAssets: 1500,
      totalLiabilities: 480000,
      netAssets: -478500,
    );
  }

  @override
  Future<Account> update(String id, UpdateAccountRequest request) async {
    updateCalls.add((id, request));
    return accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<void> updateSort(List<String> ids) async {}
}
