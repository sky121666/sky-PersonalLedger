class StatisticsDashboardQuery {
  const StatisticsDashboardQuery({
    required this.month,
    required this.categoryType,
  });

  final String month;
  final String categoryType;

  @override
  bool operator ==(Object other) {
    return other is StatisticsDashboardQuery &&
        other.month == month &&
        other.categoryType == categoryType;
  }

  @override
  int get hashCode => Object.hash(month, categoryType);
}

class StatisticsDashboard {
  const StatisticsDashboard({
    required this.overview,
    required this.trend,
    required this.categories,
  });

  final StatisticsOverviewData overview;
  final TrendResponse trend;
  final CategoryStatResponse categories;
}

class StatisticsOverviewData {
  const StatisticsOverviewData({
    required this.income,
    required this.expense,
    required this.balance,
    required this.incomeChange,
    required this.expenseChange,
    required this.dailyAverage,
    required this.transactionCount,
  });

  final double income;
  final double expense;
  final double balance;
  final double incomeChange;
  final double expenseChange;
  final double dailyAverage;
  final int transactionCount;

  factory StatisticsOverviewData.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('统计概览响应格式不正确');
    }

    return StatisticsOverviewData(
      income: _toDouble(json['income']),
      expense: _toDouble(json['expense']),
      balance: _toDouble(json['balance']),
      incomeChange: _toDouble(json['income_change']),
      expenseChange: _toDouble(json['expense_change']),
      dailyAverage: _toDouble(json['daily_average']),
      transactionCount: _toInt(json['transaction_count']),
    );
  }
}

class CategoryStatResponse {
  const CategoryStatResponse({required this.total, required this.items});

  final double total;
  final List<CategoryStatItem> items;

  factory CategoryStatResponse.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('分类统计响应格式不正确');
    }

    final rawItems = json['items'];
    return CategoryStatResponse(
      total: _toDouble(json['total']),
      items: rawItems is List
          ? rawItems.map(CategoryStatItem.fromJson).toList()
          : const [],
    );
  }
}

class CategoryStatItem {
  const CategoryStatItem({
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.color,
    required this.amount,
    required this.percentage,
    required this.count,
  });

  final String categoryId;
  final String categoryName;
  final String icon;
  final String color;
  final double amount;
  final double percentage;
  final int count;

  factory CategoryStatItem.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('分类统计项响应格式不正确');
    }

    return CategoryStatItem(
      categoryId: json['category_id'] as String? ?? '',
      categoryName: json['category_name'] as String? ?? '未分类',
      icon: json['icon'] as String? ?? '📝',
      color: json['color'] as String? ?? '#64748B',
      amount: _toDouble(json['amount']),
      percentage: _toDouble(json['percentage']),
      count: _toInt(json['count']),
    );
  }
}

class TrendResponse {
  const TrendResponse({
    required this.items,
    required this.totalIncome,
    required this.totalExpense,
  });

  final List<TrendItem> items;
  final double totalIncome;
  final double totalExpense;

  factory TrendResponse.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('趋势统计响应格式不正确');
    }

    final rawItems = json['items'];
    return TrendResponse(
      items: rawItems is List ? rawItems.map(TrendItem.fromJson).toList() : [],
      totalIncome: _toDouble(json['total_income']),
      totalExpense: _toDouble(json['total_expense']),
    );
  }
}

class TrendItem {
  const TrendItem({
    required this.date,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final String date;
  final double income;
  final double expense;
  final double balance;

  factory TrendItem.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('趋势统计项响应格式不正确');
    }

    return TrendItem(
      date: json['date'] as String? ?? '',
      income: _toDouble(json['income']),
      expense: _toDouble(json['expense']),
      balance: _toDouble(json['balance']),
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

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
