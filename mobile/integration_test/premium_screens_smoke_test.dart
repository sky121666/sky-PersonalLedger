import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart'
    as ledger_account;
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/accounts/presentation/accounts_page.dart';
import 'package:personal_ledger/features/ai/data/ai_report_repository.dart';
import 'package:personal_ledger/features/ai/presentation/ai_reports_page.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/budgets/presentation/budget_page.dart';
import 'package:personal_ledger/features/categories/application/category_controller.dart';
import 'package:personal_ledger/features/categories/data/category.dart';
import 'package:personal_ledger/features/categories/data/category_repository.dart';
import 'package:personal_ledger/features/categories/presentation/categories_page.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/family/presentation/family_page.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/home/presentation/home_page.dart';
import 'package:personal_ledger/features/main/presentation/main_shell_page.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/statistics/presentation/mobile_statistics_page.dart';
import 'package:personal_ledger/features/tags/data/tag_repository.dart';
import 'package:personal_ledger/features/tags/presentation/tag_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/quick_transaction_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('premium target screens', () {
    for (final variant in _visualVariants) {
      testWidgets('renders premium shell navigation (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          _screenshotHost(_premiumShellApp(themeMode: variant.themeMode)),
        );
        await tester.pumpAndSettle();

        expect(find.text('shell-home'), findsOneWidget);
        expect(find.text('首页'), findsOneWidget);
        expect(find.text('明细'), findsOneWidget);
        expect(find.text('统计'), findsOneWidget);
        expect(find.text('我的'), findsOneWidget);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'main-shell-navigation-${variant.name}',
        );

        await tester.tap(find.text('明细'));
        await tester.pumpAndSettle();
        expect(find.text('shell-transactions'), findsOneWidget);

        await tester.tap(find.text('记一笔'));
        await tester.pumpAndSettle();
        expect(find.text('shell-quick-entry'), findsOneWidget);
        _expectStableVisualFrame(tester);
      });

      testWidgets(
        'renders premium home dashboard with family summary (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                homeRepositoryProvider.overrideWithValue(_FakeHomeRepository()),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const HomePage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('财务控制台'), findsOneWidget);
          expect(find.text('净资产'), findsOneWidget);
          expect(find.text('本月现金流'), findsOneWidget);
          expect(find.text('快速记账'), findsOneWidget);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'home-dashboard-top-${variant.name}',
          );

          await tester.scrollUntilVisible(find.text('家庭支出'), 320);
          expect(find.text('家庭支出'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('family-home-summary-card')),
            findsOneWidget,
          );

          await tester.scrollUntilVisible(find.text('预算摘要'), 360);
          expect(find.text('预算摘要'), findsOneWidget);
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'home-dashboard-family-budget-${variant.name}',
          );
        },
      );

      testWidgets(
        'renders premium quick transaction sheet form (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                transactionRepositoryProvider.overrideWithValue(
                  _FakeTransactionRepository(),
                ),
                familyMembersProvider.overrideWith(
                  (ref) async => _familyMembers,
                ),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const QuickTransactionPage(embedded: true),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('记一笔'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('transaction-amount')),
            findsOneWidget,
          );
          expect(find.text('分类'), findsOneWidget);
          expect(find.text('成员'), findsOneWidget);
          await tester.drag(find.byType(ListView).first, const Offset(0, -900));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('transaction-save')),
            findsOneWidget,
          );
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'quick-transaction-form-${variant.name}',
          );
        },
      );

      testWidgets('renders premium accounts control room (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountRepositoryProvider.overrideWithValue(
                _FakeAccountRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const AccountsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('账户'), findsOneWidget);
        expect(find.text('资产概览'), findsOneWidget);
        expect(find.text('正常账户'), findsOneWidget);
        expect(find.text('招商银行'), findsOneWidget);
        expect(find.text('住房贷款'), findsOneWidget);
        _expectStableVisualFrame(tester);

        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.text('已归档账户'), findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'accounts-control-room-${variant.name}',
        );
      });

      testWidgets('renders premium category library (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              categoryRepositoryProvider.overrideWithValue(
                _FakeCategoryRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const CategoriesPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('分类'), findsOneWidget);
        expect(find.text('支出分类库'), findsOneWidget);
        expect(find.text('餐饮'), findsOneWidget);
        expect(find.text('交通'), findsOneWidget);
        expect(find.text('系统分类'), findsWidgets);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'category-library-${variant.name}',
        );
      });

      testWidgets('renders premium tag library (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tagRepositoryProvider.overrideWithValue(_FakeTagRepository()),
            ],
            child: _screenshotHost(
              _premiumApp(themeMode: variant.themeMode, home: const TagPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('标签管理'), findsOneWidget);
        expect(find.text('标签库'), findsOneWidget);
        expect(find.text('工资收入'), findsOneWidget);
        expect(find.text('旅行'), findsOneWidget);
        expect(find.text('系统标签 · 使用 8 次'), findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'tag-library-${variant.name}',
        );
      });

      testWidgets('renders premium statistics dashboard (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              statisticsRepositoryProvider.overrideWithValue(
                _FakeStatisticsRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const MobileStatisticsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('统计分析'), findsOneWidget);
        expect(find.text('本月总支出'), findsOneWidget);
        expect(find.text('收支趋势'), findsOneWidget);
        _expectStableVisualFrame(tester);

        await tester.drag(find.byType(ListView).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(find.text('分类排行'), findsOneWidget);
        expect(find.text('餐饮'), findsOneWidget);
        expect(find.text('交通'), findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'statistics-dashboard-${variant.name}',
        );
      });

      testWidgets('renders premium budget control room (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              budgetRepositoryProvider.overrideWithValue(
                _FakeBudgetRepository(),
              ),
              categoryRepositoryProvider.overrideWithValue(
                _FakeCategoryRepository(),
              ),
              familyMembersProvider.overrideWith((ref) async => _familyMembers),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const BudgetPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('预算管理'), findsOneWidget);
        expect(find.text('本月预算总览'), findsOneWidget);
        expect(find.text('月度总预算'), findsOneWidget);
        expect(find.text('分类预算'), findsOneWidget);
        expect(find.text('餐饮'), findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);

        await tester.drag(find.byType(ListView).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(find.text('家庭成员预算'), findsOneWidget);
        expect(find.text('成员A'), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'budget-control-room-${variant.name}',
        );
      });

      testWidgets(
        'renders premium AI report content and expansion (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                aiReportsProvider.overrideWith((ref) async => _aiReports),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const AIReportsPage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('AI 财务报告'), findsOneWidget);
          expect(find.text('每周总结'), findsOneWidget);
          expect(find.text('已完成'), findsOneWidget);
          expect(find.text('DeepSeek / deepseek-v4-flash'), findsOneWidget);

          await tester.tap(find.text('每周总结'));
          await tester.pumpAndSettle();

          expect(find.text('支出结构稳定'), findsWidgets);
          expect(find.text('• 净现金流为正'), findsOneWidget);
          expect(find.text('• 餐饮预算接近上限'), findsOneWidget);
          expect(find.text('• 下周继续保持每日记录'), findsOneWidget);
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'ai-reports-expanded-${variant.name}',
          );
        },
      );

      testWidgets(
        'renders premium family hub summary and member states (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                familyMembersProvider.overrideWith(
                  (ref) async => _familyMembers,
                ),
                familySummaryProvider.overrideWith(
                  (ref) async => _familySummary,
                ),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const FamilyPage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('家庭成员'), findsOneWidget);
          expect(find.text('成员A'), findsWidgets);
          expect(find.text('成员B'), findsWidgets);
          expect(find.text('默认'), findsOneWidget);
          expect(find.text('停用'), findsOneWidget);
          expect(find.text('2026-05 家庭支出'), findsOneWidget);
          expect(find.text('¥320.00'), findsOneWidget);
          expect(find.text('成员支出排行'), findsOneWidget);
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'family-hub-summary-${variant.name}',
          );
        },
      );
    }
  });
}

