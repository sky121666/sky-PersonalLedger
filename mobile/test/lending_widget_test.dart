import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/lendings/data/lending_repository.dart';
import 'package:personal_ledger/features/lendings/presentation/lending_page.dart';

void main() {
  group('LendingPage', () {
    testWidgets('展示借贷汇总和进行中的借出记录', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      expect(find.text('借贷往来'), findsOneWidget);
      expect(find.text('应收'), findsOneWidget);
      expect(find.text('¥1,200.00'), findsOneWidget);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('剩余 ¥800.00'), findsOneWidget);
    });

    testWidgets('新增借出记录时提交联系人和本金', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await tester.tap(find.byKey(const ValueKey('lending-add-lend-out')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lending-contact-name')),
        '王五',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lending-principal')),
        '500',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(lendingRepository.createCalls, hasLength(1));
      expect(lendingRepository.createCalls.single.type, LendingType.lendOut);
      expect(lendingRepository.createCalls.single.contactName, '王五');
      expect(lendingRepository.createCalls.single.principal, 500);
    });

    testWidgets('记录还款时提交还款金额', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await tester.tap(find.byTooltip('记录还款').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lending-repayment-amount')),
        '300',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(lendingRepository.repaymentCalls, hasLength(1));
      expect(lendingRepository.repaymentCalls.single.id, 'lend-1');
      expect(lendingRepository.repaymentCalls.single.request.amount, 300);
    });

    testWidgets('删除借贷记录前需要确认', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await tester.tap(find.byTooltip('删除借贷记录').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(lendingRepository.deleteCalls, ['lend-1']);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeLendingRepository lendingRepository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lendingRepositoryProvider.overrideWithValue(lendingRepository),
        accountRepositoryProvider.overrideWithValue(_FakeAccountRepository()),
      ],
      child: const MaterialApp(home: LendingPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeLendingRepository implements LendingRepository {
  List<LendingItem> lendings = [
    LendingItem(
      id: 'lend-1',
      type: LendingType.lendOut,
      contactName: '张三',
      principal: 1000,
      currentBalance: 800,
      totalRepaid: 200,
      lendDate: DateTime(2026, 5, 1, 9),
      dueDate: DateTime(2026, 6, 1, 9),
      remark: '朋友周转',
    ),
    LendingItem(
      id: 'borrow-1',
      type: LendingType.borrowIn,
      contactName: '李四',
      principal: 500,
      currentBalance: 400,
      totalRepaid: 100,
      lendDate: DateTime(2026, 5, 2, 9),
    ),
  ];

  LendingSummary summary = const LendingSummary(
    totalLendOut: 1000,
    totalBorrowIn: 500,
    activeLendOut: 1,
    activeBorrowIn: 1,
    settledLendOut: 0,
    settledBorrowIn: 0,
    totalReceivable: 1200,
    totalPayable: 400,
    netLending: 800,
  );

  final List<CreateLendingRequest> createCalls = [];
  final List<_RepaymentCall> repaymentCalls = [];
  final List<String> deleteCalls = [];

  @override
  Future<LendingItem?> create(CreateLendingRequest request) async {
    createCalls.add(request);
    final item = LendingItem(
      id: 'lend-new',
      type: request.type,
      contactName: request.contactName,
      principal: request.principal,
      currentBalance: request.principal,
      totalRepaid: 0,
      lendDate: DateTime.parse(request.lendDate),
      remark: request.remark,
    );
    lendings = [...lendings, item];
    return item;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    lendings = lendings.where((item) => item.id != id).toList();
  }

  @override
  Future<List<LendingItem>?> list({bool includeSettled = false}) async {
    return lendings;
  }

  @override
  Future<LendingItem?> recordRepayment(
    String id,
    RecordRepaymentRequest request,
  ) async {
    repaymentCalls.add(_RepaymentCall(id, request));
    return lendings.firstWhere((item) => item.id == id);
  }

  @override
  Future<LendingSummary?> summaryOverview() async {
    return summary;
  }

  @override
  Future<LendingItem?> update(String id, UpdateLendingRequest request) async {
    return lendings.firstWhere((item) => item.id == id);
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
          id: 'cash',
          name: '现金',
          type: 'cash',
          icon: 'cash',
          color: '#3B82F6',
          initialBalance: 1000,
          currentBalance: 1000,
          isArchived: false,
          sortOrder: 1,
        ),
      ],
      totalAssets: 1000,
      totalLiabilities: 0,
      netAssets: 1000,
    );
  }

  @override
  Future<Account> update(String id, UpdateAccountRequest request) {
    throw UnimplementedError();
  }
}

class _RepaymentCall {
  const _RepaymentCall(this.id, this.request);

  final String id;
  final RecordRepaymentRequest request;
}
