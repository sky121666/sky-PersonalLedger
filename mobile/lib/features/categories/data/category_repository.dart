import '../../../core/network/api_client.dart';
import 'category.dart';

class CategoryRepository {
  const CategoryRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 获取指定类型分类列表。
  Future<CategoryListResult> list(CategoryType type) async {
    final result = await _apiClient.get<CategoryListResult>(
      '/categories',
      queryParameters: {'type': type.value},
      fromJsonT: (json) =>
          CategoryListResult.fromJson((json as Map).cast<String, dynamic>()),
    );
    return result ?? const CategoryListResult(categories: []);
  }

  /// 创建分类。
  Future<Category> create(CreateCategoryRequest request) async {
    final result = await _apiClient.post<Category>(
      '/categories',
      data: request.toJson(),
      fromJsonT: (json) =>
          Category.fromJson((json as Map).cast<String, dynamic>()),
    );
    return result!;
  }

  /// 更新分类。
  Future<Category> update(String id, UpdateCategoryRequest request) async {
    final result = await _apiClient.put<Category>(
      '/categories/$id',
      data: request.toJson(),
      fromJsonT: (json) =>
          Category.fromJson((json as Map).cast<String, dynamic>()),
    );
    return result!;
  }

  /// 删除分类。
  Future<void> delete(String id) async {
    await _apiClient.delete<void>('/categories/$id');
  }
}
