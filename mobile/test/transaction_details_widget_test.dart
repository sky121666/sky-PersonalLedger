import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/transaction_details_page.dart';

void main() {
  group('TransactionDetailsPage', () {
    testWidgets('展示交易列表并可进入编辑页', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpPage(tester, repository);

      expect(find.text('明细'), findsOneWidget);
      expect(find.text('交易明细总览'), findsNothing);
      expect(find.text('流水信号带'), findsNothing);
      expect(find.text('交易洞察轨道'), findsNothing);
      expect(find.text('流水构成矩阵'), findsNothing);
      expect(find.text('筛选'), findsNothing);
      expect(
        find.byKey(const ValueKey('transaction-filter-workbench')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transaction-search')))
            .decoration
            ?.hintText,
        '搜索明细',
      );
      expect(
        find.byKey(const ValueKey('transaction-filter-toggle')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilterChip, '全部'), findsNothing);
      expect(find.widgetWithText(FilterChip, '支出'), findsNothing);
      expect(find.text('餐饮'), findsAtLeastNWidgets(1));
      expect(find.textContaining('现金'), findsAtLeastNWidgets(1));
      expect(find.textContaining('2026-05-18 12:00'), findsAtLeastNWidgets(1));
      expect(find.text('分类'), findsNothing);
      expect(find.text('账户'), findsNothing);
      expect(find.text('入账'), findsNothing);
      expect(find.text('全部类型'), findsNothing);
      expect(find.text('全部账户'), findsNothing);
      expect(
        find.byKey(const ValueKey('transaction-amount-transaction-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-more-menu-transaction-1')),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('transaction-item-transaction-1')),
          matching: find.byType(Semantics),
        ),
        findsWidgets,
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-more-menu-transaction-1')),
      );
      await tester.pumpAndSettle();
      await _tapTransactionMenuAction(
        tester,
        transactionId: 'transaction-1',
        actionLabel: _toggleActionLabel(isTransactionExpanded: false),
        actionSuffix: 'toggle',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('午餐'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('transaction-item-transaction-1')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transaction-amount-transaction-1')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-item-transaction-1')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('编辑 transaction-1'), findsOneWidget);
      expect(find.textContaining('午餐'), findsOneWidget);
    });

    testWidgets('删除交易前需要确认并刷新列表', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('transaction-item-transaction-1')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('transaction-more-menu-transaction-1')),
      );
      await tester.pumpAndSettle();
      await _tapTransactionMenuAction(
        tester,
        actionLabel: '删除',
        actionSuffix: 'delete',
        transactionId: 'transaction-1',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('删除「餐饮」？'), findsOneWidget);
      expect(find.textContaining('余额将同步调整'), findsNothing);
      expect(find.textContaining('账户余额会自动调整'), findsNothing);
      expect(find.textContaining('同步回滚'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['transaction-1']);
      expect(find.text('餐饮'), findsNothing);
      expect(find.text('交易已删除'), findsOneWidget);
      expect(repository.listQueries.length, greaterThanOrEqualTo(2));
    });

    testWidgets('可以选择多笔交易并批量删除', (tester) async {
      final repository = _FakeTransactionRepository(
        items: [
          _transaction(id: 'transaction-1', remark: '午餐'),
          _transaction(id: 'transaction-2', remark: '晚餐'),
        ],
      );
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('transaction-item-transaction-1')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(const ValueKey('transaction-item-transaction-1')),
      );
      await tester.pumpAndSettle();
      final transactionSelectSemantics = tester.widget<Semantics>(
        find.byKey(
          const ValueKey('transaction-select-semantics-transaction-1'),
        ),
      );
      expect(transactionSelectSemantics.properties.label, '选择交易 餐饮');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('transaction-select-transaction-2')),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-select-transaction-2')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transaction-clear-selection')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-select-all-current-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-batch-delete')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('transaction-batch-delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('删除 2 笔交易？'), findsOneWidget);
      expect(find.textContaining('余额将同步调整'), findsNothing);
      expect(find.textContaining('账户余额会自动调整'), findsNothing);
      expect(find.textContaining('同步回滚'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.batchDeleteCalls, [
        ['transaction-1', 'transaction-2'],
      ]);
      expect(find.text('餐饮'), findsNothing);
      expect(find.textContaining('已删 2 笔'), findsOneWidget);
    });

    testWidgets('搜索和筛选会按条件刷新交易列表', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpPage(tester, repository);
      expect(repository.listAccountsCalls, 1);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-search')),
        '午餐',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(repository.listQueries.last.keyword, '午餐');

      await tester.tap(find.byKey(const ValueKey('transaction-filter-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '支出'));
      await tester.pumpAndSettle();

      expect(repository.listQueries.last.type, TransactionType.expense);
      expect(find.text('2 项筛选 · 1/1'), findsOneWidget);
      expect(find.text('筛选构成'), findsNothing);
      expect(
        find.byKey(const ValueKey('transaction-filter-summary-clear')),
        findsOneWidget,
      );
      expect(find.text('支出'), findsOneWidget);
      expect(repository.listAccountsCalls, 1);
    });

    testWidgets('清空筛选会重置搜索和类型条件', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-search')),
        '午餐',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('transaction-filter-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '支出'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('transaction-filter-clear')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('transaction-search')),
      );
      expect(field.controller?.text, isEmpty);
      expect(repository.listQueries.last.keyword, isEmpty);
      expect(repository.listQueries.last.type, isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transaction-search')))
            .decoration
            ?.hintText,
        '搜索明细',
      );
    });

    testWidgets('滚动到底部时加载下一页交易', (tester) async {
      final repository = _FakeTransactionRepository(
        items: List.generate(
          25,
          (index) => _transaction(
            id: 'transaction-${index + 1}',
            remark: '流水 ${index + 1}',
          ),
        ),
      );
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('transaction-item-transaction-25')),
        420,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(
        repository.listQueries.map((query) => query.page),
        containsAllInOrder([1, 2]),
      );
    });

    testWidgets('没有交易时展示空状态并可进入记账页', (tester) async {
      final repository = _FakeTransactionRepository(items: const []);
      await _pumpPage(tester, repository);

      expect(find.text('还没有明细'), findsOneWidget);
      expect(find.text('右上角添加'), findsOneWidget);
      expect(find.text('右下角添加'), findsNothing);
      expect(find.text('还没有明细，先创建一笔交易'), findsNothing);
      expect(find.byKey(const ValueKey('transaction-add')), findsOneWidget);
      expect(find.text('暂无交易明细'), findsNothing);
      expect(find.text('还没有交易记录。'), findsNothing);
      expect(find.widgetWithText(FilledButton, '去记一笔'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('transaction-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('编辑 '), findsOneWidget);
    });

    testWidgets('筛选无结果时展示匹配空状态', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-search')),
        '晚餐',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('没有匹配结果'), findsOneWidget);
      expect(find.text('清空筛选后查看全部'), findsOneWidget);
      expect(find.text('没有匹配的交易'), findsNothing);
      expect(find.text('调整筛选条件后再试。'), findsNothing);
    });

    testWidgets('初始加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeTransactionRepository(failingListRequests: 1);
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.text('交易加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('餐饮'), findsAtLeastNWidgets(1));
      expect(repository.listQueries.length, 2);
    });

    testWidgets('交易列表跟随主题色模板', (tester) async {
      final repository = _FakeTransactionRepository(
        items: [_transaction(type: TransactionType.income)],
      );
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final amountText = tester.widget<Text>(
        find.byKey(const ValueKey('transaction-amount-transaction-1')),
      );
      expect(amountText.style?.color, AppThemePalette.graphite.incomeColor);
    });

    testWidgets('交易明细核心区域保持清晰列表层级', (tester) async {
      final repository = _FakeTransactionRepository(
        items: [
          _transaction(id: 'transaction-1', remark: '午餐'),
          _transaction(id: 'transaction-2', remark: '晚餐'),
        ],
      );
      await _pumpPage(tester, repository);

      expect(find.text('明细'), findsOneWidget);
      expect(find.text('餐饮'), findsAtLeastNWidgets(2));
      expect(
        find.byKey(const ValueKey('transaction-more-menu-transaction-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-item-transaction-1')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-more-menu-transaction-1')),
      );
      await tester.pumpAndSettle();
      await _tapTransactionMenuAction(
        tester,
        transactionId: 'transaction-1',
        actionLabel: _toggleActionLabel(isTransactionExpanded: false),
        actionSuffix: 'toggle',
      );
      await tester.pumpAndSettle();
      expect(find.text('午餐'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeTransactionRepository repository, {
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late final GoRouter router;
  router = GoRouter(
    initialLocation: AppRoutePaths.transactions,
    routes: [
      GoRoute(
        path: AppRoutePaths.transactions,
        builder: (context, state) => const TransactionDetailsPage(),
      ),
      GoRoute(
        path: AppRoutePaths.quickTransaction,
        builder: (context, state) {
          final transaction = state.extra as TransactionItem?;
          final header = transaction == null
              ? '编辑 new'
              : '编辑 ${transaction.id}';
          final subtitle = transaction?.remark.trim();
          return Scaffold(
            appBar: AppBar(title: const Text('编辑页')),
            body: Text(
              subtitle == null || subtitle.isEmpty
                  ? header
                  : '$header $subtitle',
            ),
          );
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transactionRepositoryProvider.overrideWithValue(repository),
        themeControllerProvider.overrideWith(
          (ref) => _FixedThemeController(palette),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FixedThemeController extends ThemeController {
  _FixedThemeController(AppThemePalette palette) {
    state = AppThemeSettings(palette: palette);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> setPalette(AppThemePalette palette) async {
    state = state.copyWith(palette: palette);
  }
}

String _toggleActionLabel({required bool isTransactionExpanded}) =>
    isTransactionExpanded ? '收起' : '详情';

Future<void> _tapTransactionMenuAction(
  WidgetTester tester, {
  required String transactionId,
  required String actionLabel,
  String? actionSuffix,
}) async {
  Finder finder = actionSuffix == null
      ? find.text(actionLabel)
      : find.byKey(ValueKey('transaction-action-$actionSuffix-$transactionId'));
  if (!tester.any(finder)) {
    finder = find.text(actionLabel);
  }
  await tester.tap(finder);
}

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository({
    List<TransactionItem>? items,
    this.failingListRequests = 0,
  }) : items = items ?? [_transaction()];

  var items = <TransactionItem>[];
  var failingListRequests = 0;

  final List<TransactionListQuery> listQueries = [];
  final List<String> deleteCalls = [];
  final List<List<String>> batchDeleteCalls = [];
  int listAccountsCalls = 0;

  @override
  Future<void> batchDelete(List<String> ids) async {
    batchDeleteCalls.add(ids);
    items = items.where((item) => !ids.contains(item.id)).toList();
  }

  @override
  Future<TransactionItem> create(TransactionFormData formData) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    items = items.where((item) => item.id != id).toList();
  }

  @override
  Future<TransactionItem> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<TransactionListResult> list(TransactionListQuery query) async {
    listQueries.add(query);
    if (failingListRequests > 0) {
      failingListRequests -= 1;
      throw StateError('加载交易失败');
    }
    var filtered = items;
    if (query.keyword != null && query.keyword!.trim().isNotEmpty) {
      filtered = filtered
          .where((item) => item.remark.contains(query.keyword!.trim()))
          .toList();
    }
    if (query.type != null) {
      filtered = filtered.where((item) => item.type == query.type).toList();
    }
    final start = (query.page - 1) * query.pageSize;
    final pageItems = start >= filtered.length
        ? const <TransactionItem>[]
        : filtered.skip(start).take(query.pageSize).toList();
    return TransactionListResult(
      list: pageItems,
      total: filtered.length,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  Future<List<LedgerAccount>> listAccounts() async {
    listAccountsCalls += 1;
    return const [LedgerAccount(id: 'account-1', name: '现金', type: 'cash')];
  }

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    return const [
      LedgerCategory(id: 'category-food', name: '餐饮', type: 'expense'),
    ];
  }

  @override
  Future<List<LedgerTag>> listTags() async {
    return const [];
  }

  @override
  Future<TransactionItem> update(String id, TransactionFormData formData) {
    throw UnimplementedError();
  }
}

TransactionItem _transaction({
  String id = 'transaction-1',
  String remark = '午餐',
  TransactionType type = TransactionType.expense,
}) {
  return TransactionItem(
    id: id,
    type: type,
    amount: 32.5,
    accountId: 'account-1',
    categoryId: 'category-food',
    transactionDate: DateTime(2026, 5, 18, 12),
    remark: remark,
    category: const LedgerCategory(
      id: 'category-food',
      name: '餐饮',
      type: 'expense',
    ),
    account: const LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
    tags: const ['日常'],
  );
}
