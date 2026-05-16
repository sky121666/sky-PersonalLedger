class YearlyReportDashboard {
  const YearlyReportDashboard({required this.years, required this.report});

  final List<int> years;
  final YearlyReport report;
}

class YearlyReport {
  const YearlyReport({
    required this.year,
    required this.totalIncome,
    required this.totalExpense,
    required this.netSavings,
    required this.savingsRate,
    required this.monthlyData,
    required this.topExpenses,
    required this.topIncomes,
    required this.transactionCount,
    required this.averageExpense,
    required this.averageIncome,
    required this.maxExpenseMonth,
    required this.minExpenseMonth,
    required this.bestSavingsMonth,
    required this.maxSingleExpense,
    required this.maxExpenseRemark,
    required this.activeDays,
    required this.dailyAvgExpense,
  });

  final int year;
  final double totalIncome;
  final double totalExpense;
  final double netSavings;
  final double savingsRate;
  final List<MonthlyReportData> monthlyData;
  final List<ReportCategoryStat> topExpenses;
  final List<ReportCategoryStat> topIncomes;
  final int transactionCount;
  final double averageExpense;
  final double averageIncome;
  final String maxExpenseMonth;
  final String minExpenseMonth;
  final String bestSavingsMonth;
  final double maxSingleExpense;
  final String maxExpenseRemark;
  final int activeDays;
  final double dailyAvgExpense;

  factory YearlyReport.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('年度报告响应格式不正确');
    }

    return YearlyReport(
      year: _toInt(json['year']),
      totalIncome: _toDouble(json['total_income']),
      totalExpense: _toDouble(json['total_expense']),
      netSavings: _toDouble(json['net_savings']),
      savingsRate: _toDouble(json['savings_rate']),
      monthlyData: _parseList(json['monthly_data'], MonthlyReportData.fromJson),
      topExpenses: _parseList(
        json['top_expenses'],
        ReportCategoryStat.fromJson,
      ),
      topIncomes: _parseList(json['top_incomes'], ReportCategoryStat.fromJson),
      transactionCount: _toInt(json['transaction_count']),
      averageExpense: _toDouble(json['average_expense']),
      averageIncome: _toDouble(json['average_income']),
      maxExpenseMonth: json['max_expense_month'] as String? ?? '',
      minExpenseMonth: json['min_expense_month'] as String? ?? '',
      bestSavingsMonth: json['best_savings_month'] as String? ?? '',
      maxSingleExpense: _toDouble(json['max_single_expense']),
      maxExpenseRemark: json['max_expense_remark'] as String? ?? '',
      activeDays: _toInt(json['active_days']),
      dailyAvgExpense: _toDouble(json['daily_avg_expense']),
    );
  }
}

class MonthlyReportData {
  const MonthlyReportData({
    required this.month,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final String month;
  final double income;
  final double expense;
  final double balance;

  factory MonthlyReportData.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('月度报告响应格式不正确');
    }

    return MonthlyReportData(
      month: json['month'] as String? ?? '',
      income: _toDouble(json['income']),
      expense: _toDouble(json['expense']),
      balance: _toDouble(json['balance']),
    );
  }
}

class ReportCategoryStat {
  const ReportCategoryStat({
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.amount,
    required this.percentage,
    required this.count,
  });

  final String categoryId;
  final String categoryName;
  final String categoryIcon;
  final double amount;
  final double percentage;
  final int count;

  factory ReportCategoryStat.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('年度分类统计响应格式不正确');
    }

    return ReportCategoryStat(
      categoryId: json['category_id'] as String? ?? '',
      categoryName: json['category_name'] as String? ?? '未分类',
      categoryIcon: json['category_icon'] as String? ?? '📝',
      amount: _toDouble(json['amount']),
      percentage: _toDouble(json['percentage']),
      count: _toInt(json['count']),
    );
  }
}

List<T> _parseList<T>(Object? value, T Function(Object? json) parser) {
  if (value is! List) {
    return const [];
  }
  return value.map(parser).toList();
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
