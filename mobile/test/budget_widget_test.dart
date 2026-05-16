import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/budgets/presentation/budget_page.dart';
import 'package:personal_ledger/features/categories/application/category_controller.dart';
import 'package:personal_ledger/features/categories/data/category.dart';
import 'package:personal_ledger/features/categories/data/category_repository.dart';

void main() {
  group('BudgetPage', () {
    testWidgets('展示总预算和分类预算进度', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      expect(find.text('预算管理'), findsOneWidget);
      expect(find.text('¥1800.00'), findsOneWidget);
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('87%'), findsOneWidget);
    });

    testWidgets('保存总预算时提交金额和提醒阈值', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      await tester.tap(find.text('修改'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '3500');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(budgetRepository.setTotalCalls, hasLength(1));
      expect(budgetRepository.setTotalCalls.single.amount, 3500);
      expect(budgetRepository.setTotalCalls.single.alertThreshold, 80);
    });

    testWidgets('添加分类预算时使用尚未设置预算的支出分类', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '500');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(budgetRepository.setCategoryCalls, hasLength(1));
      expect(
        budgetRepository.setCategoryCalls.single.categoryId,
        'cat-traffic',
      );
      expect(budgetRepository.setCategoryCalls.single.amount, 500);
    });

    testWidgets('删除分类预算前需要确认', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      await tester.tap(find.byTooltip('删除预算'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(budgetRepository.deleteCalls, ['budget-food']);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeBudgetRepository budgetRepository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        budgetRepositoryProvider.overrideWithValue(budgetRepository),
        categoryRepositoryProvider.overrideWithValue(_FakeCategoryRepository()),
      ],
      child: const MaterialApp(home: BudgetPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeBudgetRepository implements BudgetRepository {
  BudgetListResponse budgetList = const BudgetListResponse(
    totalBudget: BudgetItem(
      id: 'total',
      categoryId: null,
      categoryName: '',
      amount: 3000,
      spent: 1200,
      remaining: 1800,
      percentage: 40,
      alertThreshold: 80,
    ),
    categoryBudgets: [
      BudgetItem(
        id: 'budget-food',
        categoryId: 'cat-food',
        categoryName: '餐饮',
        amount: 800,
        spent: 700,
        remaining: 100,
        percentage: 87,
        alertThreshold: 80,
      ),
    ],
  );

  final List<_SetTotalCall> setTotalCalls = [];
  final List<_SetCategoryCall> setCategoryCalls = [];
  final List<String> deleteCalls = [];

  @override
  Future<void> deleteBudget(String id) async {
    deleteCalls.add(id);
    budgetList = BudgetListResponse(
      totalBudget: budgetList.totalBudget,
      categoryBudgets: budgetList.categoryBudgets
          .where((budget) => budget.id != id)
          .toList(),
    );
  }

  @override
  Future<BudgetListResponse?> getList({String? month}) async {
    return budgetList;
  }

  @override
  Future<BudgetItem?> setCategoryBudget({
    required String categoryId,
    required double amount,
    required int alertThreshold,
  }) async {
    setCategoryCalls.add(
      _SetCategoryCall(
        categoryId: categoryId,
        amount: amount,
        alertThreshold: alertThreshold,
      ),
    );
    final item = BudgetItem(
      id: 'budget-$categoryId',
      categoryId: categoryId,
      categoryName: '交通',
      amount: amount,
      spent: 0,
      remaining: amount,
      percentage: 0,
      alertThreshold: alertThreshold,
    );
    budgetList = BudgetListResponse(
      totalBudget: budgetList.totalBudget,
      categoryBudgets: [...budgetList.categoryBudgets, item],
    );
    return item;
  }

  @override
  Future<BudgetItem?> setTotalBudget({
    required double amount,
    required int alertThreshold,
  }) async {
    setTotalCalls.add(
      _SetTotalCall(amount: amount, alertThreshold: alertThreshold),
    );
    final item = BudgetItem(
      id: 'total',
      categoryId: null,
      categoryName: '',
      amount: amount,
      spent: 1200,
      remaining: amount - 1200,
      percentage: 1200 / amount * 100,
      alertThreshold: alertThreshold,
    );
    budgetList = BudgetListResponse(
      totalBudget: item,
      categoryBudgets: budgetList.categoryBudgets,
    );
    return item;
  }
}

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Future<Category> create(CreateCategoryRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<CategoryListResult> list(CategoryType type) async {
    return const CategoryListResult(
      categories: [
        Category(
          id: 'cat-food',
          name: '餐饮',
          type: CategoryType.expense,
          icon: '🍽️',
          color: '#EF4444',
          isSystem: true,
          sortOrder: 1,
        ),
        Category(
          id: 'cat-traffic',
          name: '交通',
          type: CategoryType.expense,
          icon: '🚗',
          color: '#3B82F6',
          isSystem: true,
          sortOrder: 2,
        ),
      ],
    );
  }

  @override
  Future<Category> update(String id, UpdateCategoryRequest request) {
    throw UnimplementedError();
  }
}

class _SetTotalCall {
  const _SetTotalCall({required this.amount, required this.alertThreshold});

  final double amount;
  final int alertThreshold;
}

class _SetCategoryCall {
  const _SetCategoryCall({
    required this.categoryId,
    required this.amount,
    required this.alertThreshold,
  });

  final String categoryId;
  final double amount;
  final int alertThreshold;
}
