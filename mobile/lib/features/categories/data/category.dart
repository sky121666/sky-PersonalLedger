enum CategoryType { expense, income }

extension CategoryTypeValue on CategoryType {
  String get value => switch (this) {
    CategoryType.expense => 'expense',
    CategoryType.income => 'income',
  };

  String get label => switch (this) {
    CategoryType.expense => '支出',
    CategoryType.income => '收入',
  };
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.isSystem,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String icon;
  final String color;
  final bool isSystem;
  final int sortOrder;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: (json['type'] as String?) == CategoryType.income.value
          ? CategoryType.income
          : CategoryType.expense,
      icon: json['icon'] as String? ?? '📝',
      color: json['color'] as String? ?? '#3B82F6',
      isSystem: json['is_system'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class CategoryListResult {
  const CategoryListResult({required this.categories});

  final List<Category> categories;

  factory CategoryListResult.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'];
    return CategoryListResult(
      categories: rawList is List
          ? rawList
                .whereType<Map<String, dynamic>>()
                .map(Category.fromJson)
                .toList()
          : const [],
    );
  }
}

class CreateCategoryRequest {
  const CreateCategoryRequest({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });

  final String name;
  final CategoryType type;
  final String icon;
  final String color;

  Map<String, dynamic> toJson() {
    return {'name': name, 'type': type.value, 'icon': icon, 'color': color};
  }
}

class UpdateCategoryRequest {
  const UpdateCategoryRequest({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final String color;

  Map<String, dynamic> toJson() {
    return {'name': name, 'icon': icon, 'color': color};
  }
}
