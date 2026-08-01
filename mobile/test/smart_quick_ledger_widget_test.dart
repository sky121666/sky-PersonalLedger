import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_draft.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_repository.dart';
import 'package:personal_ledger/features/smart_quick_ledger/presentation/smart_quick_ledger_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';

void main() {
  group('SmartQuickLedgerPage', () {
    _testWidgetsOnPlatform('Android 展示通知来源白名单并支持切换', TargetPlatform.android, (
      tester,
    ) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);

      expect(find.text('智能快记'), findsOneWidget);
      expect(find.text('智能候选记账'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('smart-ledger-source-card')),
        findsOneWidget,
      );
      for (final source in ['wechat', 'alipay', 'bank', 'unionpay']) {
        expect(
          find.byKey(ValueKey('smart-ledger-source-$source')),
          findsOneWidget,
        );
      }
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('瑞幸咖啡'), findsOneWidget);
      expect(find.text('-¥38.90'), findsOneWidget);

      final unionpaySwitch = find.descendant(
        of: find.byKey(const ValueKey('smart-ledger-source-unionpay')),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(unionpaySwitch).value, isFalse);

      await tester.tap(find.text('云闪付'));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(unionpaySwitch).value, isTrue);
    });

    _testWidgetsOnPlatform(
      '建议 ID 缺失时必须显式选择账户和分类后才创建交易',
      TargetPlatform.android,
      (tester) async {
        final writer = _FakeQuickLedgerWriter();
        await _pumpPage(tester, writer);

        await _openConfirmationSheet(tester);

        expect(find.text('确认候选'), findsOneWidget);
        expect(writer.createCalls, isEmpty);
        final accountField = tester.widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: find.byKey(const ValueKey('smart-ledger-confirm-account')),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        );
        final categoryField = tester.widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: find.byKey(
              const ValueKey('smart-ledger-confirm-category-expense'),
            ),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        );
        expect(accountField.initialValue, isNull);
        expect(categoryField.initialValue, isNull);

        await _tapConfirmationSubmit(tester);

        expect(find.text('请选择账户'), findsOneWidget);
        expect(find.text('请选择分类'), findsOneWidget);
        expect(writer.createCalls, isEmpty);

        await _selectConfirmationDropdown(
          tester,
          fieldKey: const ValueKey('smart-ledger-confirm-account'),
          itemText: '微信钱包',
        );
        await _selectConfirmationDropdown(
          tester,
          fieldKey: const ValueKey('smart-ledger-confirm-category-expense'),
          itemText: '餐饮',
        );
        await _tapConfirmationSubmit(tester);
        await tester.pumpAndSettle();

        expect(writer.createCalls, hasLength(1));
        expect(writer.createCalls.single.amount, 38.9);
        expect(writer.createCalls.single.accountId, 'account-1');
        expect(writer.createCalls.single.categoryId, 'category-expense');
        expect(writer.createCalls.single.remark, '瑞幸咖啡');
        expect(find.text('瑞幸咖啡'), findsNothing);
        expect(find.text('已记入账本'), findsOneWidget);
      },
    );

    _testWidgetsOnPlatform('确认前可纠正方向金额备注日期账户和分类', TargetPlatform.android, (
      tester,
    ) async {
      final writer = _FakeQuickLedgerWriter(
        accounts: const [
          LedgerAccount(id: 'account-1', name: '微信钱包', type: 'cash'),
          LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank'),
        ],
        categories: const [
          LedgerCategory(id: 'category-expense', name: '餐饮', type: 'expense'),
          LedgerCategory(id: 'category-income', name: '工资', type: 'income'),
        ],
      );
      await _pumpPage(tester, writer);
      await _openConfirmationSheet(tester);

      await tester.tap(
        find.byKey(const ValueKey('smart-ledger-confirm-type-income')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('smart-ledger-confirm-amount')),
        '1,234.56',
      );
      await tester.enterText(
        find.byKey(const ValueKey('smart-ledger-confirm-remark')),
        '七月工资',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-account'),
        itemText: '储蓄卡',
      );
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-category-income'),
        itemText: '工资',
      );

      final targetDay = DateTime.now().day == 15 ? 16 : 15;
      final dateButton = find.byKey(
        const ValueKey('smart-ledger-confirm-date'),
      );
      await tester.ensureVisible(dateButton);
      await tester.tap(dateButton);
      await tester.pumpAndSettle();
      final day = find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('$targetDay'),
      );
      expect(day, findsOneWidget);
      await tester.tap(day);
      await tester.tap(
        find
            .descendant(
              of: find.byType(DatePickerDialog),
              matching: find.byType(TextButton),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(TimePickerDialog),
              matching: find.byType(TextButton),
            )
            .last,
      );
      await tester.pumpAndSettle();

      await _tapConfirmationSubmit(tester);
      await tester.pumpAndSettle();

      expect(writer.createCalls, hasLength(1));
      final formData = writer.createCalls.single;
      expect(formData.type, TransactionType.income);
      expect(formData.amount, 1234.56);
      expect(formData.remark, '七月工资');
      expect(formData.transactionDate.day, targetDay);
      expect(formData.accountId, 'account-2');
      expect(formData.categoryId, 'category-income');
      expect(formData.tags, ['通知']);
    });

    _testWidgetsOnPlatform('账户在提交前归档时展示明确错误且不创建交易', TargetPlatform.android, (
      tester,
    ) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);
      await _openConfirmationSheet(tester);
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-account'),
        itemText: '微信钱包',
      );
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-category-expense'),
        itemText: '餐饮',
      );
      writer.accounts = const [
        LedgerAccount(
          id: 'account-1',
          name: '微信钱包',
          type: 'cash',
          isArchived: true,
        ),
      ];

      await _tapConfirmationSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('所选账户不可用或已归档'), findsOneWidget);
      expect(writer.createCalls, isEmpty);
      expect(find.text('瑞幸咖啡'), findsOneWidget);
    });

    _testWidgetsOnPlatform('分类方向在提交前变化时展示明确错误且不创建交易', TargetPlatform.android, (
      tester,
    ) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);
      await _openConfirmationSheet(tester);
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-account'),
        itemText: '微信钱包',
      );
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-category-expense'),
        itemText: '餐饮',
      );
      writer.categories = const [
        LedgerCategory(id: 'category-expense', name: '餐饮', type: 'income'),
      ];

      await _tapConfirmationSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text('分类与收支方向不匹配'), findsOneWidget);
      expect(writer.createCalls, isEmpty);
      expect(find.text('瑞幸咖啡'), findsOneWidget);
    });

    _testWidgetsOnPlatform('忽略候选会从队列移除', TargetPlatform.android, (
      tester,
    ) async {
      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer);

      final dismissButton = find.text('忽略').first;
      await tester.scrollUntilVisible(dismissButton, 120);
      await tester.tap(dismissButton);
      await tester.pumpAndSettle();

      expect(find.text('瑞幸咖啡'), findsNothing);
      expect(writer.createCalls, isEmpty);
    });

    _testWidgetsOnPlatform('iOS 无通知来源入口且粘贴文本确认后真实创建交易', TargetPlatform.iOS, (
      tester,
    ) async {
      const clipboardText = '微信支付 商户：瑞幸咖啡 付款 38.90 元，余额 1,234.56 元';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardText};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final writer = _FakeQuickLedgerWriter();
      await _pumpPage(tester, writer, initialDrafts: const []);

      expect(find.text('粘贴导入可用'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('smart-ledger-source-card')),
        findsNothing,
      );
      expect(find.text('通知来源'), findsNothing);
      expect(writer.createCalls, isEmpty);

      final openImport = find.byKey(const ValueKey('smart-ledger-open-import'));
      await tester.scrollUntilVisible(openImport, 120);
      await tester.tap(openImport);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('smart-ledger-paste-clipboard')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('smart-ledger-import-text-field')),
            )
            .controller
            ?.text,
        clipboardText,
      );
      await tester.tap(
        find.byKey(const ValueKey('smart-ledger-create-candidate')),
      );
      await tester.pumpAndSettle();

      expect(find.text('已生成待确认候选'), findsOneWidget);
      expect(find.text('瑞幸咖啡'), findsOneWidget);
      expect(find.text('-¥38.90'), findsOneWidget);
      expect(writer.createCalls, isEmpty);

      await _openConfirmationSheet(tester, button: find.text('确认'));
      expect(writer.createCalls, isEmpty);
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-account'),
        itemText: '微信钱包',
      );
      await _selectConfirmationDropdown(
        tester,
        fieldKey: const ValueKey('smart-ledger-confirm-category-expense'),
        itemText: '餐饮',
      );
      await _tapConfirmationSubmit(tester);
      await tester.pumpAndSettle();

      expect(writer.createCalls, hasLength(1));
      final formData = writer.createCalls.single;
      expect(formData.type, TransactionType.expense);
      expect(formData.amount, 38.9);
      expect(formData.accountId, 'account-1');
      expect(formData.categoryId, 'category-expense');
      expect(formData.remark, '瑞幸咖啡');
      expect(formData.tags, ['粘贴导入']);
      expect(find.text('瑞幸咖啡'), findsNothing);
      expect(find.text('已记入账本'), findsOneWidget);
    });
  });

  group('QuickLedgerDraftController', () {
    test('confirm 拒绝归档账户并保留候选', () async {
      final writer = _FakeQuickLedgerWriter(
        accounts: const [
          LedgerAccount(
            id: 'account-1',
            name: '已归档钱包',
            type: 'cash',
            isArchived: true,
          ),
        ],
      );
      final draft = _sampleDrafts().first;
      final controller = QuickLedgerDraftController(
        transactionWriter: writer,
        initialDrafts: [draft],
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.confirm(
          draft.id,
          TransactionFormData(
            type: TransactionType.expense,
            amount: 38.9,
            accountId: 'account-1',
            categoryId: 'category-expense',
            transactionDate: draft.occurredAt,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '所选账户不可用或已归档',
          ),
        ),
      );

      expect(writer.createCalls, isEmpty);
      expect(controller.state, [draft]);
    });

    test('confirm 拒绝与收支方向不匹配的分类', () async {
      final writer = _FakeQuickLedgerWriter();
      final draft = _sampleDrafts().first;
      final controller = QuickLedgerDraftController(
        transactionWriter: writer,
        initialDrafts: [draft],
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.confirm(
          draft.id,
          TransactionFormData(
            type: TransactionType.income,
            amount: 38.9,
            accountId: 'account-1',
            categoryId: 'category-expense',
            transactionDate: draft.occurredAt,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '分类与收支方向不匹配',
          ),
        ),
      );

      expect(writer.createCalls, isEmpty);
      expect(controller.state, [draft]);
    });
  });
}

