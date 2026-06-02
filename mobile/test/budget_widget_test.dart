import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/budgets/presentation/budget_page.dart';
import 'package:personal_ledger/features/categories/application/category_controller.dart';
import 'package:personal_ledger/features/categories/data/category.dart';
import 'package:personal_ledger/features/categories/data/category_repository.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';

void main() {
  group('BudgetPage', () {
    testWidgets('展示总预算和分类预算进度', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      expect(find.text('预算管理'), findsOneWidget);
      expect(find.text('本月预算总览'), findsOneWidget);
      expect(find.text('¥1200.00'), findsAtLeastNWidgets(1));
      expect(find.text('¥1800.00'), findsAtLeastNWidgets(1));
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('87%'), findsAtLeastNWidgets(1));

      expect(find.byKey(const ValueKey('budget-command-center')), findsNothing);
      expect(find.byKey(const ValueKey('budget-risk-radar')), findsNothing);
      expect(
        find.byKey(const ValueKey('budget-family-hub-panel')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('budget-ai-guardrail-rail')),
        findsNothing,
      );
      expect(find.text('预算控制台'), findsNothing);
      expect(find.text('预算风险雷达'), findsNothing);
      expect(find.text('家庭预算 Hub'), findsNothing);
      expect(find.text('预算守卫矩阵'), findsNothing);
      expect(find.text('预算燃烧节奏正常'), findsNothing);
      expect(
        find.byKey(const ValueKey('budget-guardrail-matrix-budget-food')),
        findsNothing,
      );

      await tester.scrollUntilVisible(find.text('家庭成员预算'), 300);
      await tester.pumpAndSettle();
      expect(find.text('家庭成员预算'), findsOneWidget);
      expect(find.text('家人'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('budget-guardrail-matrix-member-budget-family'),
        ),
        findsNothing,
      );
      expect(find.text('成员范围'), findsNothing);
    });

    testWidgets('预算总览和预算卡片使用分段入场动效', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(6));
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

      await tester.tap(find.text('添加').at(0));
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

    testWidgets('添加成员预算时提交成员范围', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      await tester.scrollUntilVisible(find.text('家庭成员预算'), 300);
      await tester.tap(find.text('添加').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '900');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(budgetRepository.setTotalCalls, hasLength(1));
      expect(budgetRepository.setTotalCalls.single.amount, 900);
      expect(budgetRepository.setTotalCalls.single.memberId, 'member-family');
    });

    testWidgets('删除分类预算前需要确认', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(tester, budgetRepository);

      final deleteButton = find.byTooltip('删除预算 餐饮');
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(budgetRepository.deleteCalls, ['budget-food']);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final budgetRepository = _FakeBudgetRepository()..getListErrors = 1;
      await _pumpPage(tester, budgetRepository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('预算加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('预算管理'), findsOneWidget);
      expect(find.text('餐饮'), findsOneWidget);
      expect(budgetRepository.getListCalls, 2);
    });

    testWidgets('没有预算时展示总预算和分类预算空态', (tester) async {
      final budgetRepository = _FakeBudgetRepository()
        ..budgetList = const BudgetListResponse(
          totalBudget: null,
          categoryBudgets: [],
        );
      await _pumpPage(tester, budgetRepository);

      expect(find.text('预算风险雷达'), findsNothing);
      expect(find.text('预算稳态'), findsNothing);
      expect(find.text('等待总预算、分类预算和家庭预算接入'), findsNothing);
      expect(
        find.byKey(const ValueKey('budget-ai-guardrail-rail')),
        findsNothing,
      );
      expect(find.text('家庭预留'), findsNothing);
      expect(find.text('提醒线预留'), findsNothing);
      expect(find.text('还没有设置总预算'), findsOneWidget);
      expect(find.text('暂无分类预算'), findsOneWidget);
      expect(find.text('暂无数据'), findsNothing);
    });

    testWidgets('保存总预算失败时展示错误面板', (tester) async {
      final budgetRepository = _FakeBudgetRepository()
        ..setTotalError = '总预算保存失败';
      await _pumpPage(tester, budgetRepository);

      await tester.tap(find.text('修改'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '3500');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(budgetRepository.setTotalCalls, hasLength(1));
      expect(budgetRepository.setTotalCalls.single.amount, 3500);
      expect(find.textContaining('总预算保存失败'), findsOneWidget);
      expect(find.text('总预算已保存'), findsNothing);
      expect(find.text('¥1800.00'), findsAtLeastNWidgets(1));
    });

    testWidgets('预算页资产面板跟随主题色模板', (tester) async {
      final budgetRepository = _FakeBudgetRepository();
      await _pumpPage(
        tester,
        budgetRepository,
        palette: AppThemePalette.graphite,
      );

      final surfaces = tester.widgetList<PremiumSurface>(
        find.byType(PremiumSurface),
      );
      expect(
        surfaces.any(
          (surface) =>
              surface.accentColor == AppThemePalette.graphite.assetColor,
        ),
        isTrue,
      );
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeBudgetRepository budgetRepository, {
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        budgetRepositoryProvider.overrideWithValue(budgetRepository),
        categoryRepositoryProvider.overrideWithValue(_FakeCategoryRepository()),
        familyMembersProvider.overrideWith((ref) async {
          return const [
            FamilyMember(
              id: 'member-family',
              name: '家人',
              relationship: '家人',
              color: '#2563EB',
              isDefault: true,
              isEnabled: true,
            ),
          ];
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: const BudgetPage(),
      ),
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
    memberBudgets: [
      BudgetItem(
        id: 'member-budget-family',
        categoryId: null,
        categoryName: '',
        memberId: 'member-family',
        memberName: '家人',
        amount: 1200,
        spent: 420,
        remaining: 780,
        percentage: 35,
        alertThreshold: 80,
      ),
    ],
  );

  var getListCalls = 0;
  var getListErrors = 0;
  String? setTotalError;

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
      memberBudgets: budgetList.memberBudgets,
    );
  }

  @override
  Future<BudgetListResponse?> getList({String? month}) async {
    getListCalls += 1;
    if (getListErrors > 0) {
      getListErrors -= 1;
      throw StateError('预算加载失败');
    }
    return budgetList;
  }

  @override
  Future<BudgetItem?> setCategoryBudget({
    required String categoryId,
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) async {
    setCategoryCalls.add(
      _SetCategoryCall(
        categoryId: categoryId,
        amount: amount,
        alertThreshold: alertThreshold,
        memberId: memberId,
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
      memberBudgets: budgetList.memberBudgets,
    );
    return item;
  }

  @override
  Future<BudgetItem?> setTotalBudget({
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) async {
    setTotalCalls.add(
      _SetTotalCall(
        amount: amount,
        alertThreshold: alertThreshold,
        memberId: memberId,
      ),
    );
    final error = setTotalError;
    if (error != null) {
      throw StateError(error);
    }
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
      memberBudgets: budgetList.memberBudgets,
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
  const _SetTotalCall({
    required this.amount,
    required this.alertThreshold,
    this.memberId,
  });

  final double amount;
  final int alertThreshold;
  final String? memberId;
}

class _SetCategoryCall {
  const _SetCategoryCall({
    required this.categoryId,
    required this.amount,
    required this.alertThreshold,
    this.memberId,
  });

  final String categoryId;
  final double amount;
  final int alertThreshold;
  final String? memberId;
}
