import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
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
      expect(find.text('套用'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('template-execution-matrix-tpl-1')),
        findsNothing,
      );
      expect(find.text('模板执行矩阵'), findsNothing);
      expect(find.text('交易方向'), findsNothing);
      expect(find.text('账户通道'), findsNothing);
      expect(find.text('分类节点'), findsNothing);
    });

    testWidgets('快捷模板列表保持清晰层级', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(1));
      expect(find.text('快捷模板'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('template-apply-tpl-1')),
        findsOneWidget,
      );
    });

    testWidgets('快捷模板页不展示复用效率和说明头部', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpPage(tester, repository);

      expect(find.text('快捷模板库'), findsNothing);
      expect(find.text('把高频收支做成可复用模板，减少重复录入。'), findsNothing);
      expect(find.text('模板数'), findsNothing);
      expect(find.text('累计使用'), findsNothing);
      expect(find.text('可用账户'), findsNothing);
      expect(find.text('复用效率雷达'), findsNothing);
      expect(find.text('平均复用'), findsNothing);
      expect(find.byKey(const ValueKey('template-reuse-radar')), findsNothing);
      expect(find.text('模板执行流水线'), findsNothing);
      expect(
        find.byKey(const ValueKey('template-automation-strip')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('template-orchestration-panel')),
        findsNothing,
      );
      expect(find.text('模板编排面板'), findsNothing);
      expect(find.text('高频自动化'), findsNothing);
      expect(
        find.byKey(const ValueKey('template-execution-evidence-pill')),
        findsNothing,
      );
    });

    testWidgets('新增模板时提交表单字段并刷新列表', (tester) async {
      final repository = _FakeTemplateRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('新增模板'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('template-name')), '咖啡');
      await tester.enterText(
        find.byKey(const ValueKey('template-amount')),
        '18.5',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      expect(
        find.byTooltip('添加备注'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('template-remark')), findsNothing);
      await tester.tap(find.byTooltip('添加备注'));
      await tester.pumpAndSettle();
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

      expect(find.byTooltip('套用模板 午餐'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('template-apply-tpl-1')));
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

      final menuBox = tester.getSize(
        find
            .ancestor(
              of: find.byTooltip('更多模板操作 午餐'),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(menuBox.width, greaterThanOrEqualTo(44));
      expect(menuBox.height, greaterThanOrEqualTo(44));

      await tester.tap(find.byTooltip('更多模板操作 午餐'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除「午餐」？'), findsOneWidget);
      expect(find.text('已记交易不变。'), findsNothing);
      expect(find.text('历史交易保留。'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['tpl-1']);
      expect(find.text('午餐'), findsNothing);
      expect(find.text('模板已删除'), findsOneWidget);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeTemplateRepository()..listErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('模板加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.listCalls, 2);
      expect(find.text('午餐'), findsOneWidget);
    });

    testWidgets('没有模板时展示空状态', (tester) async {
      final repository = _FakeTemplateRepository()..templates = const [];
      await _pumpPage(tester, repository);

      expect(find.text('还没有模板'), findsOneWidget);
      expect(find.text('暂无数据'), findsNothing);
      expect(find.text('新增模板'), findsWidgets);
    });

    testWidgets('收入模板跟随主题收入色', (tester) async {
      final repository = _FakeTemplateRepository()
        ..templates = const [
          QuickTemplateItem(
            id: 'tpl-income',
            name: '工资',
            type: TransactionType.income,
            amount: 12000,
            accountId: 'account-1',
            categoryId: 'category-income',
          ),
        ];
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final surface = tester.widget<PremiumSurface>(
        find.byType(PremiumSurface).last,
      );
      final badge = tester.widget<IconBadge>(
        find
            .ancestor(
              of: find.byIcon(Icons.trending_up_outlined),
              matching: find.byType(IconBadge),
            )
            .first,
      );
      expect(surface.accentColor, AppThemePalette.graphite.incomeColor);
      expect(badge.color, AppThemePalette.graphite.incomeColor);
    });

    testWidgets('新增模板失败时展示错误且保留输入和原列表', (tester) async {
      final repository = _FakeTemplateRepository()..createError = '新增模板失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('新增模板'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('template-name')), '咖啡');
      await tester.enterText(
        find.byKey(const ValueKey('template-amount')),
        '18.5',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await tester.tap(find.byKey(const ValueKey('template-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(find.text('模板保存失败'), findsOneWidget);
      expect(find.text('模板已保存'), findsNothing);
      expect(find.text('咖啡'), findsOneWidget);
      expect(find.text('午餐'), findsOneWidget);
    });

    testWidgets('套用模板失败时展示错误且保留使用次数', (tester) async {
      final repository = _FakeTemplateRepository()..applyError = '套用模板失败';
      await _pumpPage(tester, repository);

      expect(find.byTooltip('套用模板 午餐'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('template-apply-tpl-1')));
      await tester.pumpAndSettle();

      expect(repository.applyCalls, hasLength(1));
      expect(find.text('模板使用失败'), findsOneWidget);
      expect(find.text('已按模板记账'), findsNothing);
      expect(find.text('已用 3 次'), findsOneWidget);
    });

    testWidgets('删除模板失败时展示错误且保留模板', (tester) async {
      final repository = _FakeTemplateRepository()..deleteError = '删除模板失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('更多模板操作 午餐'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['tpl-1']);
      expect(find.text('模板删除失败'), findsOneWidget);
      expect(find.text('模板已删除'), findsNothing);
      expect(find.text('午餐'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeTemplateRepository repository, {
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [templateRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: const TemplatePage(),
      ),
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
  var listCalls = 0;
  var listErrors = 0;
  String? createError;
  String? applyError;
  String? deleteError;

  @override
  Future<TransactionItem> apply(String id, ApplyTemplateRequest request) async {
    applyCalls.add((id, request));
    final error = applyError;
    if (error != null) {
      throw StateError(error);
    }
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
    final error = createError;
    if (error != null) {
      throw StateError(error);
    }
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
    final error = deleteError;
    if (error != null) {
      throw StateError(error);
    }
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
    listCalls += 1;
    if (listErrors > 0) {
      listErrors -= 1;
      throw StateError('模板加载失败');
    }
    return templates;
  }
}
