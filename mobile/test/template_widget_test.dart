import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/templates/data/template_repository.dart';
import 'package:personal_ledger/features/templates/presentation/template_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';

void main() {
  group('TemplatePage', () {
    testWidgets('展示快捷模板列表和使用次数', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpPage(tester, repository);

      expect(find.text('快捷模板'), findsOneWidget);
      expect(find.text('午餐'), findsOneWidget);
      expect(find.text('支出 · 现金 · 餐饮'), findsOneWidget);
      expect(find.text('已用 3 次'), findsOneWidget);
    });

    testWidgets('新增模板时提交表单字段并刷新列表', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增模板'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('template-name')), '咖啡');
      await tester.enterText(
        find.byKey(const ValueKey('template-amount')),
        '18.5',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await tester.enterText(
        find.byKey(const ValueKey('template-remark')),
        '下午咖啡',
      );
      await tester.tap(find.byKey(const ValueKey('template-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.name, '咖啡');
      expect(repository.createCalls.single.amount, 18.5);
      expect(repository.createCalls.single.accountId, 'account-1');
      expect(repository.createCalls.single.categoryId, 'category-expense');
      expect(repository.createCalls.single.remark, '下午咖啡');
      expect(find.text('咖啡'), findsOneWidget);
      expect(find.text('模板已保存'), findsOneWidget);
    });

    testWidgets('套用模板时创建交易并刷新模板', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('套用'));
      await tester.pumpAndSettle();

      expect(repository.applyCalls, hasLength(1));
      expect(repository.applyCalls.single.$1, 'tpl-1');
      expect(repository.applyCalls.single.$2.transactionDate, isNotNull);
      expect(find.text('已按模板记账'), findsOneWidget);
      expect(find.text('已用 4 次'), findsOneWidget);
    });

    testWidgets('删除模板前需要确认', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('删除模板'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['tpl-1']);
      expect(find.text('午餐'), findsNothing);
      expect(find.text('模板已删除'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeTemplateRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [templateRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: TemplatePage()),
    ),
  );
  await tester.pumpAndSettle();
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
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

class _FakeTemplateRepository implements TemplateRepository {
  var templates = <QuickTemplateItem>[
    const QuickTemplateItem(
      id: 'tpl-1',
      name: '午餐',
      type: TransactionType.expense,
      amount: 32,
      accountId: 'account-1',
      categoryId: 'category-expense',
      remark: '工作日午餐',
      usedCount: 3,
    ),
  ];

  final List<QuickTemplateRequest> createCalls = [];
  final List<(String, ApplyTemplateRequest)> applyCalls = [];
  final List<String> deleteCalls = [];

  @override
  Future<TransactionItem> apply(String id, ApplyTemplateRequest request) async {
    applyCalls.add((id, request));
    final template = templates.firstWhere((item) => item.id == id);
    templates = [
      for (final item in templates)
        item.id == id
            ? QuickTemplateItem(
                id: item.id,
                name: item.name,
                type: item.type,
                amount: item.amount,
                accountId: item.accountId,
                categoryId: item.categoryId,
                remark: item.remark,
                usedCount: item.usedCount + 1,
              )
            : item,
    ];
    return TransactionItem(
      id: 'tx-1',
      type: template.type,
      amount: template.amount,
      accountId: template.accountId,
      categoryId: template.categoryId,
      transactionDate: request.transactionDate ?? DateTime(2026, 5, 18),
      remark: template.remark,
    );
  }

  @override
  Future<QuickTemplateItem> create(QuickTemplateRequest request) async {
    createCalls.add(request);
    final template = QuickTemplateItem(
      id: 'tpl-${templates.length + 1}',
      name: request.name,
      type: request.type,
      amount: request.amount,
      accountId: request.accountId,
      categoryId: request.categoryId,
      remark: request.remark,
    );
    templates = [...templates, template];
    return template;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    templates = templates.where((item) => item.id != id).toList();
  }

  @override
  Future<List<LedgerAccount>> listAccounts() async {
    return const [
      LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
      LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank_card'),
    ];
  }

  @override
  Future<List<LedgerCategory>> listCategories() async {
    return const [
      LedgerCategory(id: 'category-expense', name: '餐饮', type: 'expense'),
      LedgerCategory(id: 'category-income', name: '工资', type: 'income'),
    ];
  }

  @override
  Future<List<QuickTemplateItem>> list() async {
    return templates;
  }
}
