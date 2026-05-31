import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/home/presentation/home_page.dart';

void main() {
  group('HomePage', () {
    testWidgets('首页数据加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeHomeRepository()..summaryErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('首页数据加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(repository.summaryCalls, 2);
      expect(find.text('净资产'), findsOneWidget);
      expect(find.text('现金'), findsOneWidget);
    });

    testWidgets('首页展示空预算和空统计摘要', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [_summary(accounts: const [], emptyBudget: true)],
      );
      await _pumpPage(tester, repository);

      expect(find.text('暂无账户，请先创建账户'), findsOneWidget);
      expect(find.text('本月已记 0 笔'), findsOneWidget);
      expect(find.text('本月暂未设置预算'), findsOneWidget);
      expect(find.text('¥0.00'), findsWidgets);
    });

    testWidgets('首页刷新后恢复为最新摘要', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [
          _summary(accountName: '现金', netAssets: 1280),
          _summary(accountName: '储蓄卡', netAssets: 2600),
        ],
      );
      await _pumpPage(tester, repository);

      expect(find.text('现金'), findsOneWidget);
      expect(find.text('¥1280.00'), findsWidgets);

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();

      expect(repository.summaryCalls, 2);
      expect(find.text('现金'), findsNothing);
      expect(find.text('储蓄卡'), findsOneWidget);
      expect(find.text('¥2600.00'), findsWidgets);
    });

    testWidgets('首页展示现金流、预算、快捷入口和家庭摘要', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [_summary(familyExpense: 320)],
      );
      await _pumpPage(tester, repository);

      expect(find.text('本月现金流'), findsOneWidget);
      expect(find.text('预算摘要'), findsOneWidget);
      expect(find.text('快速记账'), findsOneWidget);
      expect(find.text('家庭支出'), findsOneWidget);
      expect(find.text('成员A'), findsOneWidget);
      expect(find.text('¥320.00'), findsWidgets);
      expect(find.byType(PremiumSurface), findsWidgets);
      expect(find.byKey(const Key('family-home-summary-card')), findsOneWidget);
    });

    testWidgets('首页核心财务卡跟随主题色模板', (tester) async {
      final repository = _FakeHomeRepository();
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final hero = tester.widget<FinanceHeroCard>(
        find.byType(FinanceHeroCard).first,
      );
      expect(hero.accentColor, AppThemePalette.graphite.assetColor);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeHomeRepository repository, {
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: const HomePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({List<HomeSummary>? summaries})
    : summaries = summaries ?? [_summary()];

  final List<HomeSummary> summaries;
  var summaryCalls = 0;
  var summaryErrors = 0;

  @override
  Future<HomeSummary> getSummary() async {
    summaryCalls += 1;
    if (summaryErrors > 0) {
      summaryErrors -= 1;
      throw StateError('首页数据加载失败');
    }
    final index = (summaryCalls - 1).clamp(0, summaries.length - 1);
    return summaries[index];
  }
}

HomeSummary _summary({
  String accountName = '现金',
  double netAssets = 1280,
  List<Account>? accounts,
  bool emptyBudget = false,
  double familyExpense = 0,
}) {
  final accountList =
      accounts ??
      [
        Account(
          id: 'account-1',
          name: accountName,
          type: 'cash',
          icon: '💰',
          color: '#10B981',
          currentBalance: netAssets,
          isArchived: false,
        ),
      ];
  return HomeSummary(
    accounts: AccountListResponse(
      list: accountList,
      totalAssets: netAssets,
      totalLiabilities: 0,
      netAssets: netAssets,
    ),
    overview: StatisticsOverview(
      income: emptyBudget ? 0 : 1000,
      expense: emptyBudget ? 0 : 400,
      balance: emptyBudget ? 0 : 600,
      transactionCount: emptyBudget ? 0 : 5,
    ),
    budgetSummary: BudgetSummary(
      totalAmount: emptyBudget ? 0 : 3000,
      totalSpent: emptyBudget ? 0 : 1200,
      percentage: emptyBudget ? 0 : 40,
      dailyAvailable: emptyBudget ? 0 : 90,
      daysRemaining: emptyBudget ? 0 : 20,
      overBudgetCategories: const [],
    ),
    familySummary: FamilyHomeSummary(
      month: '2026-05',
      totalExpense: familyExpense,
      members: familyExpense > 0
          ? [
              FamilyHomeMemberSummary(
                memberID: 'member-1',
                name: '成员A',
                expenseTotal: familyExpense,
                count: 2,
              ),
            ]
          : const [],
    ),
  );
}
