import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/categories/application/category_controller.dart';
import 'package:personal_ledger/features/categories/data/category.dart';
import 'package:personal_ledger/features/categories/data/category_repository.dart';
import 'package:personal_ledger/features/categories/presentation/categories_page.dart';

void main() {
  group('CategoriesPage', () {
    testWidgets('展示支出分类列表', (tester) async {
      final repository = _FakeCategoryRepository();
      await _pumpPage(tester, repository);

      expect(find.text('分类'), findsOneWidget);
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('系统分类'), findsOneWidget);
      expect(find.text('交通'), findsOneWidget);
      expect(find.text('自定义分类'), findsOneWidget);
    });

    testWidgets('新增分类时提交表单字段并刷新列表', (tester) async {
      final repository = _FakeCategoryRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增分类'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('category-name')), '咖啡');
      await tester.enterText(find.byKey(const ValueKey('category-icon')), '☕');
      await tester.tap(find.byKey(const ValueKey('category-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.name, '咖啡');
      expect(repository.createCalls.single.type, CategoryType.expense);
      expect(repository.createCalls.single.icon, '☕');
      expect(find.text('咖啡'), findsOneWidget);
      expect(find.text('保存成功'), findsOneWidget);
    });

    testWidgets('编辑分类时提交更新字段', (tester) async {
      final repository = _FakeCategoryRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('交通'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('category-name')), '通勤');
      await tester.tap(find.byKey(const ValueKey('category-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'cat-traffic');
      expect(repository.updateCalls.single.$2.name, '通勤');
      expect(find.text('通勤'), findsOneWidget);
    });

    testWidgets('删除分类前需要确认', (tester) async {
      final repository = _FakeCategoryRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['cat-traffic']);
      expect(find.text('交通'), findsNothing);
      expect(find.text('删除成功'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeCategoryRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [categoryRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: CategoriesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeCategoryRepository implements CategoryRepository {
  var expenseCategories = <Category>[
    const Category(
      id: 'cat-food',
      name: '餐饮',
      type: CategoryType.expense,
      icon: '🍽️',
      color: '#EF4444',
      isSystem: true,
      sortOrder: 1,
    ),
    const Category(
      id: 'cat-traffic',
      name: '交通',
      type: CategoryType.expense,
      icon: '🚗',
      color: '#3B82F6',
      isSystem: false,
      sortOrder: 2,
    ),
  ];

  final List<CreateCategoryRequest> createCalls = [];
  final List<(String, UpdateCategoryRequest)> updateCalls = [];
  final List<String> deleteCalls = [];

  @override
  Future<Category> create(CreateCategoryRequest request) async {
    createCalls.add(request);
    final category = Category(
      id: 'cat-${expenseCategories.length + 1}',
      name: request.name,
      type: request.type,
      icon: request.icon,
      color: request.color,
      isSystem: false,
      sortOrder: expenseCategories.length + 1,
    );
    if (request.type == CategoryType.expense) {
      expenseCategories = [...expenseCategories, category];
    }
    return category;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    expenseCategories = expenseCategories
        .where((category) => category.id != id)
        .toList();
  }

  @override
  Future<CategoryListResult> list(CategoryType type) async {
    if (type == CategoryType.income) {
      return const CategoryListResult(categories: []);
    }
    return CategoryListResult(categories: expenseCategories);
  }

  @override
  Future<Category> update(String id, UpdateCategoryRequest request) async {
    updateCalls.add((id, request));
    late Category updated;
    expenseCategories = [
      for (final category in expenseCategories)
        if (category.id == id)
          updated = Category(
            id: category.id,
            name: request.name,
            type: category.type,
            icon: request.icon,
            color: request.color,
            isSystem: category.isSystem,
            sortOrder: category.sortOrder,
          )
        else
          category,
    ];
    return updated;
  }
}
