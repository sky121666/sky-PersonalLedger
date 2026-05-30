import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/ai/data/ai_report_repository.dart';
import 'package:personal_ledger/features/ai/presentation/ai_reports_page.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/family/presentation/family_page.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/home/presentation/home_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/quick_transaction_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('premium target screens', () {
    for (final variant in _visualVariants) {
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

          expect(find.text('个人记账'), findsOneWidget);
          expect(find.text('净资产'), findsOneWidget);
          expect(find.text('本月收支'), findsOneWidget);
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
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: themeMode,
    home: home,
  );
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
