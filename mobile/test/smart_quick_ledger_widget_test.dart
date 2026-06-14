import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_repository.dart';
import 'package:personal_ledger/features/smart_quick_ledger/presentation/smart_quick_ledger_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';

void main() {
  group('SmartQuickLedgerPage', () {
    testWidgets('展示智能快记能力、来源和待确认候选', (tester) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);

      expect(find.text('智能快记'), findsOneWidget);
      expect(find.text('智能候选记账'), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('iOS'), findsOneWidget);
      expect(find.text('通知来源'), findsOneWidget);
      expect(find.text('微信支付'), findsOneWidget);
      expect(find.text('支付宝'), findsOneWidget);
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('瑞幸咖啡'), findsOneWidget);
      expect(find.text('-¥38.90'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('smart-ledger-shortcut-card')),
        120,
      );
      expect(
        find.byKey(const ValueKey('smart-ledger-shortcut-card')),
        findsOneWidget,
      );
    });

    testWidgets('通知来源白名单可切换', (tester) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);

      final unionpaySwitch = find.descendant(
        of: find.byKey(const ValueKey('smart-ledger-source-unionpay')),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(unionpaySwitch).value, isFalse);

      await tester.tap(find.text('云闪付'));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(unionpaySwitch).value, isTrue);
    });

    testWidgets('确认候选会创建交易并移除草稿', (tester) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);

      final confirmButton = find.byKey(
        const ValueKey('smart-ledger-confirm-draft-wechat-coffee'),
      );
      await tester.scrollUntilVisible(confirmButton, 120);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(writer.createCalls, hasLength(1));
      expect(writer.createCalls.single.amount, 38.9);
      expect(writer.createCalls.single.accountId, 'account-1');
      expect(writer.createCalls.single.categoryId, 'category-expense');
      expect(writer.createCalls.single.remark, '瑞幸咖啡');
      expect(find.text('瑞幸咖啡'), findsNothing);
      expect(find.text('已记入账本'), findsOneWidget);
    });

    testWidgets('忽略候选会从队列移除', (tester) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);

      final dismissButton = find.text('忽略').first;
      await tester.scrollUntilVisible(dismissButton, 120);
      await tester.tap(dismissButton);
      await tester.pumpAndSettle();

      expect(find.text('瑞幸咖啡'), findsNothing);
      expect(writer.createCalls, isEmpty);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeQuickLedgerWriter writer,
) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickLedgerDraftsProvider.overrideWith(
          (ref) => QuickLedgerDraftController(transactionWriter: writer),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(AppThemePalette.teal),
        home: const SmartQuickLedgerPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeQuickLedgerWriter implements QuickLedgerTransactionWriter {
  final List<TransactionFormData> createCalls = [];

  @override
  Future<List<LedgerAccount>> listAccounts() async {
    return const [LedgerAccount(id: 'account-1', name: '微信钱包', type: 'cash')];
  }

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    return const [
      LedgerCategory(id: 'category-expense', name: '餐饮', type: 'expense'),
    ];
  }

  @override
  Future<TransactionItem> create(TransactionFormData formData) async {
    createCalls.add(formData);
    return TransactionItem(
      id: 'transaction-${createCalls.length}',
      type: formData.type,
      amount: formData.amount,
      accountId: formData.accountId,
      categoryId: formData.categoryId,
      transactionDate: formData.transactionDate,
      remark: formData.remark,
      tags: formData.tags,
    );
  }
}
