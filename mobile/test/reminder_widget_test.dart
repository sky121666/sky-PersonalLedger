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

    testWidgets('新增提醒时提交核心表单字段', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('新增负债提醒'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '花呗');
      await tester.enterText(find.byType(TextFormField).at(1), '15');
      await tester.enterText(find.byType(TextFormField).at(3), '3000');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.name, '花呗');
      expect(repository.createCalls.single.paymentDay, 15);
      expect(repository.createCalls.single.principal, 3000);
      expect(repository.createCalls.single.currentBalance, 3000);
    });

    testWidgets('编辑提醒时提交更新表单', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '房贷调整');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.id, 'reminder-1');
      expect(repository.updateCalls.single.request.name, '房贷调整');
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

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeReminderRepository()..listErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('负债提醒加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('房贷'), findsOneWidget);
      expect(repository.listCalls, 2);
    });

    testWidgets('没有提醒时展示空态', (tester) async {
      final repository = _FakeReminderRepository()
        ..reminders = const []
        ..summary = const DebtSummary.empty();
      await _pumpPage(tester, repository);

      expect(find.text('暂无负债提醒'), findsOneWidget);
      expect(find.text('添加分期或还款计划后，可以在这里跟踪上岸进度。'), findsOneWidget);
      expect(find.text('¥0.00'), findsWidgets);
    });

    testWidgets('暂停提醒失败时展示错误且保留原状态', (tester) async {
      final repository = _FakeReminderRepository()..toggleError = '暂停失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂停提醒'));
      await tester.pumpAndSettle();

      expect(repository.toggleCalls, ['reminder-1']);
      expect(find.textContaining('暂停失败'), findsOneWidget);
      expect(find.text('提醒已暂停'), findsNothing);
      expect(find.text('进行中 (1)'), findsOneWidget);
      expect(find.text('房贷'), findsOneWidget);
    });

    testWidgets('记录还款失败时展示错误且保留待还金额', (tester) async {
      final repository = _FakeReminderRepository()..paymentError = '还款失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录还款'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '1200');
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(repository.paymentCalls, hasLength(1));
      expect(find.textContaining('还款失败'), findsOneWidget);
      expect(find.text('还款已记录'), findsNothing);
      expect(find.text('待还 ¥80000.00'), findsOneWidget);
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
  DebtSummary summary = const DebtSummary(
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
  final List<String> toggleCalls = [];
  final List<String> deleteCalls = [];
  final List<_PaymentCall> paymentCalls = [];
  final List<ReminderFormRequest> createCalls = [];
  final List<_UpdateCall> updateCalls = [];
  var listCalls = 0;
  var listErrors = 0;
  String? toggleError;
  String? paymentError;

  @override
  Future<ReminderItem?> createReminder(ReminderFormRequest request) async {
    createCalls.add(request);
    final item = _activeReminder(
      id: 'created-1',
      name: request.name,
      paymentDay: request.paymentDay,
      principal: request.principal,
      currentBalance: request.currentBalance,
    );
    reminders = [...reminders, item];
    return item;
  }

  @override
  Future<void> deleteReminder(String id) async {
    deleteCalls.add(id);
    reminders = reminders.where((item) => item.id != id).toList();
  }

  @override
  Future<DebtSummary?> getDebtSummary() async {
    return summary;
  }

  @override
  Future<List<ReminderItem>?> listReminders({String? accountId}) async {
    listCalls += 1;
    if (listErrors > 0) {
      listErrors -= 1;
      throw StateError('负债提醒加载失败');
    }
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
    final error = paymentError;
    if (error != null) {
      throw StateError(error);
    }
    return reminders.firstWhere((item) => item.id == id);
  }

  @override
  Future<ReminderItem?> toggleReminder(String id) async {
    toggleCalls.add(id);
    final error = toggleError;
    if (error != null) {
      throw StateError(error);
    }
    final old = reminders.firstWhere((item) => item.id == id);
    final updated = _activeReminder(isEnabled: !old.isEnabled);
    reminders = [updated];
    return updated;
  }

  @override
  Future<ReminderItem?> updateReminder(
    String id,
    ReminderFormRequest request,
  ) async {
    updateCalls.add(_UpdateCall(id: id, request: request));
    final updated = _activeReminder(id: id, name: request.name);
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

ReminderItem _activeReminder({
  String id = 'reminder-1',
  String name = '房贷',
  int paymentDay = 10,
  double? principal = 120000,
  double? currentBalance = 80000,
  bool isEnabled = true,
}) {
  return ReminderItem(
    id: id,
    name: name,
    accountId: 'loan-1',
    accountName: '贷款账户',
    loanType: 'mortgage',
    paymentDay: paymentDay,
    billingDay: null,
    advanceDays: 3,
    amount: 1000,
    principal: principal,
    currentBalance: currentBalance,
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

class _UpdateCall {
  const _UpdateCall({required this.id, required this.request});

  final String id;
  final ReminderFormRequest request;
}