void _testWidgetsOnPlatform(
  String description,
  TargetPlatform platform,
  WidgetTesterCallback callback,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _openConfirmationSheet(
  WidgetTester tester, {
  Finder? button,
}) async {
  final target =
      button ??
      find.byKey(const ValueKey('smart-ledger-confirm-draft-wechat-coffee'));
  await tester.scrollUntilVisible(target, 120);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tapConfirmationSubmit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('smart-ledger-confirm-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Future<void> _selectConfirmationDropdown(
  WidgetTester tester, {
  required Key fieldKey,
  required String itemText,
}) async {
  final field = find.byKey(fieldKey);
  await tester.ensureVisible(field);
  await tester.tap(
    find.descendant(
      of: field,
      matching: find.byType(DropdownButtonFormField<String>),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeQuickLedgerWriter writer, {
  List<QuickLedgerDraft>? initialDrafts,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickLedgerDraftsProvider.overrideWith(
          (ref) => QuickLedgerDraftController(
            transactionWriter: writer,
            initialDrafts: initialDrafts ?? _sampleDrafts(),
          ),
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

List<QuickLedgerDraft> _sampleDrafts() {
  final now = DateTime.now();
  return [
    QuickLedgerDraft(
      id: 'draft-wechat-coffee',
      source: QuickLedgerDraftSource.androidNotification,
      sourceName: '微信支付',
      type: TransactionType.expense,
      amount: 38.9,
      merchant: '瑞幸咖啡',
      occurredAt: DateTime(now.year, now.month, now.day, 9, 18),
      confidence: 0.92,
      suggestedAccountName: '微信钱包',
      suggestedCategoryName: '餐饮',
      rawText: '微信支付收款方 瑞幸咖啡 ¥38.90',
      notificationHash: 'wechat-coffee-3890',
    ),
    QuickLedgerDraft(
      id: 'draft-alipay-transport',
      source: QuickLedgerDraftSource.androidNotification,
      sourceName: '支付宝',
      type: TransactionType.expense,
      amount: 12,
      merchant: '地铁出行',
      occurredAt: DateTime(now.year, now.month, now.day, 8, 42),
      confidence: 0.88,
      suggestedAccountName: '支付宝',
      suggestedCategoryName: '交通',
      rawText: '支付宝付款 地铁出行 12.00元',
      notificationHash: 'alipay-transport-1200',
    ),
  ];
}

class _FakeQuickLedgerWriter implements QuickLedgerTransactionWriter {
  _FakeQuickLedgerWriter({
    List<LedgerAccount>? accounts,
    List<LedgerCategory>? categories,
  }) : accounts =
           accounts ??
           const [LedgerAccount(id: 'account-1', name: '微信钱包', type: 'cash')],
       categories =
           categories ??
           const [
             LedgerCategory(
               id: 'category-expense',
               name: '餐饮',
               type: 'expense',
             ),
           ];

  final List<TransactionFormData> createCalls = [];
  List<LedgerAccount> accounts;
  List<LedgerCategory> categories;

  @override
  Future<List<LedgerAccount>> listAccounts() async => accounts;

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    return type == null
        ? categories
        : categories.where((category) => category.type == type).toList();
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
