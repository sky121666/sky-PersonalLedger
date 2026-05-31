import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
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
      expect(find.byKey(const ValueKey('yearly-insight-deck')), findsOneWidget);
      expect(find.text('年度洞察台'), findsOneWidget);
      expect(find.text('年度正结余'), findsOneWidget);
      expect(find.text('交易活跃'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('yearly-narrative-radar')),
        findsOneWidget,
      );
      expect(find.text('年度叙事雷达'), findsOneWidget);
      expect(find.text('最佳结余'), findsOneWidget);
      expect(find.text('支出峰值'), findsOneWidget);
      expect(find.text('主导支出 · 餐饮 · 50.0%'), findsOneWidget);
      expect(find.text('年度现金流稳健'), findsOneWidget);
      expect(find.text('¥600.00'), findsWidgets);
      expect(find.text('交易笔数'), findsOneWidget);
      expect(find.text('活跃天数'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('年度节奏'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('全年收入'), findsOneWidget);
      expect(find.text('全年支出'), findsOneWidget);
      expect(find.text('结余峰值'), findsOneWidget);
      expect(find.text('1月 ¥600.00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('餐饮'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('餐饮'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('工资'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('工资'), findsOneWidget);
    });

    testWidgets('年度报告核心区块使用分段入场动效', (tester) async {
      final repository = _FakeYearlyReportRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(6));
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

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final currentYear = DateTime.now().year;
      final repository = _FakeYearlyReportRepository()
        ..dashboardErrors = {currentYear: 1};
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('年度报告加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.requestedYears, [currentYear, currentYear]);
      expect(find.text('$currentYear 年账本汇总'), findsOneWidget);
    });

    testWidgets('没有年度明细时展示空年度数据', (tester) async {
      final repository = _FakeYearlyReportRepository()..emptyYears = {2026};
      await _pumpPage(tester, repository);

      expect(find.text('2026 年账本汇总'), findsOneWidget);
      expect(find.text('年度洞察台'), findsOneWidget);
      expect(find.text('年度叙事雷达'), findsOneWidget);
      expect(find.text('月度样本'), findsOneWidget);
      expect(find.text('分类样本'), findsOneWidget);
      expect(find.text('暂无主导支出分类'), findsOneWidget);
      expect(find.text('暂无月度数据'), findsAtLeastNWidgets(1));
      await tester.scrollUntilVisible(
        find.text('本年暂无支出分类数据'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本年暂无支出分类数据'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('本年暂无收入分类数据'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本年暂无收入分类数据'), findsOneWidget);
      expect(find.text('交易笔数'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('年份切换失败后可重试恢复', (tester) async {
      final repository = _FakeYearlyReportRepository()
        ..dashboardErrors = {2025: 1};
      await _pumpPage(tester, repository);

      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025 年').last);
      await tester.pumpAndSettle();

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('年度报告加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(
        repository.requestedYears.where((year) => year == 2025),
        hasLength(2),
      );
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
  Map<int, int> dashboardErrors = const {};
  Set<int> emptyYears = const {};

  @override
  Future<YearlyReportDashboard> getDashboard(int year) async {
    requestedYears.add(year);
    final remainingErrors = dashboardErrors[year] ?? 0;
    if (remainingErrors > 0) {
      dashboardErrors = {...dashboardErrors, year: remainingErrors - 1};
      throw StateError('年度报告加载失败');
    }
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
    if (emptyYears.contains(year)) {
      return YearlyReport(
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
      );
    }
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
