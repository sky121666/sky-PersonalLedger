import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../transactions/data/transaction_models.dart';

const debtAccountTypes = <String>{
  'credit',
  'loan',
  'mortgage',
  'car_loan',
  'consumer_loan',
  'huabei',
  'baitiao',
};

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.currentBalance,
    required this.isArchived,
  });

  final String id;
  final String name;
  final String type;
  final String icon;
  final String color;
  final double currentBalance;
  final bool isArchived;

  bool get isDebt => debtAccountTypes.contains(type);

  /// 从账户 JSON 构建账户模型。
  factory Account.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('账户响应格式不正确');
    }

    return Account(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名账户',
      type: json['type'] as String? ?? 'other',
      icon: json['icon'] as String? ?? '💳',
      color: json['color'] as String? ?? '#6366F1',
      currentBalance: _toDouble(json['current_balance']),
      isArchived: json['is_archived'] as bool? ?? false,
    );
  }
}

class AccountListResponse {
  const AccountListResponse({
    required this.list,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netAssets,
  });

  final List<Account> list;
  final double totalAssets;
  final double totalLiabilities;
  final double netAssets;

  List<Account> get activeAccounts {
    return list.where((account) => !account.isArchived).toList();
  }

  /// 从账户列表 JSON 构建账户汇总模型。
  factory AccountListResponse.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('账户列表响应格式不正确');
    }

    final rawList = json['list'];
    return AccountListResponse(
      list: rawList is List ? rawList.map(Account.fromJson).toList() : const [],
      totalAssets: _toDouble(json['total_assets']),
      totalLiabilities: _toDouble(json['total_liabilities']),
      netAssets: _toDouble(json['net_assets']),
    );
  }
}

class StatisticsOverview {
  const StatisticsOverview({
    required this.income,
    required this.expense,
    required this.balance,
    required this.transactionCount,
  });

  final double income;
  final double expense;
  final double balance;
  final int transactionCount;

  /// 从统计概览 JSON 构建本月收支模型。
  factory StatisticsOverview.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('统计概览响应格式不正确');
    }

    return StatisticsOverview(
      income: _toDouble(json['income']),
      expense: _toDouble(json['expense']),
      balance: _toDouble(json['balance']),
      transactionCount: json['transaction_count'] as int? ?? 0,
    );
  }
}

class BudgetSummary {
  const BudgetSummary({
    required this.totalAmount,
    required this.totalSpent,
    required this.percentage,
    required this.dailyAvailable,
    required this.daysRemaining,
    required this.overBudgetCategories,
  });

  final double totalAmount;
  final double totalSpent;
  final double percentage;
  final double dailyAvailable;
  final int daysRemaining;
  final List<OverBudgetCategory> overBudgetCategories;

  double get remainingAmount => totalAmount - totalSpent;

  /// 从预算摘要 JSON 构建预算模型。
  factory BudgetSummary.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('预算摘要响应格式不正确');
    }

    final rawOverBudgetCategories = json['over_budget_categories'];
    return BudgetSummary(
      totalAmount: _toDouble(json['total_amount']),
      totalSpent: _toDouble(json['total_spent']),
      percentage: _toDouble(json['percentage']),
      dailyAvailable: _toDouble(json['daily_available']),
      daysRemaining: json['days_remaining'] as int? ?? 0,
      overBudgetCategories: rawOverBudgetCategories is List
          ? rawOverBudgetCategories.map(OverBudgetCategory.fromJson).toList()
          : const [],
    );
  }
}

class OverBudgetCategory {
  const OverBudgetCategory({required this.name, required this.percentage});

  final String name;
  final double percentage;

  /// 从超预算分类 JSON 构建分类模型。
  factory OverBudgetCategory.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('超预算分类响应格式不正确');
    }

    return OverBudgetCategory(
      name: json['name'] as String? ?? '未命名分类',
      percentage: _toDouble(json['percentage']),
    );
  }
}

class HomeSummary {
  const HomeSummary({
    required this.accounts,
    required this.overview,
    required this.budgetSummary,
    this.recentTransactions = const [],
    this.familySummary = const FamilyHomeSummary.empty(),
  });

  final AccountListResponse accounts;
  final StatisticsOverview overview;
  final BudgetSummary budgetSummary;
  final List<TransactionItem> recentTransactions;
  final FamilyHomeSummary familySummary;
}

class FamilyHomeSummary {
  const FamilyHomeSummary({
    required this.month,
    required this.totalExpense,
    required this.members,
  });

