import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/statistics/presentation/mobile_statistics_page.dart';

void main() {
  group('MobileStatisticsPage', () {
    testWidgets('统计加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeStatisticsRepository()..dashboardErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.text('统计数据加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.dashboardCalls, 2);
      expect(
        find.byKey(const ValueKey('statistics-period-command-center')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('statistics-period-header')),
        findsOneWidget,
      );
      expect(find.textContaining('周期指挥台'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-data-cockpit')),
        findsNothing,
      );
      expect(find.text('现金流驾驶舱'), findsNothing);
      expect(find.text('可持续'), findsNothing);
      expect(find.text('收入池'), findsNothing);
      expect(find.text('支出池'), findsNothing);
      expect(find.text('结余效率'), findsNothing);
      expect(find.text('支出压力'), findsNothing);
      expect(find.text('趋势覆盖'), findsNothing);
      expect(find.text('首要分类'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-insight-deck')),
        findsNothing,
      );
      expect(find.text('数据洞察台'), findsNothing);
      expect(find.text('数据皮肤'), findsNothing);
      expect(find.textContaining('图表、分类和现金流语义色同步'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-theme-data-strip')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('statistics-evidence-rail')),
        findsNothing,
      );
      expect(find.text('AI 输入'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-ai-input-panel')),
        findsNothing,
      );
      expect(find.text('AI 分析输入质量'), findsNothing);
      expect(find.text('周报可分析'), findsNothing);
      expect(find.text('交易样本'), findsNothing);
      expect(find.text('趋势节点'), findsNothing);
      expect(find.text('分类样本'), findsNothing);
      expect(find.text('餐饮'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('statistics-category-rank-card')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('statistics-category-rank-card')),
        findsOneWidget,
      );
      expect(find.text('支出结构扫描'), findsNothing);
      expect(find.text('支出分类'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-category-rank-cat-1')),
        findsOneWidget,
      );
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('5 笔 · 100.0%'), findsOneWidget);
    });

    testWidgets('统计页展示空统计摘要', (tester) async {
      final repository = _FakeStatisticsRepository(
        dashboards: [_dashboard(empty: true)],
      );
      await _pumpPage(tester, repository);

      expect(find.text('交易笔数'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-period-command-center')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('statistics-period-header')),
        findsOneWidget,
      );
      expect(find.textContaining('周期指挥台'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-evidence-rail')),
        findsNothing,
      );
      expect(find.text('0 笔交易'), findsNothing);
      expect(find.text('AI 输入'), findsNothing);
      expect(find.text('现金流驾驶舱'), findsNothing);
      expect(find.text('支出压力'), findsNothing);
      expect(find.text('首要分类'), findsNothing);
      expect(find.text('暂无分类'), findsNothing);
      expect(find.text('数据洞察台'), findsNothing);
      expect(find.text('数据皮肤'), findsNothing);
      expect(find.text('默认稳健'), findsNothing);
      expect(find.text('趋势节点'), findsNothing);
      expect(find.text('分类样本'), findsNothing);
      expect(find.text('本月现金流持平'), findsNothing);
      expect(find.text('结余率'), findsNothing);
      expect(find.text('AI 分析输入质量'), findsNothing);
      expect(find.text('待积累'), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics-ai-input-panel')),
        findsNothing,
      );
      expect(find.text('收入变化'), findsNothing);
      expect(find.text('支出变化'), findsNothing);
      expect(find.text('0 笔'), findsNothing);
      await tester.scrollUntilVisible(find.text('本月还没有趋势'), 300);
      expect(find.text('本月还没有趋势'), findsOneWidget);
      expect(find.text('本月暂无趋势数据'), findsNothing);
      await tester.scrollUntilVisible(find.text('本月还没有分类'), 300);
      expect(find.text('本月还没有分类'), findsOneWidget);
      expect(find.text('本月暂无分类数据'), findsNothing);
      expect(find.text('¥0.00'), findsWidgets);
    });

    testWidgets('统计页核心区块保持清晰层级', (tester) async {
      final repository = _FakeStatisticsRepository();
      await _pumpPage(tester, repository);

      expect(
        find.byKey(const ValueKey('statistics-period-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statistics-category-rank-card')),
        findsOneWidget,
      );
      expect(find.text('统计'), findsOneWidget);
    });

    testWidgets('统计页分类排行默认只展示前五项', (tester) async {
      final repository = _FakeStatisticsRepository(
        dashboards: [_dashboard(categoryCount: 6)],
      );
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('statistics-category-rank-card')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('分类 1'), findsOneWidget);
      expect(find.text('分类 5'), findsOneWidget);
      expect(find.text('分类 6'), findsNothing);
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
      final now = DateTime.now();
      final previousMonth = DateTime(now.year, now.month - 1);
      expect(
        find.byKey(
          ValueKey(
            'statistics-previous-month-${previousMonth.year}-${previousMonth.month.toString().padLeft(2, '0')}',
          ),
        ),
        findsOneWidget,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileStatisticsPage)),
      );
      container.invalidate(
        statisticsDashboardProvider(
          StatisticsDashboardQuery(
            month: '${now.year}-${now.month.toString().padLeft(2, '0')}',
            categoryType: 'expense',
          ),
        ),
      );
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
  int categoryCount = 1,
}) {
  final categories = [
    for (var index = 0; index < categoryCount; index++)
      CategoryStatItem(
        categoryId: 'cat-${index + 1}',
        categoryName: categoryCount == 1 ? categoryName : '分类 ${index + 1}',
        icon: '🍽️',
        color: '#EF4444',
        amount: expense - index,
        percentage: categoryCount == 1 ? 100 : 100 / categoryCount,
        count: 5,
      ),
  ];
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
      items: empty ? const [] : categories,
    ),
  );
}
