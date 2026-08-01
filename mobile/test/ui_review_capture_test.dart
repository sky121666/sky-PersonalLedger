import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/attachments/data/attachment_picker_service.dart';
import 'package:personal_ledger/features/attachments/data/attachment_repository.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart'
    as home_data;
import 'package:personal_ledger/features/home/presentation/home_page.dart';
import 'package:personal_ledger/features/lendings/data/lending_repository.dart';
import 'package:personal_ledger/features/lendings/presentation/lending_page.dart';
import 'package:personal_ledger/features/main/presentation/main_shell_page.dart';
import 'package:personal_ledger/features/profile/presentation/profile_page.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_draft.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_repository.dart';
import 'package:personal_ledger/features/smart_quick_ledger/presentation/smart_quick_ledger_page.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/statistics/presentation/mobile_statistics_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/quick_transaction_page.dart';
import 'package:personal_ledger/features/transactions/presentation/transaction_details_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outputDir = String.fromEnvironment(
  'LEDGER_REVIEW_SCREENSHOT_DIR',
  defaultValue: '/tmp/sky-personalledger/ui-review',
);
const _runUiReviewCapture = bool.fromEnvironment('RUN_UI_REVIEW_CAPTURE');

final _boundaryKey = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!_runUiReviewCapture) {
    test(
      'UI review capture is disabled in default run',
      () {
        return;
      },
      skip:
          'Set --dart-define=RUN_UI_REVIEW_CAPTURE=true to run capture tests.',
    );
    return;
  }

  setUpAll(_loadReviewFonts);

  group('UI review capture', () {
    testWidgets('capture home page', (tester) async {
      await _preparePhoneViewport(tester);
      SharedPreferences.setMockInitialValues({
        'app_theme_palette': AppThemePalette.teal.id,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            home_data.homeRepositoryProvider.overrideWithValue(
              _FakeHomeRepository(),
            ),
          ],
          child: _host(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _reviewTheme(),
              home: const HomePage(),
            ),
          ),
        ),
      );
      await _stabilize(tester);

      await _capture(tester, 'home-phone');
    });

    for (final target in const [
      (name: 'home', path: AppRoutePaths.home),
      (name: 'transactions', path: AppRoutePaths.transactions),
      (name: 'statistics', path: AppRoutePaths.statistics),
      (name: 'profile', path: AppRoutePaths.profile),
    ]) {
      testWidgets('capture Apple minimal ${target.name} shell page', (
        tester,
      ) async {
        await _pumpCoreShell(tester, initialLocation: target.path);
        await _capture(tester, 'apple-minimal-${target.name}-shell-phone');
      });
    }

    testWidgets('capture Apple minimal quick sheet', (tester) async {
      await _pumpCoreShell(tester, initialLocation: AppRoutePaths.home);
      await tester.tap(
        find.byKey(const ValueKey('main-shell-quick-transaction')),
      );
      await _stabilize(tester);
      await _capture(tester, 'apple-minimal-quick-sheet-phone');
    });

    testWidgets('capture quick transaction collapsed and expanded', (
      tester,
    ) async {
      await _preparePhoneViewport(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transactionRepositoryProvider.overrideWithValue(
              _FakeTransactionRepository(),
            ),
            familyMembersProvider.overrideWith((ref) async => _familyMembers),
            themeControllerProvider.overrideWith(
              (ref) => _FixedThemeController(AppThemePalette.teal),
            ),
            attachmentPickerServiceProvider.overrideWithValue(
              const _EmptyAttachmentPickerService(),
            ),
            attachmentRepositoryProvider.overrideWithValue(
              _FakeAttachmentRepository(),
            ),
          ],
          child: _host(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _reviewTheme(),
              home: const Scaffold(body: QuickTransactionPage(embedded: true)),
            ),
          ),
        ),
      );
      await _stabilize(tester);

      await _capture(tester, 'quick-transaction-collapsed-phone');

      await tester.tap(find.byKey(const ValueKey('transaction-more-options')));
      await _stabilize(tester);
      await _capture(tester, 'quick-transaction-expanded-phone');
    });

    testWidgets('capture lending page', (tester) async {
      await _preparePhoneViewport(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lendingRepositoryProvider.overrideWithValue(
              _FakeLendingRepository(),
            ),
            themeControllerProvider.overrideWith(
              (ref) => _FixedThemeController(AppThemePalette.teal),
            ),
            accountRepositoryProvider.overrideWithValue(
              _FakeAccountRepository(),
            ),
          ],
          child: _host(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _reviewTheme(),
              home: const LendingPage(),
            ),
          ),
        ),
      );
      await _stabilize(tester);

      await _capture(tester, 'lending-phone');
    });

    testWidgets('capture smart quick ledger Android page', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pumpSmartQuickLedger(tester, initialDrafts: [_smartLedgerDraft]);

        await _capture(tester, 'smart-quick-ledger-android-phone');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('capture smart quick ledger iOS import flow', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pumpSmartQuickLedger(tester, initialDrafts: const []);

        await _capture(tester, 'smart-quick-ledger-ios-phone');
        final importButton = find.byKey(
          const ValueKey('smart-ledger-open-import'),
        );
        await tester.scrollUntilVisible(importButton, 120);
        await tester.tap(importButton);
        await _stabilize(tester);
        await _capture(tester, 'smart-quick-ledger-ios-import-sheet-phone');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

Future<void> _loadReviewFonts() async {
  await Future.wait([
    _loadFont('ReviewSans', '/Library/Fonts/Arial Unicode.ttf'),
    _loadFont(
      'MaterialIcons',
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  ]);
}

Future<void> _loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

ThemeData _reviewTheme() {
  final base = AppTheme.lightTheme();
  final reviewLabel = (base.textTheme.labelLarge ?? const TextStyle()).copyWith(
    fontFamily: 'ReviewSans',
  );
  final reviewButtonLabel = reviewLabel.copyWith(fontWeight: FontWeight.w600);
  ButtonStyle reviewButtonStyle(ButtonStyle? style) {
    return (style ?? const ButtonStyle()).copyWith(
      textStyle: WidgetStatePropertyAll(reviewButtonLabel),
    );
  }

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'ReviewSans'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'ReviewSans'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'ReviewSans',
      ),
      toolbarTextStyle: base.appBarTheme.toolbarTextStyle?.copyWith(
        fontFamily: 'ReviewSans',
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      selectedIcon: base.segmentedButtonTheme.selectedIcon,
      style: base.segmentedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(reviewLabel),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: reviewButtonStyle(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: reviewButtonStyle(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: reviewButtonStyle(base.textButtonTheme.style),
    ),
  );
}

Future<void> _pumpCoreShell(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  await _preparePhoneViewport(tester);
  SharedPreferences.setMockInitialValues({
    'app_theme_palette': AppThemePalette.teal.id,
  });

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShellPage(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.transactions,
                builder: (context, state) => const TransactionDetailsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.statistics,
                builder: (context, state) => const MobileStatisticsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.profile,
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        home_data.homeRepositoryProvider.overrideWithValue(
          _FakeHomeRepository(),
        ),
        transactionRepositoryProvider.overrideWithValue(
          _FakeTransactionRepository(),
        ),
        statisticsRepositoryProvider.overrideWithValue(
          _FakeStatisticsRepository(),
        ),
        familyMembersProvider.overrideWith((ref) async => _familyMembers),
        themeControllerProvider.overrideWith(
          (ref) => _FixedThemeController(AppThemePalette.teal),
        ),
        attachmentPickerServiceProvider.overrideWithValue(
          const _EmptyAttachmentPickerService(),
        ),
        attachmentRepositoryProvider.overrideWithValue(
          _FakeAttachmentRepository(),
        ),
      ],
      child: _host(
        MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: _reviewTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await _stabilize(tester);
}

Future<void> _pumpSmartQuickLedger(
  WidgetTester tester, {
  required List<QuickLedgerDraft> initialDrafts,
}) async {
  await _preparePhoneViewport(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickLedgerDraftsProvider.overrideWith(
          (ref) => QuickLedgerDraftController(
            transactionWriter: const _ReviewQuickLedgerWriter(),
            initialDrafts: initialDrafts,
          ),
        ),
      ],
      child: _host(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _reviewTheme(),
          home: const SmartQuickLedgerPage(),
        ),
      ),
    ),
  );
  await _stabilize(tester);
}

final _smartLedgerDraft = QuickLedgerDraft(
  id: 'review-smart-ledger-draft',
  source: QuickLedgerDraftSource.androidNotification,
  sourceName: '微信支付',
  type: TransactionType.expense,
  amount: 38.9,
  merchant: '瑞幸咖啡',
  occurredAt: DateTime(2026, 7, 31, 9, 18),
  confidence: 0.92,
  suggestedAccountName: '微信钱包',
  suggestedCategoryName: '餐饮',
);

class _ReviewQuickLedgerWriter implements QuickLedgerTransactionWriter {
  const _ReviewQuickLedgerWriter();

  @override
  Future<List<LedgerAccount>> listAccounts() async => const [];

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async => const [];

  @override
  Future<TransactionItem> create(TransactionFormData formData) {
    throw UnsupportedError('截图流程不会直接创建交易');
  }
}

Widget _host(Widget child) {
  return RepaintBoundary(key: _boundaryKey, child: child);
}

Future<void> _preparePhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _stabilize(tester);
  final file = File('$_outputDir/$name.png');
  file.parent.createSync(recursive: true);
  await expectLater(find.byKey(_boundaryKey), matchesGoldenFile(file.path));
}

