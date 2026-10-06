import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/category.dart';
import '../data/category_repository.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(ledgerApiClientProvider));
});

final categoryListControllerProvider =
    StateNotifierProvider<
      CategoryListController,
      AsyncValue<CategoryListState>
    >((ref) {
      ref.watch(categoryRepositoryProvider);
      return CategoryListController(ref)..load();
    });

class CategoryListState {
  const CategoryListState({required this.type, required this.categories});

  final CategoryType type;
  final List<Category> categories;

  CategoryListState copyWith({CategoryType? type, List<Category>? categories}) {
    return CategoryListState(
      type: type ?? this.type,
      categories: categories ?? this.categories,
    );
  }
}

class CategoryListController
    extends StateNotifier<AsyncValue<CategoryListState>> {
  CategoryListController(this._ref)
    : super(
        const AsyncValue.data(
          CategoryListState(type: CategoryType.expense, categories: []),
        ),
      );

  final Ref _ref;
  CategoryType _type = CategoryType.expense;
  int _loadGeneration = 0;

  /// 切换分类类型并重新加载。
  Future<void> setType(CategoryType type) async {
    if (_type == type) {
      return;
    }
    _type = type;
    await load();
  }

  /// 加载当前类型分类列表。
  Future<void> load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final type = _type;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final result = await _ref.read(categoryRepositoryProvider).list(type);
      return CategoryListState(type: type, categories: result.categories);
    });
    if (mounted && generation == _loadGeneration) state = result;
  }

  /// 创建分类并刷新列表。
  Future<void> create(CreateCategoryRequest request) async {
    await _ref.read(categoryRepositoryProvider).create(request);
    await load();
  }

  /// 更新分类并刷新列表。
  Future<void> update(String id, UpdateCategoryRequest request) async {
    await _ref.read(categoryRepositoryProvider).update(id, request);
    await load();
  }

  /// 删除分类并刷新列表。
  Future<void> delete(String id) async {
    await _ref.read(categoryRepositoryProvider).delete(id);
    await load();
  }
}
