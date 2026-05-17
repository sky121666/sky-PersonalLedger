import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/transaction_details_page.dart';

void main() {
  group('TransactionDetailsPage', () {
    testWidgets('展示交易列表并可进入编辑页', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpPage(tester, repository);

      expect(find.text('明细'), findsOneWidget);
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('-¥32.50'), findsOneWidget);
      expect(find.textContaining('午餐'), findsOneWidget);

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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['transaction-1']);
      expect(find.text('餐饮'), findsNothing);
      expect(find.text('交易已删除'), findsOneWidget);
      expect(repository.listQueries.length, greaterThanOrEqualTo(2));
    });

    testWidgets('搜索和筛选会按条件刷新交易列表', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-search')),
        '午餐',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(repository.listQueries.last.keyword, '午餐');

      await tester.tap(find.text('支出'));
      await tester.pumpAndSettle();

      expect(repository.listQueries.last.type, TransactionType.expense);
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
      await tester.tap(find.text('支出'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('transaction-search')),
      );
      expect(field.controller?.text, isEmpty);
      expect(repository.listQueries.last.keyword, isEmpty);
      expect(repository.listQueries.last.type, isNull);
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

      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();

      expect(
        repository.listQueries.map((query) => query.page),
        containsAllInOrder([1, 2]),
      );
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeTransactionRepository repository,
) async {
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
          return Scaffold(
            appBar: AppBar(title: const Text('编辑页')),
            body: Text(
              '编辑 ${transaction?.id ?? 'new'} ${transaction?.remark ?? ''}',
            ),
          );
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [transactionRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository({List<TransactionItem>? items})
    : items = items ?? [_transaction()];

  var items = <TransactionItem>[];

  final List<TransactionListQuery> listQueries = [];
  final List<String> deleteCalls = [];

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
}) {
  return TransactionItem(
    id: id,
    type: TransactionType.expense,
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
    tags: const ['日常'],
  );
}
