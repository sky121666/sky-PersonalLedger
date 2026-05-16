import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/reports/data/yearly_report_models.dart';
import 'package:personal_ledger/features/reports/data/yearly_report_repository.dart';
import 'package:personal_ledger/features/reports/presentation/yearly_report_page.dart';

void main() {
  group('YearlyReportPage', () {
    testWidgets('展示年度摘要、月度趋势和分类排行', (tester) async {
      final repository = _FakeYearlyReportRepository();
      await _pumpPage(tester, repository);

      expect(find.text('年度报告'), findsWidgets);
      expect(find.text('2026 年账本汇总'), findsOneWidget);
      expect(find.text('¥600.00'), findsWidgets);
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('工资'), findsOneWidget);
    });

    testWidgets('切换年份时重新加载报告', (tester) async {
      final repository = _FakeYearlyReportRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025 年').last);
      await tester.pumpAndSettle();

      expect(repository.requestedYears, contains(2025));
      expect(find.text('2025 年账本汇总'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeYearlyReportRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [yearlyReportRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: YearlyReportPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeYearlyReportRepository implements YearlyReportRepository {
  final List<int> requestedYears = [];

  @override
  Future<YearlyReportDashboard> getDashboard(int year) async {
    requestedYears.add(year);
    return YearlyReportDashboard(
      years: const [2026, 2025],
      report: _report(year),
    );
  }

  @override
  Future<List<int>?> getAvailableYears() async {
    return const [2026, 2025];
  }

  @override
  Future<YearlyReport?> getYearlyReport(int year) async {
    requestedYears.add(year);
    return _report(year);
  }

  YearlyReport _report(int year) {
    return YearlyReport(
      year: year,
      totalIncome: 1000,
      totalExpense: 400,
      netSavings: 600,
      savingsRate: 60,
      monthlyData: const [
        MonthlyReportData(
          month: '1月',
          income: 1000,
          expense: 400,
          balance: 600,
        ),
      ],
      topExpenses: const [
        ReportCategoryStat(
          categoryId: 'expense-1',
          categoryName: '餐饮',
          categoryIcon: '🍽️',
          amount: 200,
          percentage: 50,
          count: 4,
        ),
      ],
      topIncomes: const [
        ReportCategoryStat(
          categoryId: 'income-1',
          categoryName: '工资',
          categoryIcon: '💰',
          amount: 1000,
          percentage: 100,
          count: 1,
        ),
      ],
      transactionCount: 5,
      averageExpense: 33.33,
      averageIncome: 83.33,
      maxExpenseMonth: '1月',
      minExpenseMonth: '1月',
      bestSavingsMonth: '1月',
      maxSingleExpense: 100,
      maxExpenseRemark: '晚餐',
      activeDays: 3,
      dailyAvgExpense: 133.33,
    );
  }
}