const _screenshotDir = String.fromEnvironment('LEDGER_PREMIUM_SCREENSHOT_DIR');
final _screenshotBoundaryKey = GlobalKey();
const _visualVariants = [
  _VisualVariant(name: 'light', themeMode: ThemeMode.light),
  _VisualVariant(name: 'dark', themeMode: ThemeMode.dark),
];

class _VisualVariant {
  const _VisualVariant({required this.name, required this.themeMode});

  final String name;
  final ThemeMode themeMode;
}

Widget _premiumApp({required ThemeMode themeMode, required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    themeMode: themeMode,
    home: home,
  );
}

Widget _premiumShellApp({required ThemeMode themeMode}) {
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    themeMode: themeMode,
    routerConfig: _premiumShellRouter(),
  );
}

GoRouter _premiumShellRouter() {
  return GoRouter(
    initialLocation: AppRoutePaths.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShellPage(
          navigationShell: navigationShell,
          quickTransactionBuilder: (_) =>
              const _ShellMarker('shell-quick-entry'),
        ),
        branches: [
          _shellBranch(AppRoutePaths.home, 'shell-home'),
          _shellBranch(AppRoutePaths.transactions, 'shell-transactions'),
          _shellBranch(AppRoutePaths.statistics, 'shell-statistics'),
          _shellBranch(AppRoutePaths.profile, 'shell-profile'),
        ],
      ),
    ],
  );
}

