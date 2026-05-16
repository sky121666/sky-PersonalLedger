import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/reminders/data/reminder_repository.dart';
import 'package:personal_ledger/features/reminders/presentation/reminder_page.dart';

void main() {
  group('ReminderPage', () {
    testWidgets('展示上岸进度和进行中的负债提醒', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      expect(find.text('负债管理'), findsOneWidget);
      expect(find.text('上岸进度'), findsOneWidget);
      expect(find.text('房贷'), findsOneWidget);
      expect(find.text('待还 ¥80000.00'), findsOneWidget);
    });

    testWidgets('菜单中可以暂停提醒', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂停提醒'));
      await tester.pumpAndSettle();

      expect(repository.toggleCalls, ['reminder-1']);
    });

    testWidgets('记录还款时提交还款金额和账户', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录还款'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '1200');
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(repository.paymentCalls, hasLength(1));
      expect(repository.paymentCalls.single.id, 'reminder-1');
      expect(repository.paymentCalls.single.amount, 1200);
      expect(repository.paymentCalls.single.accountId, 'cash-1');
    });

    testWidgets('删除提醒前需要确认', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['reminder-1']);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeReminderRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reminderRepositoryProvider.overrideWithValue(repository),
        accountRepositoryProvider.overrideWithValue(_FakeAccountRepository()),
      ],
      child: const MaterialApp(home: ReminderPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeReminderRepository implements ReminderRepository {
  List<ReminderItem> reminders = [_activeReminder()];
  final List<String> toggleCalls = [];
  final List<String> deleteCalls = [];
  final List<_PaymentCall> paymentCalls = [];

  @override
  Future<void> deleteReminder(String id) async {
    deleteCalls.add(id);
    reminders = reminders.where((item) => item.id != id).toList();
  }

  @override
  Future<DebtSummary?> getDebtSummary() async {
    return const DebtSummary(
      totalDebt: 80000,
      totalPaid: 40000,
      totalPrincipal: 120000,
      progress: 33.3,
      activeLoans: 1,
      paidOffLoans: 0,
      nextPaymentDay: 10,
      nextPaymentName: '房贷',
      daysUntilNext: 3,
    );
  }

  @override
  Future<List<ReminderItem>?> listReminders({String? accountId}) async {
    return reminders;
  }

  @override
  Future<ReminderItem?> recordPayment(
    String id, {
    required double amount,
    String? accountId,
    double? principalAmount,
    double? interestAmount,
  }) async {
    paymentCalls.add(
      _PaymentCall(
        id: id,
        amount: amount,
        accountId: accountId,
        principalAmount: principalAmount,
        interestAmount: interestAmount,
      ),
    );
    return reminders.firstWhere((item) => item.id == id);
  }

  @override
  Future<ReminderItem?> toggleReminder(String id) async {
    toggleCalls.add(id);
    final old = reminders.firstWhere((item) => item.id == id);
    final updated = _activeReminder(isEnabled: !old.isEnabled);
    reminders = [updated];
    return updated;
  }
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<void> archive(String id, bool isArchived) {
    throw UnimplementedError();
  }

  @override
  Future<Account> create(CreateAccountRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<AccountListResult> list({bool includeArchived = true}) async {
    return const AccountListResult(
      accounts: [
        Account(
          id: 'cash-1',
          name: '储蓄卡',
          type: 'debit',
          icon: '💳',
          color: '#3B82F6',
          initialBalance: 10000,
          currentBalance: 8000,
          isArchived: false,
          sortOrder: 1,
        ),
      ],
      totalAssets: 8000,
      totalLiabilities: 0,
      netAssets: 8000,
    );
  }

  @override
  Future<Account> update(String id, UpdateAccountRequest request) {
    throw UnimplementedError();
  }
}

ReminderItem _activeReminder({bool isEnabled = true}) {
  return ReminderItem(
    id: 'reminder-1',
    name: '房贷',
    accountId: 'loan-1',
    accountName: '贷款账户',
    loanType: 'mortgage',
    paymentDay: 10,
    billingDay: null,
    advanceDays: 3,
    amount: 1000,
    principal: 120000,
    currentBalance: 80000,
    interestRate: null,
    totalInterest: null,
    totalPaid: 40000,
    interestPaid: 0,
    startDate: null,
    targetDate: null,
    paidOffAt: null,
    color: '#3B82F6',
    remark: '',
    isEnabled: isEnabled,
  );
}

class _PaymentCall {
  const _PaymentCall({
    required this.id,
    required this.amount,
    this.accountId,
    this.principalAmount,
    this.interestAmount,
  });

  final String id;
  final double amount;
  final String? accountId;
  final double? principalAmount;
  final double? interestAmount;
}
