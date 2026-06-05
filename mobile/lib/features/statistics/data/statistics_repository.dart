import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import 'statistics_models.dart';

final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return StatisticsRepository(ref.watch(apiClientProvider));
});

final statisticsDashboardProvider = FutureProvider
    .family<StatisticsDashboard, StatisticsDashboardQuery>((ref, query) {
      return ref.watch(statisticsRepositoryProvider).getDashboard(query);
    });

class StatisticsRepository {
  const StatisticsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<StatisticsDashboard> getDashboard(
    StatisticsDashboardQuery query,
  ) async {
    final results = await Future.wait<Object?>([
      getOverview(query.month),
      getTrend(query.month),
      getCategoryStats(month: query.month, type: query.categoryType),
    ]);

    return StatisticsDashboard(
      overview:
          results[0] as StatisticsOverviewData? ??
          const StatisticsOverviewData(
            income: 0,
            expense: 0,
            balance: 0,
            incomeChange: 0,
            expenseChange: 0,
            dailyAverage: 0,
            transactionCount: 0,
          ),
      trend:
          results[1] as TrendResponse? ??
          const TrendResponse(items: [], totalIncome: 0, totalExpense: 0),
      categories:
          results[2] as CategoryStatResponse? ??
          const CategoryStatResponse(total: 0, items: []),
    );
  }

  Future<StatisticsOverviewData?> getOverview(String month) {
    return _apiClient.get<StatisticsOverviewData>(
      '/statistics/overview',
      queryParameters: {'month': month},
      fromJsonT: StatisticsOverviewData.fromJson,
    );
  }

  Future<TrendResponse?> getTrend(String month) {
    return _apiClient.get<TrendResponse>(
      '/statistics/trend',
      queryParameters: {'month': month},
      fromJsonT: TrendResponse.fromJson,
    );
  }

  Future<CategoryStatResponse?> getCategoryStats({
    required String month,
    required String type,
  }) {
    return _apiClient.get<CategoryStatResponse>(
      '/statistics/categories',
      queryParameters: {'month': month, 'type': type},
      fromJsonT: CategoryStatResponse.fromJson,
    );
  }
}