  const FamilyHomeSummary.empty()
    : month = '',
      totalExpense = 0,
      members = const [];

  final String month;
  final double totalExpense;
  final List<FamilyHomeMemberSummary> members;

  factory FamilyHomeSummary.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const FamilyHomeSummary.empty();
    }
    final rawMembers = json['members'];
    return FamilyHomeSummary(
      month: json['month'] as String? ?? '',
      totalExpense: _toDouble(json['total_expense']),
      members: rawMembers is List
          ? rawMembers.map(FamilyHomeMemberSummary.fromJson).toList()
          : const [],
    );
  }
}

class FamilyHomeMemberSummary {
  const FamilyHomeMemberSummary({
    required this.memberID,
    required this.name,
    required this.expenseTotal,
    required this.count,
  });

  final String memberID;
  final String name;
  final double expenseTotal;
  final int count;

  factory FamilyHomeMemberSummary.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const FamilyHomeMemberSummary(
        memberID: '',
        name: '成员',
        expenseTotal: 0,
        count: 0,
      );
    }
    return FamilyHomeMemberSummary(
      memberID: json['member_id'] as String? ?? '',
      name: json['name'] as String? ?? '成员',
      expenseTotal: _toDouble(json['expense_total']),
      count: json['count'] as int? ?? 0,
    );
  }
}

class HomeRepository {
  const HomeRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 获取首页需要的账户、统计、预算和最近交易数据。
  Future<HomeSummary> getSummary() async {
    final results = await Future.wait<Object?>([
      _apiClient.get<AccountListResponse>(
        '/accounts',
        queryParameters: const {'include_archived': false},
        fromJsonT: AccountListResponse.fromJson,
      ),
      _apiClient.get<StatisticsOverview>(
        '/statistics/overview',
        fromJsonT: StatisticsOverview.fromJson,
      ),
      _apiClient.get<BudgetSummary>(
        '/budgets/summary',
        fromJsonT: BudgetSummary.fromJson,
      ),
      _apiClient.get<FamilyHomeSummary>(
        '/family/summary',
        fromJsonT: FamilyHomeSummary.fromJson,
      ),
      listRecentTransactions(),
    ]);

    return HomeSummary(
      accounts:
          results[0] as AccountListResponse? ??
          const AccountListResponse(
            list: [],
            totalAssets: 0,
            totalLiabilities: 0,
            netAssets: 0,
          ),
      overview:
          results[1] as StatisticsOverview? ??
          const StatisticsOverview(
            income: 0,
            expense: 0,
            balance: 0,
            transactionCount: 0,
          ),
      budgetSummary:
          results[2] as BudgetSummary? ??
          const BudgetSummary(
            totalAmount: 0,
            totalSpent: 0,
            percentage: 0,
            dailyAvailable: 0,
            daysRemaining: 0,
            overBudgetCategories: [],
          ),
      familySummary:
          results[3] as FamilyHomeSummary? ?? const FamilyHomeSummary.empty(),
      recentTransactions:
          results[4] as List<TransactionItem>? ?? const <TransactionItem>[],
    );
  }

  Future<List<TransactionItem>> listRecentTransactions() async {
    final result = await _apiClient.get<TransactionListResult>(
      '/transactions',
      queryParameters: const {'page': 1, 'page_size': 5},
      fromJsonT: (json) =>
          TransactionListResult.fromJson(json as Map<String, dynamic>? ?? {}),
    );
    return result?.list ?? const [];
  }

  Future<List<TransactionItem>> listTransactionsForDate(DateTime date) async {
    final dateText = _formatDate(date);
    final result = await _apiClient.get<TransactionListResult>(
      '/transactions',
      queryParameters: {
        'page': 1,
        'page_size': 50,
        'start_date': dateText,
        'end_date': dateText,
      },
      fromJsonT: (json) =>
          TransactionListResult.fromJson(json as Map<String, dynamic>? ?? {}),
    );
    return result?.list ?? const [];
  }
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(ref.watch(apiClientProvider));
});

final homeSummaryProvider = FutureProvider.autoDispose<HomeSummary>((ref) {
  return ref.watch(homeRepositoryProvider).getSummary();
});

final homeDateTransactionsProvider = FutureProvider.autoDispose
    .family<List<TransactionItem>, DateTime>((ref, date) {
      return ref.watch(homeRepositoryProvider).listTransactionsForDate(date);
    });

/// 将动态数值转换为 double。
double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