Future<void> _stabilize(WidgetTester tester) async {
  for (var index = 0; index < 6; index += 1) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

class _FixedThemeController extends ThemeController {
  _FixedThemeController(AppThemePalette palette) {
    state = AppThemeSettings(palette: palette);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> setPalette(AppThemePalette palette) async {
    state = state.copyWith(palette: palette);
  }
}

class _FakeHomeRepository implements home_data.HomeRepository {
  @override
  Future<home_data.HomeSummary> getSummary({
    home_data.HomeSummaryQuery? query,
  }) async => home_data.HomeSummary(
    accounts: const home_data.AccountListResponse(
      list: [
        home_data.Account(
          id: 'account-1',
          name: '现金',
          type: 'cash',
          icon: '💰',
          color: '#10B981',
          currentBalance: 1280,
          isArchived: false,
        ),
        home_data.Account(
          id: 'account-2',
          name: '储蓄卡',
          type: 'bank',
          icon: '💳',
          color: '#2563EB',
          currentBalance: 5200,
          isArchived: false,
        ),
        home_data.Account(
          id: 'account-3',
          name: '花呗',
          type: 'credit',
          icon: '🏦',
          color: '#EF4444',
          currentBalance: 860,
          isArchived: false,
        ),
      ],
      totalAssets: 6480,
      totalLiabilities: 860,
      netAssets: 5620,
    ),
    overview: const home_data.StatisticsOverview(
      income: 10000,
      expense: 4200,
      balance: 5800,
      transactionCount: 28,
    ),
    budgetSummary: const home_data.BudgetSummary(
      totalAmount: 9000,
      totalSpent: 4200,
      percentage: 46.7,
      dailyAvailable: 240,
      daysRemaining: 20,
      overBudgetCategories: [],
    ),
    trend: _reviewStatisticsDashboard.trend,
    familySummary: const home_data.FamilyHomeSummary(
      month: '2026-06',
      totalExpense: 1260,
      members: [
        home_data.FamilyHomeMemberSummary(
          memberID: 'member-1',
          name: '自己',
          expenseTotal: 860,
          count: 8,
        ),
        home_data.FamilyHomeMemberSummary(
          memberID: 'member-2',
          name: '家人',
          expenseTotal: 400,
          count: 3,
        ),
      ],
    ),
    recentTransactions: _sampleTransactions,
  );

  @override
  Future<List<TransactionItem>> listRecentTransactions() async =>
      _sampleTransactions;

  @override
  Future<List<TransactionItem>> listTransactionsForDate(DateTime date) async =>
      _sampleTransactions;
}

class _FakeTransactionRepository implements TransactionRepository {
  @override
  Future<void> batchDelete(List<String> ids) async {}

  @override
  Future<TransactionItem> create(TransactionFormData form) async {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<LedgerAccount>> listAccounts() async => const [
    LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
    LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank'),
  ];

  @override
  Future<TransactionItem> getById(String id) async => _sampleTransactions.first;

  @override
  Future<TransactionListResult> list(TransactionListQuery query) async =>
      TransactionListResult(
        list: _sampleTransactions,
        total: _sampleTransactions.length,
        page: 1,
        pageSize: 20,
      );

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    final categories = const [
      LedgerCategory(id: 'category-food', name: '餐饮', type: 'expense'),
      LedgerCategory(id: 'category-transport', name: '交通', type: 'expense'),
      LedgerCategory(id: 'category-salary', name: '工资', type: 'income'),
    ];
    if (type == null) {
      return categories;
    }
    return categories.where((item) => item.type == type).toList();
  }

  @override
  Future<List<LedgerTag>> listTags() async => const [
    LedgerTag(id: 'tag-1', name: '通勤'),
    LedgerTag(id: 'tag-2', name: '家庭'),
    LedgerTag(id: 'tag-3', name: '报销'),
  ];

  @override
  Future<TransactionItem> update(String id, TransactionFormData form) async {
    throw UnimplementedError();
  }
}

class _FakeStatisticsRepository implements StatisticsRepository {
  @override
  Future<StatisticsDashboard> getDashboard(
    StatisticsDashboardQuery query,
  ) async => _reviewStatisticsDashboard;

  @override
  Future<CategoryStatResponse?> getCategoryStats({
    required String month,
    StatisticsPeriod period = StatisticsPeriod.month,
    required String type,
  }) async => _reviewStatisticsDashboard.categories;

  @override
  Future<StatisticsOverviewData?> getOverview(
    String month, {
    StatisticsPeriod period = StatisticsPeriod.month,
  }) async => _reviewStatisticsDashboard.overview;

  @override
  Future<TrendResponse?> getTrend(
    String month, {
    StatisticsPeriod period = StatisticsPeriod.month,
  }) async => _reviewStatisticsDashboard.trend;
}

final _reviewStatisticsDashboard = StatisticsDashboard(
  overview: const StatisticsOverviewData(
    income: 10000,
    expense: 4200,
    balance: 5800,
    incomeChange: 8.4,
    expenseChange: -5.2,
    dailyAverage: 140,
    transactionCount: 28,
  ),
  trend: const TrendResponse(
    totalIncome: 10000,
    totalExpense: 4200,
    items: [
      TrendItem(date: '2026-06-01', income: 900, expense: 480, balance: 420),
      TrendItem(date: '2026-06-05', income: 1200, expense: 720, balance: 480),
      TrendItem(date: '2026-06-10', income: 1800, expense: 650, balance: 1150),
      TrendItem(date: '2026-06-15', income: 1400, expense: 900, balance: 500),
      TrendItem(date: '2026-06-20', income: 2100, expense: 560, balance: 1540),
      TrendItem(date: '2026-06-25', income: 1300, expense: 470, balance: 830),
      TrendItem(date: '2026-06-30', income: 1300, expense: 420, balance: 880),
    ],
  ),
  categories: const CategoryStatResponse(
    total: 4200,
    items: [
      CategoryStatItem(
        categoryId: 'category-food',
        categoryName: '餐饮',
        icon: 'restaurant',
        color: '#FF3B30',
        amount: 1680,
        percentage: 40,
        count: 12,
      ),
      CategoryStatItem(
        categoryId: 'category-transport',
        categoryName: '交通',
        icon: 'directions_car',
        color: '#0F766E',
        amount: 1050,
        percentage: 25,
        count: 7,
      ),
      CategoryStatItem(
        categoryId: 'category-shopping',
        categoryName: '购物',
        icon: 'shopping_bag',
        color: '#8E8E93',
        amount: 840,
        percentage: 20,
        count: 5,
      ),
    ],
  ),
);

class _FakeLendingRepository implements LendingRepository {
  @override
  Future<LendingItem?> create(CreateLendingRequest request) async =>
      LendingItem(
        id: 'new',
        type: request.type,
        contactName: request.contactName,
        principal: request.principal,
        currentBalance: request.principal,
        totalRepaid: 0,
        lendDate: DateTime.parse(request.lendDate),
      );

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<LendingItem>?> list({bool includeSettled = false}) async => [
    LendingItem(
      id: 'lend-1',
      type: LendingType.lendOut,
      contactName: '张三',
      principal: 2000,
      currentBalance: 1200,
      totalRepaid: 800,
      lendDate: DateTime(2026, 5, 1, 9),
      dueDate: DateTime(2026, 6, 20),
      remark: '装修周转',
    ),
    LendingItem(
      id: 'borrow-1',
      type: LendingType.borrowIn,
      contactName: '李四',
      principal: 1500,
      currentBalance: 900,
      totalRepaid: 600,
      lendDate: DateTime(2026, 5, 12, 9),
      dueDate: DateTime(2026, 6, 18),
      remark: '短借',
    ),
  ];

  @override
  Future<List<LendingRecordItem>?> records(String id) async => const [];

  @override
  Future<LendingItem?> recordRepayment(
    String id,
    RecordRepaymentRequest request,
  ) async => null;

  @override
  Future<LendingSummary?> summaryOverview() async => const LendingSummary(
    totalLendOut: 2000,
    totalBorrowIn: 1500,
    activeLendOut: 1,
    activeBorrowIn: 1,
    settledLendOut: 0,
    settledBorrowIn: 0,
    totalReceivable: 1200,
    totalPayable: 900,
    netLending: 300,
  );

  @override
  Future<LendingItem?> update(String id, UpdateLendingRequest request) async =>
      null;
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<Account> create(CreateAccountRequest request) async =>
      throw UnimplementedError();

  @override
  Future<void> archive(String id, bool isArchived) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Account> getById(String id) async => const Account(
    id: 'cash',
    name: '现金',
    type: 'cash',
    icon: '💰',
    color: '#10B981',
    initialBalance: 3000,
    currentBalance: 3000,
    isArchived: false,
    sortOrder: 0,
  );

  @override
  Future<AccountListResult> list({bool includeArchived = false}) async =>
      const AccountListResult(
        accounts: [
          Account(
            id: 'cash',
            name: '现金',
            type: 'cash',
            icon: '💰',
            color: '#10B981',
            initialBalance: 3000,
            currentBalance: 3000,
            isArchived: false,
            sortOrder: 0,
          ),
          Account(
            id: 'bank',
            name: '储蓄卡',
            type: 'bank',
            icon: '💳',
            color: '#2563EB',
            initialBalance: 5200,
            currentBalance: 5200,
            isArchived: false,
            sortOrder: 1,
          ),
        ],
        totalAssets: 8200,
        totalLiabilities: 0,
        netAssets: 8200,
      );

  @override
  Future<Account> update(String id, UpdateAccountRequest request) async =>
      throw UnimplementedError();

  @override
  Future<void> updateSort(List<String> ids) async {}
}

class _FakeAttachmentRepository implements AttachmentRepository {
  @override
  Future<void> delete(String path) async {}

  @override
  Future<void> download(String path, String savePath) async {}

  @override
  Future<List<int>> downloadBytes(String path) async => const [];

  @override
  Uri downloadUri(String path) => Uri.parse('https://example.test/$path');

  @override
  Future<LedgerAttachment> upload({
    required PendingAttachmentFile file,
    required String category,
    required String refId,
    void Function(int sent, int total)? onSendProgress,
  }) async => LedgerAttachment(
    path: '$category/$refId/${file.name}',
    filename: file.name,
    size: 0,
    mimeType: 'image/png',
  );
}

class _EmptyAttachmentPickerService implements AttachmentPickerService {
  const _EmptyAttachmentPickerService();

  @override
  Future<PendingAttachmentFile?> pickImageFromCamera() async => null;

  @override
  Future<PendingAttachmentFile?> pickImageFromGallery() async => null;

  @override
  Future<List<PendingAttachmentFile>> pickFiles() async => const [];
}

const _familyMembers = [
  FamilyMember(
    id: 'member-1',
    name: '自己',
    relationship: 'self',
    color: '#10B981',
    isDefault: true,
    isEnabled: true,
  ),
  FamilyMember(
    id: 'member-2',
    name: '家人',
    relationship: 'family',
    color: '#3B82F6',
    isDefault: false,
    isEnabled: true,
  ),
];

final _sampleTransactions = [
  TransactionItem(
    id: 'tx-1',
    type: TransactionType.expense,
    amount: 28,
    accountId: 'account-1',
    categoryId: 'category-food',
    transactionDate: DateTime(2026, 6, 1, 12, 30),
    remark: '午餐',
    account: const LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
    category: const LedgerCategory(
      id: 'category-food',
      name: '餐饮',
      type: 'expense',
    ),
  ),
  TransactionItem(
    id: 'tx-2',
    type: TransactionType.expense,
    amount: 16,
    accountId: 'account-1',
    categoryId: 'category-transport',
    transactionDate: DateTime(2026, 6, 1, 8, 15),
    remark: '地铁',
    account: const LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
    category: const LedgerCategory(
      id: 'category-transport',
      name: '交通',
      type: 'expense',
    ),
  ),
  TransactionItem(
    id: 'tx-3',
    type: TransactionType.income,
    amount: 3500,
    accountId: 'account-2',
    categoryId: 'category-salary',
    transactionDate: DateTime(2026, 6, 1, 9, 0),
    remark: '工资',
    account: const LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank'),
    category: const LedgerCategory(
      id: 'category-salary',
      name: '工资',
      type: 'income',
    ),
  ),
];
