import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/quick_transaction_page.dart';
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
            MaterialApp(theme: AppTheme.lightTheme(), home: const HomePage()),
          ),
        ),
      );
      await _stabilize(tester);

      await _capture(tester, 'home-phone');
      await _disposeTree(tester);
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
              theme: AppTheme.lightTheme(),
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
      await _disposeTree(tester);
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
              theme: AppTheme.lightTheme(),
              home: const LendingPage(),
            ),
          ),
        ),
      );
      await _stabilize(tester);

      await _capture(tester, 'lending-phone');
      await _disposeTree(tester);
    });
  });
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
  final boundary =
      _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('screenshot boundary is not mounted');
  }
  final image = await boundary
      .toImage(pixelRatio: 1)
      .timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('screenshot capture timeout'),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('failed to encode screenshot');
  }
  final file = File('$_outputDir/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data.buffer.asUint8List(), flush: true);
}

Future<void> _stabilize(WidgetTester tester) async {
  for (var index = 0; index < 6; index += 1) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 32));
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
