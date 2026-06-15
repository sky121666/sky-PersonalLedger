import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/family/presentation/family_page.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';

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
                avatar: '',
                color: '#2563EB',
                isDefault: true,
                isEnabled: true,
              ),
              FamilyMember(
                id: 'member-2',
                name: '成员B',
                relationship: '子女',
                avatar: '',
                color: '#059669',
                isDefault: false,
                isEnabled: false,
              ),
            ];
          }),
          familySummaryByPeriodProvider.overrideWith((ref, query) async {
            return const FamilySummary(
              month: '2026-05',
              label: '2026年5月',
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
          familyStatisticsByPeriodProvider.overrideWith((ref, query) async {
            return const FamilyStatistics(
              month: '2026-05',
              label: '2026年5月',
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
    expect(find.text('2026年5月 家庭支出'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('family-period-selector')),
      findsOneWidget,
    );
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
    expect(find.text('成员A'), findsWidgets);
    expect(find.text('家人'), findsOneWidget);
    expect(find.text('常用'), findsOneWidget);
    expect(find.text('成员B'), findsWidgets);
    expect(find.text('子女'), findsOneWidget);
    expect(find.text('停用'), findsOneWidget);
    expect(find.text('家庭洞察'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('family-insights-surface')),
      findsOneWidget,
    );
    expect(find.text('家庭预算'), findsNothing);
    await tester.tap(find.text('家庭洞察'));
    await tester.pumpAndSettle();
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
    expect(find.text('右上角添加'), findsOneWidget);
    expect(find.text('尚未添加家庭成员，先添加成员'), findsNothing);
    expect(find.byKey(const ValueKey('family-add-member')), findsOneWidget);
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

  testWidgets('FamilyPage 可以新增、编辑并停用成员', (tester) async {
    final repository = _FakeFamilyRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyRepositoryProvider.overrideWithValue(repository),
          memberBudgetsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: FamilyPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('family-add-member')));
    await tester.pumpAndSettle();
    final colorChoiceBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('family-member-color-#2563EB')),
    );
    expect(colorChoiceBox.size.width, greaterThanOrEqualTo(44));
    expect(colorChoiceBox.size.height, greaterThanOrEqualTo(44));

    await tester.enterText(
      find.byKey(const ValueKey('family-member-name')),
      '成员C',
    );
    await tester.enterText(
      find.byKey(const ValueKey('family-member-relationship')),
      '家人',
    );
    await tester.tap(find.text('保存成员'));
    await tester.pumpAndSettle();

    expect(repository.createdRequests, hasLength(1));
    expect(repository.createdRequests.single.name, '成员C');
    expect(find.text('成员C'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('family-member-toggle-member-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('family-member-action-edit-member-2')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('family-member-name')),
      '成员C改',
    );
    await tester.tap(find.text('保存成员'));
    await tester.pumpAndSettle();

    expect(repository.updatedRequests, hasLength(1));
    expect(repository.updatedRequests.single.$1, 'member-2');
    expect(repository.updatedRequests.single.$2.name, '成员C改');
    expect(find.text('成员C改'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('family-member-action-disable-member-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('停用「成员C改」？'), findsOneWidget);
    expect(find.text('关联记录不变。'), findsNothing);
    expect(find.text('历史归属保留。'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '停用'));
    await tester.pumpAndSettle();

    expect(repository.deletedIds, ['member-2']);
    expect(find.text('成员C改'), findsNothing);
  });
}

class _FakeFamilyRepository implements FamilyRepository {
  final members = <FamilyMember>[
    const FamilyMember(
      id: 'member-1',
      name: '成员A',
      relationship: '家人',
      avatar: '',
      color: '#2563EB',
      isDefault: true,
      isEnabled: true,
    ),
  ];

  final createdRequests = <FamilyMemberRequest>[];
  final updatedRequests = <(String, FamilyMemberRequest)>[];
  final deletedIds = <String>[];

  @override
  Future<List<FamilyMember>> listMembers() async => List.of(members);

  @override
  Future<FamilyMember> createMember(FamilyMemberRequest request) async {
    createdRequests.add(request);
    final member = FamilyMember(
      id: 'member-${members.length + 1}',
      name: request.name,
      relationship: request.relationship,
      avatar: request.avatar,
      color: request.color,
      isDefault: request.isDefault,
      isEnabled: request.isEnabled,
    );
    members.add(member);
    return member;
  }

  @override
  Future<FamilyMember> updateMember(
    String id,
    FamilyMemberRequest request,
  ) async {
    updatedRequests.add((id, request));
    final index = members.indexWhere((member) => member.id == id);
    final member = FamilyMember(
      id: id,
      name: request.name,
      relationship: request.relationship,
      avatar: request.avatar,
      color: request.color,
      isDefault: request.isDefault,
      isEnabled: request.isEnabled,
    );
    if (index >= 0) {
      members[index] = member;
    }
    return member;
  }

  @override
  Future<void> deleteMember(String id) async {
    deletedIds.add(id);
    members.removeWhere((member) => member.id == id);
  }

  @override
  Future<FamilySummary> getSummary({
    String? month,
    FamilyPeriodQuery? query,
  }) async {
    return FamilySummary(
      month: query?.month ?? month ?? '2026-05',
      period: query?.period ?? StatisticsPeriod.month,
      totalExpense: 0,
      members: const [],
    );
  }

  @override
  Future<FamilyStatistics> getStatistics({
    String? month,
    FamilyPeriodQuery? query,
  }) async {
    return FamilyStatistics(
      month: query?.month ?? month ?? '2026-05',
      period: query?.period ?? StatisticsPeriod.month,
      totalExpense: 0,
      members: const [],
    );
  }
}
