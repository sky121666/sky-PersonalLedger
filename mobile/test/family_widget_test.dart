import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/family/presentation/family_page.dart';

void main() {
  testWidgets('FamilyPage 展示家庭成员数据', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyMembersProvider.overrideWith((ref) async {
            return const [
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
          }),
          familySummaryProvider.overrideWith((ref) async {
            return const FamilySummary(
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
          }),
          familyStatisticsProvider.overrideWith((ref) async {
            return const FamilyStatistics(
              month: '2026-05',
              totalExpense: 320,
              members: [
                FamilyStatisticsMember(
                  memberId: 'member-1',
                  name: '成员A',
                  relationship: '家人',
                  color: '#2563EB',
                  expenseTotal: 200,
                  count: 3,
                  categories: [
                    FamilyStatisticsCategory(
                      categoryId: 'category-food',
                      name: '餐饮',
                      color: '#F97316',
                      amount: 160,
                      count: 2,
                    ),
                  ],
                ),
              ],
            );
          }),
          memberBudgetsProvider.overrideWith((ref) async {
            return const [
              BudgetItem(
                id: 'member-budget-1',
                categoryId: null,
                categoryName: '',
                memberId: 'member-1',
                memberName: '成员A',
                amount: 1000,
                spent: 450,
                remaining: 550,
                percentage: 45,
                alertThreshold: 80,
              ),
            ];
          }),
        ],
        child: const MaterialApp(home: FamilyPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('家庭成员'), findsOneWidget);
    expect(find.text('协同中'), findsNothing);
    expect(find.text('已汇总'), findsNothing);
    expect(find.text('2026-05 家庭支出'), findsOneWidget);
    expect(find.text('¥320.00'), findsAtLeastNWidgets(1));
    expect(find.text('家庭协同中枢'), findsNothing);
    expect(find.textContaining('成员、预算、分类归属统一展示'), findsNothing);
    expect(
      find.byKey(const ValueKey('family-collaboration-hub')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('family-ai-collaboration-rail')),
      findsNothing,
    );
    expect(find.text('成员协作'), findsNothing);
    expect(find.text('预算联动'), findsNothing);
    expect(find.text('AI 预留'), findsNothing);
    expect(
      find.byKey(const ValueKey('family-governance-surface')),
      findsNothing,
    );
    expect(find.text('家庭治理预留'), findsNothing);
    expect(find.textContaining('角色、权限、预算规则分层接入'), findsNothing);
    expect(
      find.byKey(const ValueKey('family-readiness-surface')),
      findsNothing,
    );
    expect(find.text('家庭功能成熟度'), findsNothing);
    expect(find.text('阶段可用'), findsNothing);
    expect(find.text('成员启用'), findsNothing);
    expect(find.text('默认成员'), findsNothing);
    expect(find.text('分类统计'), findsNothing);
    await tester.scrollUntilVisible(find.text('家庭预算'), 260);
    await tester.pumpAndSettle();
    expect(find.text('家庭预算'), findsAtLeastNWidgets(1));
    expect(find.text('¥1000.00'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('成员支出排行'), 300);
    await tester.pumpAndSettle();
    expect(find.text('成员支出排行'), findsOneWidget);
    expect(find.text('支出集中度'), findsNothing);
    expect(find.text('成员A 63%'), findsNothing);
    expect(find.text('¥200.00 · 3 笔'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('成员分类拆分'), 300);
    await tester.pumpAndSettle();
    expect(find.text('成员分类拆分'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('¥160.00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('默认'), 300);
    expect(find.text('成员A'), findsWidgets);
    expect(find.text('家人'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('停用'), 300);
    expect(find.text('成员B'), findsWidgets);
    expect(find.text('子女'), findsOneWidget);
    expect(find.text('停用'), findsOneWidget);
    expect(find.byType(PremiumSurface), findsWidgets);
  });

  testWidgets('FamilyPage 空态可见', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyMembersProvider.overrideWith((ref) async => const []),
          memberBudgetsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: FamilyPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有家庭成员'), findsOneWidget);
    expect(find.text('添加成员'), findsOneWidget);
  });

  testWidgets('FamilyPage 空态跟随主题色模板', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyMembersProvider.overrideWith((ref) async => const []),
          memberBudgetsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(AppThemePalette.graphite),
          darkTheme: AppTheme.darkTheme(AppThemePalette.graphite),
          home: const FamilyPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.widget<PremiumSurface>(
      find.byType(PremiumSurface).first,
    );
    expect(surface.accentColor, AppThemePalette.graphite.assetColor);
  });
}
