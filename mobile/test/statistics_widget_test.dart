import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/statistics/presentation/mobile_statistics_page.dart';

void main() {
  group('MobileStatisticsPage', () {
    testWidgets('统计加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeStatisticsRepository()..dashboardErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('统计加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.dashboardCalls, 2);
      expect(find.text('统计分析'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('statistics-insight-deck')),
        findsOneWidget,
      );
      expect(find.text('数据洞察台'), findsOneWidget);
      expect(find.text('数据皮肤'), findsOneWidget);
      expect(find.textContaining('图表、分类和现金流语义色同步'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('statistics-theme-data-strip')),
        findsOneWidget,
      );
      expect(find.text('现金流正向'), findsOneWidget);
      expect(find.text('交易活跃'), findsOneWidget);
      expect(find.text('本月现金流稳健'), findsOneWidget);
      expect(find.text('结余率'), findsAtLeastNWidgets(1));
      expect(find.text('60%'), findsAtLeastNWidgets(1));
      expect(find.text('餐饮'), findsOneWidget);
    });

    testWidgets('统计页展示空统计摘要', (tester) async {
      final repository = _FakeStatisticsRepository(
        dashboards: [_dashboard(empty: true)],
      );
      await _pumpPage(tester, repository);

      expect(find.text('交易笔数'), findsOneWidget);
      expect(find.text('数据洞察台'), findsOneWidget);
      expect(find.text('数据皮肤'), findsOneWidget);
      expect(find.text('默认稳健'), findsOneWidget);
      expect(find.text('趋势节点'), findsOneWidget);
      expect(find.text('分类样本'), findsOneWidget);
      expect(find.text('本月现金流持平'), findsOneWidget);
      expect(find.text('结余率'), findsAtLeastNWidgets(1));
      expect(find.text('收入变化'), findsOneWidget);
      expect(find.text('支出变化'), findsOneWidget);
      expect(find.text('0 笔'), findsAtLeastNWidgets(1));
      expect(find.text('本月暂无趋势数据'), findsOneWidget);
      expect(find.text('本月暂无分类数据'), findsOneWidget);
      expect(find.text('¥0.00'), findsWidgets);
    });

    testWidgets('统计页核心区块使用分段入场动效', (tester) async {
      final repository = _FakeStatisticsRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(5));
    });

    testWidgets('统计刷新后恢复为最新数据', (tester) async {
      final repository = _FakeStatisticsRepository(
        dashboards: [
          _dashboard(categoryName: '餐饮', expense: 400),
          _dashboard(categoryName: '交通', expense: 120),
        ],
      );
      await _pumpPage(tester, repository);

      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('¥400.00'), findsWidgets);

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();

      expect(repository.dashboardCalls, 2);
      expect(find.text('餐饮'), findsNothing);
      expect(find.text('交通'), findsOneWidget);
      expect(find.text('¥120.00'), findsWidgets);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeStatisticsRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [statisticsRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: MobileStatisticsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeStatisticsRepository implements StatisticsRepository {
  _FakeStatisticsRepository({List<StatisticsDashboard>? dashboards})
    : dashboards = dashboards ?? [_dashboard()];

  final List<StatisticsDashboard> dashboards;
  var dashboardCalls = 0;
  var dashboardErrors = 0;

  @override
  Future<StatisticsDashboard> getDashboard(
    StatisticsDashboardQuery query,
  ) async {
    dashboardCalls += 1;
    if (dashboardErrors > 0) {
      dashboardErrors -= 1;
      throw StateError('统计加载失败');
    }
    final index = (dashboardCalls - 1).clamp(0, dashboards.length - 1);
    return dashboards[index];
  }

  @override
  Future<CategoryStatResponse?> getCategoryStats({
    required String month,
    required String type,
  }) async {
    return getDashboard(
      StatisticsDashboardQuery(month: month, categoryType: type),
    ).then((dashboard) => dashboard.categories);
  }

  @override
  Future<StatisticsOverviewData?> getOverview(String month) async {
    return getDashboard(
      StatisticsDashboardQuery(month: month, categoryType: 'expense'),
    ).then((dashboard) => dashboard.overview);
  }

  @override
  Future<TrendResponse?> getTrend(String month) async {
    return getDashboard(
      StatisticsDashboardQuery(month: month, categoryType: 'expense'),
    ).then((dashboard) => dashboard.trend);
  }
}

StatisticsDashboard _dashboard({
  String categoryName = '餐饮',
  double expense = 400,
  bool empty = false,
}) {
  return StatisticsDashboard(
    overview: StatisticsOverviewData(
      income: empty ? 0 : 1000,
      expense: empty ? 0 : expense,
      balance: empty ? 0 : 1000 - expense,
      incomeChange: empty ? 0 : 12,
      expenseChange: empty ? 0 : -8,
      dailyAverage: empty ? 0 : 20,
      transactionCount: empty ? 0 : 5,
    ),
    trend: TrendResponse(
      totalIncome: empty ? 0 : 1000,
      totalExpense: empty ? 0 : expense,
      items: empty
          ? const []
          : const [
              TrendItem(
                date: '2026-05-01',
                income: 1000,
                expense: 400,
                balance: 600,
              ),
            ],
    ),
    categories: CategoryStatResponse(
      total: empty ? 0 : expense,
      items: empty
          ? const []
          : [
              CategoryStatItem(
                categoryId: 'cat-1',
                categoryName: categoryName,
                icon: '🍽️',
                color: '#EF4444',
                amount: expense,
                percentage: 100,
                count: 5,
              ),
            ],
    ),
  );
}
