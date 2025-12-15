import 'api_service.dart';

class OverviewData {
  final double income;
  final double expense;
  final double balance;
  final double incomeChange;
  final double expenseChange;
  final double dailyAverage;
  final int transactionCount;

  OverviewData({
    required this.income,
    required this.expense,
    required this.balance,
    required this.incomeChange,
    required this.expenseChange,
    required this.dailyAverage,
    required this.transactionCount,
  });

  factory OverviewData.fromJson(Map<String, dynamic> json) {
    return OverviewData(
      income: (json['income'] ?? 0).toDouble(),
      expense: (json['expense'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(),
      incomeChange: (json['income_change'] ?? 0).toDouble(),
      expenseChange: (json['expense_change'] ?? 0).toDouble(),
      dailyAverage: (json['daily_average'] ?? 0).toDouble(),
      transactionCount: json['transaction_count'] ?? 0,
    );
  }
}

class CategoryStatItem {
  final String categoryId;
  final String categoryName;
  final String icon;
  final String color;
  final double amount;
  final double percentage;
  final int count;

  CategoryStatItem({
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.color,
    required this.amount,
    required this.percentage,
    required this.count,
  });

  factory CategoryStatItem.fromJson(Map<String, dynamic> json) {
    return CategoryStatItem(
      categoryId: json['category_id'] ?? '',
      categoryName: json['category_name'] ?? '',
      icon: json['icon'] ?? '',
      color: json['color'] ?? '#007AFF',
      amount: (json['amount'] ?? 0).toDouble(),
      percentage: (json['percentage'] ?? 0).toDouble(),
      count: json['count'] ?? 0,
    );
  }
}

class CategoryStatResponse {
  final double total;
  final List<CategoryStatItem> items;

  CategoryStatResponse({required this.total, required this.items});

  factory CategoryStatResponse.fromJson(Map<String, dynamic> json) {
    return CategoryStatResponse(
      total: (json['total'] ?? 0).toDouble(),
      items: (json['items'] as List<dynamic>?)
          ?.map((e) => CategoryStatItem.fromJson(e))
          .toList() ?? [],
    );
  }
}

class StatisticsService {
  final ApiService _api = ApiService();

  Future<OverviewData> getOverview({String? month}) async {
    final response = await _api.get('/statistics/overview', params: {
      if (month != null) 'month': month,
    });
    if (response.data['code'] == 0) {
      return OverviewData.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }

  Future<CategoryStatResponse> getCategoryStats({String? month, String? type}) async {
    final response = await _api.get('/statistics/categories', params: {
      if (month != null) 'month': month,
      if (type != null) 'type': type,
    });
    if (response.data['code'] == 0) {
      return CategoryStatResponse.fromJson(response.data['data']);
    }
    throw Exception(response.data['message']);
  }
}
