import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../categories/application/category_controller.dart';
import '../../categories/data/category.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return BudgetRepository(ref.watch(apiClientProvider));
});

final budgetDashboardProvider = FutureProvider.autoDispose<BudgetDashboard>((
  ref,
) async {
  final results = await Future.wait<Object?>([
    ref.watch(budgetRepositoryProvider).getList(),
    ref.watch(categoryRepositoryProvider).list(CategoryType.expense),
  ]);

  final budgetList =
      results[0] as BudgetListResponse? ??
      const BudgetListResponse(
        totalBudget: null,
        categoryBudgets: [],
        memberBudgets: [],
      );
  final categoryList =
      results[1] as CategoryListResult? ??
      const CategoryListResult(categories: []);

  return BudgetDashboard(
    budgetList: budgetList,
    expenseCategories: categoryList.categories,
  );
});

final memberBudgetsProvider = FutureProvider.autoDispose<List<BudgetItem>>((
  ref,
) async {
  final budgetList = await ref.watch(budgetRepositoryProvider).getList();
  return budgetList?.memberBudgets ?? const [];
});

class BudgetRepository {
  const BudgetRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<BudgetListResponse?> getList({String? month}) {
    return _apiClient.get<BudgetListResponse>(
      '/budgets',
      queryParameters: month == null ? null : {'month': month},
      fromJsonT: BudgetListResponse.fromJson,
    );
  }

  Future<BudgetItem?> setTotalBudget({
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) {
    return _apiClient.post<BudgetItem>(
      '/budgets/total',
      data: {
        'amount': amount,
        'alert_threshold': alertThreshold,
        if (memberId != null && memberId.isNotEmpty) 'member_id': memberId,
      },
      fromJsonT: BudgetItem.fromJson,
    );
  }

  Future<BudgetItem?> setCategoryBudget({
    required String categoryId,
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) {
    return _apiClient.post<BudgetItem>(
      '/budgets/category',
      data: {
        'category_id': categoryId,
        'amount': amount,
        'alert_threshold': alertThreshold,
        if (memberId != null && memberId.isNotEmpty) 'member_id': memberId,
      },
      fromJsonT: BudgetItem.fromJson,
    );
  }

  Future<void> deleteBudget(String id) async {
    await _apiClient.delete<void>('/budgets/$id');
  }
}

class BudgetDashboard {
  const BudgetDashboard({
    required this.budgetList,
    required this.expenseCategories,
  });

  final BudgetListResponse budgetList;
  final List<Category> expenseCategories;

  List<Category> get availableExpenseCategories {
    final usedIds = budgetList.categoryBudgets
        .map((budget) => budget.categoryId)
        .whereType<String>()
        .toSet();
    return expenseCategories
        .where((category) => !usedIds.contains(category.id))
        .toList();
  }
}

class BudgetListResponse {
  const BudgetListResponse({
    required this.totalBudget,
    required this.categoryBudgets,
    this.memberBudgets = const [],
  });

  final BudgetItem? totalBudget;
  final List<BudgetItem> categoryBudgets;
  final List<BudgetItem> memberBudgets;

  factory BudgetListResponse.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('预算列表响应格式不正确');
    }

    final rawCategoryBudgets = json['category_budgets'];
    final rawMemberBudgets = json['member_budgets'];
    return BudgetListResponse(
      totalBudget: json['total_budget'] == null
          ? null
          : BudgetItem.fromJson(json['total_budget']),
      categoryBudgets: rawCategoryBudgets is List
          ? rawCategoryBudgets.map(BudgetItem.fromJson).toList()
          : const [],
      memberBudgets: rawMemberBudgets is List
          ? rawMemberBudgets.map(BudgetItem.fromJson).toList()
          : const [],
    );
  }
}

class BudgetItem {
  const BudgetItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    this.memberId,
    this.memberName = '',
    required this.amount,
    required this.spent,
    required this.remaining,
    required this.percentage,
    required this.alertThreshold,
  });

  final String id;
  final String? categoryId;
  final String categoryName;
  final String? memberId;
  final String memberName;
  final double amount;
  final double spent;
  final double remaining;
  final double percentage;
  final int alertThreshold;

  bool get isOverBudget => spent > amount && amount > 0;

  bool get isNearLimit => percentage >= alertThreshold;

  factory BudgetItem.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('预算响应格式不正确');
    }

    return BudgetItem(
      id: json['id'] as String? ?? '',
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String? ?? '',
      memberId: json['member_id'] as String?,
      memberName: json['member_name'] as String? ?? '',
      amount: _toDouble(json['amount']),
      spent: _toDouble(json['spent']),
      remaining: _toDouble(json['remaining']),
      percentage: _toDouble(json['percentage']),
      alertThreshold: _toInt(json['alert_threshold'], fallback: 80),
    );
  }
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

int _toInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}
