import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import 'yearly_report_models.dart';

final yearlyReportRepositoryProvider = Provider<YearlyReportRepository>((ref) {
  return YearlyReportRepository(ref.watch(apiClientProvider));
});

final yearlyReportDashboardProvider = FutureProvider.autoDispose
    .family<YearlyReportDashboard, int>((ref, year) {
      return ref.watch(yearlyReportRepositoryProvider).getDashboard(year);
    });

class YearlyReportRepository {
  const YearlyReportRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<YearlyReportDashboard> getDashboard(int year) async {
    final results = await Future.wait<Object?>([
      getAvailableYears(),
      getYearlyReport(year),
    ]);
    return YearlyReportDashboard(
      years: results[0] as List<int>? ?? const [],
      report:
          results[1] as YearlyReport? ??
          YearlyReport(
            year: year,
            totalIncome: 0,
            totalExpense: 0,
            netSavings: 0,
            savingsRate: 0,
            monthlyData: const [],
            topExpenses: const [],
            topIncomes: const [],
            transactionCount: 0,
            averageExpense: 0,
            averageIncome: 0,
            maxExpenseMonth: '',
            minExpenseMonth: '',
            bestSavingsMonth: '',
            maxSingleExpense: 0,
            maxExpenseRemark: '',
            activeDays: 0,
            dailyAvgExpense: 0,
          ),
    );
  }

  Future<YearlyReport?> getYearlyReport(int year) {
    return _apiClient.get<YearlyReport>(
      '/export/report/yearly',
      queryParameters: {'year': year},
      fromJsonT: YearlyReport.fromJson,
    );
  }

  Future<List<int>?> getAvailableYears() {
    return _apiClient.get<List<int>>(
      '/export/years',
      fromJsonT: (json) {
        final map = json as Map<String, dynamic>? ?? const {};
        final years = map['years'];
        if (years is! List) {
          return const <int>[];
        }
        return years
            .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
            .whereType<int>()
            .toList();
      },
    );
  }
}
