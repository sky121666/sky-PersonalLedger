import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
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

    testWidgets('分类头部和卡片使用分段入场动效', (tester) async {
      final repository = _FakeCategoryRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(3));
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

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeCategoryRepository()..listErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('分类加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('餐饮'), findsOneWidget);
      expect(repository.listCalls, 2);
    });

    testWidgets('没有分类时展示空状态', (tester) async {
      final repository = _FakeCategoryRepository()
        ..expenseCategories = const [];
      await _pumpPage(tester, repository);

      expect(find.text('暂无支出分类'), findsOneWidget);
      expect(find.text('添加分类后，记账时可以快速归类。'), findsOneWidget);
    });

    testWidgets('新增分类失败时展示错误且保留输入', (tester) async {
      final repository = _FakeCategoryRepository()..createError = '新增分类失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增分类'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('category-name')), '咖啡');
      await tester.enterText(find.byKey(const ValueKey('category-icon')), '☕');
      await tester.tap(find.byKey(const ValueKey('category-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(find.textContaining('新增分类失败'), findsOneWidget);
      expect(find.text('保存成功'), findsNothing);
      expect(find.text('咖啡'), findsOneWidget);
      expect(find.text('餐饮'), findsOneWidget);
    });

    testWidgets('编辑分类失败时展示错误且保留原列表', (tester) async {
      final repository = _FakeCategoryRepository()..updateError = '编辑分类失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.text('交通'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('category-name')), '通勤');
      await tester.tap(find.byKey(const ValueKey('category-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(find.textContaining('编辑分类失败'), findsOneWidget);
      expect(find.text('保存成功'), findsNothing);
      expect(find.text('通勤'), findsOneWidget);
      expect(find.text('交通'), findsOneWidget);
    });

    testWidgets('删除分类失败时展示错误且保留分类', (tester) async {
      final repository = _FakeCategoryRepository()..deleteError = '删除分类失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.byIcon(Icons.more_vert).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['cat-traffic']);
      expect(find.textContaining('删除分类失败'), findsOneWidget);
      expect(find.text('删除成功'), findsNothing);
      expect(find.text('交通'), findsOneWidget);
    });

    testWidgets('分类头部跟随主题色模板', (tester) async {
      final repository = _FakeCategoryRepository();
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final surface = tester.widget<PremiumSurface>(
        find.byType(PremiumSurface).first,
      );
      expect(surface.accentColor, AppThemePalette.graphite.expenseColor);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeCategoryRepository repository, {
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [categoryRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: const CategoriesPage(),
      ),
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
  var listCalls = 0;
  var listErrors = 0;
  String? createError;
  String? updateError;
  String? deleteError;

  @override
  Future<Category> create(CreateCategoryRequest request) async {
    createCalls.add(request);
    final error = createError;
    if (error != null) {
      throw StateError(error);
    }
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
    final error = deleteError;
    if (error != null) {
      throw StateError(error);
    }
    expenseCategories = expenseCategories
        .where((category) => category.id != id)
        .toList();
  }

  @override
  Future<CategoryListResult> list(CategoryType type) async {
    listCalls += 1;
    if (listErrors > 0) {
      listErrors -= 1;
      throw StateError('分类加载失败');
    }
    if (type == CategoryType.income) {
      return const CategoryListResult(categories: []);
    }
    return CategoryListResult(categories: expenseCategories);
  }

  @override
  Future<Category> update(String id, UpdateCategoryRequest request) async {
    updateCalls.add((id, request));
    final error = updateError;
    if (error != null) {
      throw StateError(error);
    }
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
