import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
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
        ],
        child: const MaterialApp(home: FamilyPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('家庭成员'), findsOneWidget);
    expect(find.text('成员A'), findsWidgets);
    expect(find.text('家人'), findsOneWidget);
    expect(find.text('成员B'), findsWidgets);
    expect(find.text('子女'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('停用'), findsOneWidget);
    expect(find.text('2026-05 家庭支出'), findsOneWidget);
    expect(find.text('¥320.00'), findsOneWidget);
    expect(find.text('成员支出排行'), findsOneWidget);
    expect(find.text('¥200.00 · 3 笔'), findsOneWidget);
    expect(find.byType(PremiumSurface), findsWidgets);
  });

  testWidgets('FamilyPage 空态可见', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyMembersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: FamilyPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有家庭成员'), findsOneWidget);
    expect(find.text('添加成员'), findsOneWidget);
  });
}