StatefulShellBranch _shellBranch(String path, String label) {
  return StatefulShellBranch(
    routes: [
      GoRoute(path: path, builder: (context, state) => _ShellMarker(label)),
    ],
  );
}

class _ShellMarker extends StatelessWidget {
  const _ShellMarker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

Widget _screenshotHost(Widget child) {
  return RepaintBoundary(key: _screenshotBoundaryKey, child: child);
}

void _expectStableVisualFrame(WidgetTester tester) {
  final exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: 'Premium screen should not overflow or throw',
  );
}

Future<void> _prepareScreenshotCapture(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  if (Platform.isAndroid) {
    await binding.convertFlutterSurfaceToImage();
  }
}

Future<void> _capturePremiumScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await tester.pumpAndSettle();
  final bytes = await _takeScreenshotBytes(binding, name);
  expect(bytes, isNotEmpty);

  if (_screenshotDir.isEmpty ||
      !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    return;
  }

  final directory = Directory(_screenshotDir);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File('${directory.path}/$name.png').writeAsBytesSync(bytes, flush: true);
}

Future<List<int>> _takeScreenshotBytes(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  try {
    return await binding.takeScreenshot(name);
  } on MissingPluginException {
    return _takeRepaintBoundaryScreenshot();
  }
}

Future<List<int>> _takeRepaintBoundaryScreenshot() async {
  final boundary =
      _screenshotBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('Screenshot boundary is not mounted');
  }
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('Screenshot byte data is empty');
  }
  return data.buffer.asUint8List();
}

const _familyMembers = [
  FamilyMember(
    id: 'member-1',
    name: '成员A',
    relationship: '家人',
    color: '#2563EB',
    isDefault: true,
    isEnabled: true,
  ),
  FamilyMember(
    id: 'member-2',
    name: '成员B',
    relationship: '子女',
    color: '#059669',
    isDefault: false,
    isEnabled: false,
  ),
];

const _familySummary = FamilySummary(
  month: '2026-05',
  totalExpense: 320,
  members: [
    FamilyMemberSummary(
      memberId: 'member-1',
      name: '成员A',
      relationship: '家人',
      color: '#2563EB',
      expenseTotal: 200,
      count: 3,
    ),
    FamilyMemberSummary(
      memberId: 'member-2',
      name: '成员B',
      relationship: '子女',
      color: '#059669',
      expenseTotal: 120,
      count: 2,
    ),
  ],
);

const _aiReports = [
  AIReportSummary(
    id: 'report-1',
    reportType: 'weekly',
    status: 'completed',
    periodStart: '2026-05-18T00:00:00Z',
    periodEnd: '2026-05-24T23:59:59Z',
    providerName: 'DeepSeek',
    model: 'deepseek-v4-flash',
    contentJson:
        '{"summary":"支出结构稳定","highlights":["净现金流为正"],"risks":["餐饮预算接近上限"],"suggestions":["下周继续保持每日记录"]}',
  ),
];

class _FakeHomeRepository implements HomeRepository {
  @override
  Future<HomeSummary> getSummary() async {
    return const HomeSummary(
      accounts: AccountListResponse(
        list: [
          Account(
            id: 'account-1',
            name: '现金',
            type: 'cash',
            icon: 'cash',
            color: '#10B981',
            currentBalance: 1280,
            isArchived: false,
          ),
        ],
        totalAssets: 1280,
        totalLiabilities: 0,
        netAssets: 1280,
      ),
      overview: StatisticsOverview(
        income: 1000,
        expense: 400,
        balance: 600,
        transactionCount: 5,
      ),
      budgetSummary: BudgetSummary(
        totalAmount: 3000,
        totalSpent: 1200,
        percentage: 40,
        dailyAvailable: 90,
        daysRemaining: 20,
        overBudgetCategories: [],
      ),
      familySummary: FamilyHomeSummary(
        month: '2026-05',
        totalExpense: 320,
        members: [
          FamilyHomeMemberSummary(
            memberID: 'member-1',
            name: '成员A',
            expenseTotal: 320,
            count: 2,
          ),
        ],
      ),
    );
  }
}

