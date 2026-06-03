import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/home/presentation/home_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      await tester.scrollUntilVisible(
        find.text('现金'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('现金'), findsOneWidget);
    });

    testWidgets('首页展示空预算和空统计摘要', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [_summary(accounts: const [], emptyBudget: true)],
      );
      await _pumpPage(tester, repository);

      expect(find.text('主题仪表盘'), findsNothing);
      expect(find.text('当前主题'), findsNothing);
      expect(find.text('行动编排层'), findsNothing);
      expect(
        find.byKey(const ValueKey('quick-home-action-evidence-rail')),
        findsNothing,
      );
      expect(find.text('入口证据'), findsNothing);
      expect(find.text('三类交易'), findsNothing);
      expect(find.text('未设置'), findsNothing);
      expect(find.text('AI 周报'), findsNothing);
      expect(
        find.byKey(const ValueKey('home-decision-evidence-rail')),
        findsNothing,
      );
      expect(find.text('0 笔记录'), findsNothing);
      expect(find.text('预算缺口'), findsNothing);
      expect(find.text('AI 输入就绪'), findsNothing);
      expect(find.text('现金流稳定'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('还没有账户'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('还没有账户'), findsOneWidget);
      expect(find.text('0 笔'), findsOneWidget);
      expect(find.text('本月无现金流'), findsAtLeastNWidgets(1));
      expect(find.text('等待首笔记录'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('本月未设置预算'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本月未设置预算'), findsOneWidget);
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

      await tester.scrollUntilVisible(
        find.text('现金'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('现金'), findsOneWidget);
      expect(find.text('¥1280.00'), findsWidgets);

      await tester.tap(find.byTooltip('刷新首页概览'));
      await tester.pumpAndSettle();

      expect(repository.summaryCalls, 2);
      expect(find.text('现金'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('储蓄卡'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('储蓄卡'), findsOneWidget);
      expect(find.text('¥2600.00'), findsWidgets);
    });

    testWidgets('首页交易项默认不展开备注，点击展开后才显示', (tester) async {
      final repository = _FakeHomeRepository(summaries: [_summary()]);
      await _pumpPage(tester, repository);

      final expandToggle = find.byTooltip('展开备注').first;
      await tester.scrollUntilVisible(
        expandToggle,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(expandToggle, findsOneWidget);
      expect(find.text('午餐'), findsNothing);

      await tester.tap(expandToggle);
      await tester.pumpAndSettle();
      expect(find.text('午餐'), findsOneWidget);

      await tester.tap(find.byTooltip('收起备注').first);
      await tester.pumpAndSettle();
      expect(find.text('午餐'), findsNothing);
    });

    testWidgets('首页展示现金流、预算、快捷入口和家庭摘要', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [_summary(familyExpense: 320)],
      );
      await _pumpPage(tester, repository);

      expect(find.text('主题仪表盘'), findsNothing);
      expect(find.text('当前模板同步首页、家庭账本、AI 报告和财务语义色。'), findsNothing);
      expect(find.text('当前主题'), findsNothing);
      expect(find.text('预算已接入'), findsNothing);
      expect(
        find.byKey(const ValueKey('home-action-orchestration-panel')),
        findsNothing,
      );
      expect(find.text('行动编排层'), findsNothing);
      expect(find.text('把记账、预算、家庭和 AI 周报串成一个可执行的首页工作流。'), findsNothing);
      expect(find.text('快速记账'), findsNothing);
      expect(find.text('5 笔'), findsOneWidget);
      expect(find.text('预算守护'), findsNothing);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('家庭协同'), findsNothing);
      expect(find.text('1 人'), findsNothing);
      expect(find.text('AI 周报'), findsNothing);
      expect(find.text('可分析'), findsNothing);
      expect(
        find.byKey(const ValueKey('home-decision-evidence-rail')),
        findsNothing,
      );
      expect(find.text('5 笔记录'), findsNothing);
      expect(find.text('预算输入'), findsNothing);
      expect(find.text('AI 输入就绪'), findsNothing);
      expect(find.text('家庭数据在线'), findsNothing);
      expect(find.text('本月现金流'), findsOneWidget);
      expect(find.text('最近交易'), findsOneWidget);
      expect(find.text('当日交易'), findsOneWidget);
      expect(find.byTooltip('退出登录'), findsNothing);
      expect(find.text('全部'), findsNothing);
      expect(find.byTooltip('查看全部明细'), findsOneWidget);
      expect(find.text('餐饮'), findsWidgets);
      expect(find.text('-¥28.00'), findsWidgets);
      expect(find.text('现金流充沛'), findsNothing);
      expect(find.text('结余率 60%'), findsNothing);
      expect(find.text('本月趋势已同步'), findsNothing);
      expect(find.text('快速记账'), findsNothing);
      expect(
        find.byKey(const ValueKey('quick-home-action-evidence-rail')),
        findsNothing,
      );
      expect(find.text('入口证据'), findsNothing);
      expect(find.text('三类交易'), findsNothing);
      expect(find.text('家庭支出'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('family-home-evidence-rail')),
        findsNothing,
      );
      expect(find.text('家庭证据 3/3'), findsNothing);
      expect(find.text('1 人在线'), findsNothing);
      expect(find.text('家庭协同中'), findsNothing);
      expect(find.text('成员A'), findsOneWidget);
      expect(find.text('¥320.00'), findsWidgets);
      expect(find.byType(PremiumSurface), findsWidgets);
      expect(find.byKey(const Key('family-home-summary-card')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-theme-signal-panel')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('预算摘要'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('预算摘要'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-budget-summary-card')),
        findsOneWidget,
      );
      expect(find.text('已设置'), findsOneWidget);
      expect(find.text('剩余预算'), findsOneWidget);
      expect(find.text('日可用'), findsOneWidget);
      expect(find.text('剩余天数'), findsOneWidget);
    });

    testWidgets('首页核心财务卡跟随主题色模板', (tester) async {
      final repository = _FakeHomeRepository();
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final hero = tester.widget<FinanceHeroCard>(
        find.byType(FinanceHeroCard).first,
      );
      expect(hero.accentColor, AppThemePalette.graphite.assetColor);
      expect(find.text('石墨蓝'), findsNothing);
    });

    testWidgets('首页家庭摘要跟随主题色模板', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [_summary(familyExpense: 320)],
      );
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final familyCard = tester.widget<PremiumSurface>(
        find.byKey(const Key('family-home-summary-card')),
      );
      expect(familyCard.accentColor, AppThemePalette.graphite.incomeColor);
    });

    testWidgets('首页账户概览使用现代化账户数据条目', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [
          _summary(
            accounts: const [
              Account(
                id: 'cash-1',
                name: '现金钱包',
                type: 'cash',
                icon: '💰',
                color: '#10B981',
                currentBalance: 1280,
                isArchived: false,
              ),
              Account(
                id: 'credit-1',
                name: '信用卡',
                type: 'credit',
                icon: '💳',
                color: '#EF4444',
                currentBalance: 860,
                isArchived: false,
              ),
            ],
          ),
        ],
      );
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-account-overview-card')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-account-overview-card')),
        findsOneWidget,
      );
      expect(find.text('资产、负债与现金账户一屏扫读'), findsNothing);
      expect(find.text('2 个'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-account-line-cash-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-account-line-credit-1')),
        findsOneWidget,
      );
      expect(find.text('资产账户'), findsOneWidget);
      expect(find.text('可用余额'), findsOneWidget);
      expect(find.text('负债账户'), findsOneWidget);
      expect(find.text('待偿还'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('home-account-line-credit-1')),
          matching: find.byType(Semantics),
        ),
        findsWidgets,
      );
    });

    testWidgets('首页账户概览优先展示非零余额账户', (tester) async {
      final repository = _FakeHomeRepository(
        summaries: [
          _summary(
            netAssets: 1000,
            accounts: const [
              Account(
                id: 'empty-cash',
                name: '现金',
                type: 'cash',
                icon: '💰',
                color: '#10B981',
                currentBalance: 0,
                isArchived: false,
              ),
              Account(
                id: 'living-cash',
                name: '生活现金',
                type: 'cash',
                icon: '💰',
                color: '#0EA5E9',
                currentBalance: 1000,
                isArchived: false,
              ),
              Account(
                id: 'empty-bank',
                name: '银行卡',
                type: 'bank',
                icon: '💳',
                color: '#6366F1',
                currentBalance: 0,
                isArchived: false,
              ),
              Account(
                id: 'loan',
                name: '房贷',
                type: 'loan',
                icon: '🏦',
                color: '#EF4444',
                currentBalance: 300000,
                isArchived: false,
              ),
            ],
          ),
        ],
      );
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-account-overview-card')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('4 个'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-account-line-living-cash')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-account-line-loan')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-account-line-empty-cash')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-account-line-empty-bank')),
        findsNothing,
      );
    });

    testWidgets('FinanceHeroCard 默认跟随主题资产色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(AppThemePalette.graphite),
          home: const Scaffold(
            body: FinanceHeroCard(label: '默认资产', amount: 1280, metrics: []),
          ),
        ),
      );

      final surface = tester.widget<PremiumSurface>(
        find.byType(PremiumSurface).first,
      );
      final badge = tester.widget<IconBadge>(find.byType(IconBadge).first);
      expect(surface.accentColor, AppThemePalette.graphite.assetColor);
      expect(badge.color, AppThemePalette.graphite.assetColor);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeHomeRepository repository, {
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  SharedPreferences.setMockInitialValues({'app_theme_palette': palette.id});
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
  var dateTransactionCalls = 0;

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

  @override
  Future<List<TransactionItem>> listRecentTransactions() async {
    return summaries.first.recentTransactions;
  }

  @override
  Future<List<TransactionItem>> listTransactionsForDate(DateTime date) async {
    dateTransactionCalls += 1;
    return summaries.first.recentTransactions;
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
    recentTransactions: [
      TransactionItem(
        id: 'tx-1',
        type: TransactionType.expense,
        amount: 28,
        accountId: 'account-1',
        categoryId: 'category-food',
        transactionDate: DateTime(2026, 5, 20),
        remark: '午餐',
        account: const LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
        category: const LedgerCategory(
          id: 'category-food',
          name: '餐饮',
          type: 'expense',
        ),
      ),
    ],
  );
}
