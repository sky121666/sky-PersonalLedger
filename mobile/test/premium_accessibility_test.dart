import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  group('Premium mobile accessibility', () {
    testWidgets('Home premium actions expose semantic labels and tap targets', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeRepositoryProvider.overrideWithValue(_FakeHomeRepository()),
            ],
            child: _premiumApp(const HomePage()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(find.text('快速记账'), 320);
        await tester.pumpAndSettle();
        final surfaceLabels = tester
            .widgetList<PremiumSurface>(find.byType(PremiumSurface))
            .map((surface) => surface.semanticLabel)
            .whereType<String>();
        expect(surfaceLabels, contains('快速记账'));

        await tester.scrollUntilVisible(find.text('家庭支出'), 320);
        await tester.pumpAndSettle();
        final visibleSurfaceLabels = tester
            .widgetList<PremiumSurface>(find.byType(PremiumSurface))
            .map((surface) => surface.semanticLabel)
            .whereType<String>();
        expect(visibleSurfaceLabels, contains('查看家庭支出详情'));
        expect(find.byTooltip('刷新首页概览'), findsOneWidget);
        expect(find.byTooltip('退出登录'), findsOneWidget);
        _expectMinTapTarget(tester, find.byTooltip('刷新首页概览'));
        _expectMinTapTarget(tester, find.byTooltip('退出登录'));
      });
    });

    testWidgets('Quick Transaction embedded form has labeled controls', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              transactionRepositoryProvider.overrideWithValue(
                _FakeTransactionRepository(),
              ),
              familyMembersProvider.overrideWith((ref) async => _familyMembers),
            ],
            child: _premiumApp(const QuickTransactionPage(embedded: true)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('记一笔'), findsOneWidget);
        expect(find.byTooltip('关闭记一笔表单'), findsOneWidget);
        expect(find.text('金额'), findsAtLeastNWidgets(1));
        expect(find.text('账户'), findsAtLeastNWidgets(1));
        expect(find.text('分类'), findsAtLeastNWidgets(1));
        expect(find.text('成员'), findsOneWidget);
        _expectMinTapTarget(tester, find.byTooltip('关闭记一笔表单'));

        await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
        await tester.pumpAndSettle();
        expect(find.byTooltip('添加自定义标签'), findsOneWidget);
        _expectMinTapTarget(tester, find.byTooltip('添加自定义标签'));
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, '保存'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        _expectMinTapTarget(tester, find.widgetWithText(FilledButton, '保存'));
      });
    });

    testWidgets('AI Reports exposes generation action and report status', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              aiReportsProvider.overrideWith((ref) async => _aiReports),
            ],
            child: _premiumApp(const AIReportsPage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('AI 财务报告'), findsOneWidget);
        expect(find.byTooltip('生成 AI 财务报告'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('已完成'), 240);
        expect(find.text('已完成'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('DeepSeek / deepseek-v4-flash'),
          240,
        );
        expect(find.text('DeepSeek / deepseek-v4-flash'), findsOneWidget);
        _expectMinTapTarget(tester, find.byTooltip('生成 AI 财务报告'));
      });
    });

    testWidgets('Family Hub exposes refresh action and member states', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              familyMembersProvider.overrideWith((ref) async => _familyMembers),
              familySummaryProvider.overrideWith((ref) async => _familySummary),
            ],
            child: _premiumApp(const FamilyPage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('家庭成员'), findsOneWidget);
        expect(find.byTooltip('刷新家庭数据'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('默认'), 240);
        expect(find.text('默认'), findsOneWidget);
        expect(find.text('启用'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('停用'), 240);
        expect(find.text('停用'), findsOneWidget);
        _expectMinTapTarget(tester, find.byTooltip('刷新家庭数据'));
      });
    });
  });
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

Widget _premiumApp(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    home: home,
  );
}

void _expectMinTapTarget(
  WidgetTester tester,
  Finder finder, {
  double minSize = 44,
}) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(minSize));
  expect(size.height, greaterThanOrEqualTo(minSize));
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