class _FakeTransactionRepository implements TransactionRepository {
  @override
  Future<void> batchDelete(List<String> ids) async {}

  @override
  Future<TransactionItem> create(TransactionFormData formData) async {
    return _transactionFromForm('transaction-1', formData);
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<TransactionItem> getById(String id) async {
    return TransactionItem(
      id: id,
      type: TransactionType.expense,
      amount: 1,
      accountId: 'account-1',
      categoryId: 'category-expense',
      transactionDate: DateTime(2026, 5, 14),
    );
  }

  @override
  Future<TransactionListResult> list(TransactionListQuery query) async {
    return const TransactionListResult(
      list: [],
      total: 0,
      page: 1,
      pageSize: 20,
    );
  }

  @override
  Future<List<LedgerAccount>> listAccounts() async {
    return const [
      LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
      LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank_card'),
    ];
  }

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    return const [
      LedgerCategory(id: 'category-expense', name: '餐饮', type: 'expense'),
      LedgerCategory(id: 'category-income', name: '工资', type: 'income'),
    ];
  }

  @override
  Future<List<LedgerTag>> listTags() async {
    return const [LedgerTag(id: 'tag-1', name: '日常')];
  }

  @override
  Future<TransactionItem> update(
    String id,
    TransactionFormData formData,
  ) async {
    return _transactionFromForm(id, formData);
  }

  TransactionItem _transactionFromForm(
    String id,
    TransactionFormData formData,
  ) {
    return TransactionItem(
      id: id,
      type: formData.type,
      amount: formData.amount,
      accountId: formData.accountId,
      categoryId: formData.categoryId,
      transactionDate: formData.transactionDate,
      remark: formData.remark,
      images: formData.images,
      tags: formData.tags,
      toAccountId: formData.toAccountId,
      memberId: formData.memberId,
      paidByMemberId: formData.paidByMemberId,
    );
  }
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<void> archive(String id, bool isArchived) async {}

  @override
  Future<ledger_account.Account> create(
    ledger_account.CreateAccountRequest request,
  ) async {
    return _accounts.first;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<ledger_account.Account> getById(String id) async {
    return _accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<ledger_account.AccountListResult> list({
    bool includeArchived = true,
  }) async {
    return const ledger_account.AccountListResult(
      accounts: _accounts,
      totalAssets: 1500,
      totalLiabilities: 480000,
      netAssets: -478500,
    );
  }

  @override
  Future<ledger_account.Account> update(
    String id,
    ledger_account.UpdateAccountRequest request,
  ) async {
    return _accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<void> updateSort(List<String> ids) async {}
}

const _accounts = [
  ledger_account.Account(
    id: 'bank-card',
    name: '招商银行',
    type: 'bank_card',
    icon: 'card',
    color: '#2563EB',
    initialBalance: 1000,
    currentBalance: 1200,
    isArchived: false,
    sortOrder: 1,
  ),
  ledger_account.Account(
    id: 'mortgage',
    name: '住房贷款',
    type: 'mortgage',
    icon: 'home',
    color: '#EF4444',
    initialBalance: 500000,
    currentBalance: 480000,
    paymentDay: 20,
    billingDay: 1,
    creditLimit: 800000,
    interestRate: 3.25,
    startDate: '2026-01-01',
    targetDate: '2056-01-01',
    remark: '首套房商贷',
    isArchived: false,
    sortOrder: 2,
  ),
  ledger_account.Account(
    id: 'wallet',
    name: '旧钱包',
    type: 'cash',
    icon: 'cash',
    color: '#64748B',
    initialBalance: 0,
    currentBalance: 300,
    isArchived: true,
    sortOrder: 3,
  ),
];

class _FakeBudgetRepository implements BudgetRepository {
  @override
  Future<void> deleteBudget(String id) async {}

  @override
  Future<BudgetListResponse?> getList({String? month}) async {
    return _budgetList;
  }

  @override
  Future<BudgetItem?> setCategoryBudget({
    required String categoryId,
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) async {
    return null;
  }

  @override
  Future<BudgetItem?> setTotalBudget({
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) async {
    return null;
  }
}

class _FakeTagRepository implements TagRepository {
  @override
  Future<TagItem> create(TagRequest request) async {
    return _tags.first;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<TagItem>> list() async {
    return _tags;
  }

  @override
  Future<TagItem> update(String id, TagRequest request) async {
    return _tags.firstWhere((tag) => tag.id == id);
  }
}

const _tags = [
  TagItem(
    id: 'tag-system',
    userId: 1,
    name: '工资收入',
    color: '#22C55E',
    icon: 'wallet',
    isSystem: true,
    usedCount: 8,
  ),
  TagItem(
    id: 'tag-travel',
    userId: 1,
    name: '旅行',
    color: '#3B82F6',
    icon: 'star',
    usedCount: 2,
  ),
];

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Future<Category> create(CreateCategoryRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<CategoryListResult> list(CategoryType type) async {
    return const CategoryListResult(categories: _expenseCategories);
  }

  @override
  Future<Category> update(String id, UpdateCategoryRequest request) {
    throw UnimplementedError();
  }
}

const _budgetList = BudgetListResponse(
  totalBudget: BudgetItem(
    id: 'budget-total',
    categoryId: null,
    categoryName: '',
    amount: 3000,
    spent: 1200,
    remaining: 1800,
    percentage: 40,
    alertThreshold: 80,
  ),
  categoryBudgets: [
    BudgetItem(
      id: 'budget-food',
      categoryId: 'cat-food',
      categoryName: '餐饮',
      amount: 800,
      spent: 700,
      remaining: 100,
      percentage: 87,
      alertThreshold: 80,
    ),
    BudgetItem(
      id: 'budget-traffic',
      categoryId: 'cat-traffic',
      categoryName: '交通',
      amount: 600,
      spent: 210,
      remaining: 390,
      percentage: 35,
      alertThreshold: 80,
    ),
  ],
  memberBudgets: [
    BudgetItem(
      id: 'budget-member-a',
      categoryId: null,
      categoryName: '',
      memberId: 'member-1',
      memberName: '成员A',
      amount: 1200,
      spent: 420,
      remaining: 780,
      percentage: 35,
      alertThreshold: 80,
    ),
  ],
);

const _expenseCategories = [
  Category(
    id: 'cat-food',
    name: '餐饮',
    type: CategoryType.expense,
    icon: 'food',
    color: '#EF4444',
    isSystem: true,
    sortOrder: 1,
  ),
  Category(
    id: 'cat-traffic',
    name: '交通',
    type: CategoryType.expense,
    icon: 'transport',
    color: '#2563EB',
    isSystem: true,
    sortOrder: 2,
  ),
  Category(
    id: 'cat-home',
    name: '家庭',
    type: CategoryType.expense,
    icon: 'home',
    color: '#8B5CF6',
    isSystem: true,
    sortOrder: 3,
  ),
];

class _FakeStatisticsRepository implements StatisticsRepository {
  @override
  Future<StatisticsDashboard> getDashboard(
    StatisticsDashboardQuery query,
  ) async {
    return _statisticsDashboard;
  }

  @override
  Future<CategoryStatResponse?> getCategoryStats({
    required String month,
    required String type,
  }) async {
    return _statisticsDashboard.categories;
  }

  @override
  Future<StatisticsOverviewData?> getOverview(String month) async {
    return _statisticsDashboard.overview;
  }

  @override
  Future<TrendResponse?> getTrend(String month) async {
    return _statisticsDashboard.trend;
  }
}

const _statisticsDashboard = StatisticsDashboard(
  overview: StatisticsOverviewData(
    income: 12800,
    expense: 4680,
    balance: 8120,
    incomeChange: 8,
    expenseChange: -4,
    dailyAverage: 156,
    transactionCount: 36,
  ),
  trend: TrendResponse(
    totalIncome: 12800,
    totalExpense: 4680,
    items: [
      TrendItem(date: '2026-05-01', income: 3200, expense: 900, balance: 2300),
      TrendItem(date: '2026-05-08', income: 2800, expense: 1100, balance: 1700),
      TrendItem(date: '2026-05-15', income: 3400, expense: 1320, balance: 2080),
      TrendItem(date: '2026-05-22', income: 3400, expense: 1360, balance: 2040),
    ],
  ),
  categories: CategoryStatResponse(
    total: 4680,
    items: [
      CategoryStatItem(
        categoryId: 'cat-food',
        categoryName: '餐饮',
        icon: 'food',
        color: '#EF4444',
        amount: 1680,
        percentage: 35.9,
        count: 14,
      ),
      CategoryStatItem(
        categoryId: 'cat-transport',
        categoryName: '交通',
        icon: 'transport',
        color: '#2563EB',
        amount: 920,
        percentage: 19.7,
        count: 8,
      ),
      CategoryStatItem(
        categoryId: 'cat-family',
        categoryName: '家庭',
        icon: 'family',
        color: '#8B5CF6',
        amount: 760,
        percentage: 16.2,
        count: 6,
      ),
    ],
  ),
);
