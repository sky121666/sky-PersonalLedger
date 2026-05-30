import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../budgets/data/budget_repository.dart';
import '../data/family_repository.dart';

class FamilyPage extends ConsumerWidget {
  const FamilyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersState = ref.watch(familyMembersProvider);
    final summaryState = ref.watch(familySummaryProvider);
    final memberBudgetsState = ref.watch(memberBudgetsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭成员'),
        actions: [
          IconButton(
            onPressed: () {
              ref.invalidate(familyMembersProvider);
              ref.invalidate(familySummaryProvider);
              ref.invalidate(familyStatisticsProvider);
              ref.invalidate(memberBudgetsProvider);
            },
            icon: const Icon(Icons.refresh_outlined),
            tooltip: '刷新家庭数据',
          ),
        ],
      ),
      body: AdaptivePageContainer(
        child: membersState.when(
          loading: () => const AppLoadingView(message: '正在加载家庭成员'),
          error: (error, stackTrace) => AppErrorView(
            message: '家庭成员加载失败：$error',
            onRetry: () => ref.invalidate(familyMembersProvider),
          ),
          data: (members) {
            if (members.isEmpty) {
              return const _FamilyEmptyState();
            }
            final summary = summaryState.valueOrNull;
            final statisticsState = ref.watch(familyStatisticsProvider);
            final statistics = statisticsState.valueOrNull;
            return ListView(
              children: [
                StaggeredEntrance(
                  child: _FamilySummaryHeader(
                    members: members,
                    summary: summary,
                    loadingSummary: summaryState.isLoading,
                  ),
                ),
                if (memberBudgetsState.valueOrNull?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: 1,
                    child: _FamilyBudgetSurface(
                      budgets: memberBudgetsState.valueOrNull!,
                    ),
                  ),
                ],
                if (summaryState.hasError) ...[
                  const SizedBox(height: 12),
                  PremiumSurface(
                    accentColor: Theme.of(context).colorScheme.error,
                    child: const Text('家庭汇总加载失败，成员列表仍可查看。'),
                  ),
                ],
                if (summary != null && summary.members.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: 2,
                    child: _FamilyRankingSurface(summary: summary),
                  ),
                ],
                if (statistics != null &&
                    statistics.members.any(
                      (member) => member.categories.isNotEmpty,
                    )) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: 3,
                    child: _FamilyCategorySurface(statistics: statistics),
                  ),
                ],
                if (statisticsState.hasError) ...[
                  const SizedBox(height: 12),
                  PremiumSurface(
                    accentColor: Theme.of(context).colorScheme.error,
                    child: const Text('家庭分类统计加载失败，其他家庭数据仍可查看。'),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  '成员',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...members.indexed.map((entry) {
                  final (index, member) = entry;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StaggeredEntrance(
                      index: index + 3,
                      child: _FamilyMemberCard(member: member),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FamilyEmptyState extends StatelessWidget {
  const _FamilyEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: PremiumSurface(
        accentColor: AppTheme.assetColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.diversity_3_outlined,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有家庭成员',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '添加成员后，可按成员查看支出归属和本月家庭汇总。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.add_outlined),
              label: const Text('添加成员'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilySummaryHeader extends StatelessWidget {
  const _FamilySummaryHeader({
    required this.members,
    required this.summary,
    required this.loadingSummary,
  });

  final List<FamilyMember> members;
  final FamilySummary? summary;
  final bool loadingSummary;

  @override
  Widget build(BuildContext context) {
    final enabledCount = members.where((member) => member.isEnabled).length;
    final month = summary?.month.isNotEmpty == true ? summary!.month : '本月';
    return Row(
      children: [
        Expanded(
          child: PremiumSurface(
            accentColor: AppTheme.incomeColor,
            child: _FamilyMetric(
              label: '启用成员',
              value: '$enabledCount',
              helper: '共 ${members.length} 位',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: PremiumSurface(
            accentColor: AppTheme.warningColor,
            child: _FamilyMetric(
              label: '$month 家庭支出',
              value: loadingSummary
                  ? '加载中'
                  : _formatMoney(summary?.totalExpense ?? 0),
              helper: '按成员归属聚合',
            ),
          ),
        ),
      ],
    );
  }
}

class _FamilyBudgetSurface extends StatelessWidget {
  const _FamilyBudgetSurface({required this.budgets});

  final List<BudgetItem> budgets;

  @override
  Widget build(BuildContext context) {
    final totalAmount = budgets.fold<double>(
      0,
      (sum, budget) => sum + budget.amount,
    );
    final totalSpent = budgets.fold<double>(
      0,
      (sum, budget) => sum + budget.spent,
    );
    final remaining = totalAmount - totalSpent;
    final visibleBudgets = budgets.take(3).toList();
    return PremiumSurface(
      accentColor: AppTheme.warningColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '家庭预算',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${budgets.length} 项',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _FamilyMetric(
                  label: '成员预算',
                  value: _formatMoney(totalAmount),
                  helper: '已用 ${_formatMoney(totalSpent)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FamilyMetric(
                  label: '剩余额度',
                  value: _formatMoney(remaining),
                  helper: remaining >= 0 ? '仍在预算内' : '需要关注',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...visibleBudgets.map((budget) => _FamilyBudgetRow(budget: budget)),
        ],
      ),
    );
  }
}

class _FamilyBudgetRow extends StatelessWidget {
  const _FamilyBudgetRow({required this.budget});

  final BudgetItem budget;

  @override
  Widget build(BuildContext context) {
    final color = _budgetStatusColor(context, budget.percentage);
    final memberName = budget.memberName.isEmpty ? '家庭成员' : budget.memberName;
    final title = budget.categoryName.isEmpty
        ? memberName
        : '$memberName · ${budget.categoryName}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${budget.percentage.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (budget.percentage / 100).clamp(0, 1).toDouble(),
              minHeight: 7,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyMetric extends StatelessWidget {
  const _FamilyMetric({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
      ],
    );
  }
}

class _FamilyCategorySurface extends StatelessWidget {
  const _FamilyCategorySurface({required this.statistics});

  final FamilyStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final visibleMembers = statistics.members
        .where((member) => member.categories.isNotEmpty)
        .take(4)
        .toList();
    return PremiumSurface(
      accentColor: AppTheme.assetColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.donut_large_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '成员分类拆分',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...visibleMembers.map(
            (member) => _FamilyCategoryMemberBlock(member: member),
          ),
        ],
      ),
    );
  }
}

class _FamilyCategoryMemberBlock extends StatelessWidget {
  const _FamilyCategoryMemberBlock({required this.member});

  final FamilyStatisticsMember member;

  @override
  Widget build(BuildContext context) {
    final memberColor = _memberColor(context, member.color);
    final categories = [...member.categories]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: memberColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const SizedBox.square(dimension: 10),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  member.name.isEmpty ? '未命名成员' : member.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _formatMoney(member.expenseTotal),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...categories
              .take(3)
              .map(
                (category) => _FamilyCategoryRow(
                  category: category,
                  total: member.expenseTotal,
                ),
              ),
        ],
      ),
    );
  }
}

class _FamilyCategoryRow extends StatelessWidget {
  const _FamilyCategoryRow({required this.category, required this.total});

  final FamilyStatisticsCategory category;
  final double total;

  @override
  Widget build(BuildContext context) {
    final color = _memberColor(context, category.color);
    final ratio = total <= 0 ? 0.0 : (category.amount / total).clamp(0, 1);
    final name = category.name.isEmpty ? '未分类' : category.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 7,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatMoney(category.amount),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _FamilyRankingSurface extends StatelessWidget {
  const _FamilyRankingSurface({required this.summary});

  final FamilySummary summary;

  @override
  Widget build(BuildContext context) {
    final ranked = [...summary.members]
      ..sort((a, b) => b.expenseTotal.compareTo(a.expenseTotal));
    return PremiumSurface(
      accentColor: AppTheme.assetColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '成员支出排行',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...ranked.map(
            (member) =>
                _FamilyRankingRow(member: member, total: summary.totalExpense),
          ),
        ],
      ),
    );
  }
}

class _FamilyRankingRow extends StatelessWidget {
  const _FamilyRankingRow({required this.member, required this.total});

  final FamilyMemberSummary member;
  final double total;

  @override
  Widget build(BuildContext context) {
    final color = _memberColor(context, member.color);
    final ratio = total <= 0
        ? 0.0
        : (member.expenseTotal / total).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member.name.isEmpty ? '未命名成员' : member.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${_formatMoney(member.expenseTotal)} · ${member.count} 笔',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyMemberCard extends StatelessWidget {
  const _FamilyMemberCard({required this.member});

  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final accent = _memberColor(context, member.color);
    final colorScheme = Theme.of(context).colorScheme;
    final relationship = member.relationship.isEmpty
        ? '家庭成员'
        : member.relationship;
    final initial = member.name.characters.isEmpty
        ? '?'
        : member.name.characters.first;
    return PremiumSurface(
      accentColor: accent,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Text(
                  initial,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  relationship,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              if (member.isDefault)
                const _MemberStateChip(
                  label: '默认',
                  icon: Icons.check_circle_outline,
                  color: AppTheme.incomeColor,
                ),
              _MemberStateChip(
                label: member.isEnabled ? '启用' : '停用',
                icon: member.isEnabled
                    ? Icons.person_outline
                    : Icons.person_off_outlined,
                color: member.isEnabled
                    ? AppTheme.assetColor
                    : colorScheme.outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberStateChip extends StatelessWidget {
  const _MemberStateChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _memberColor(BuildContext context, String color) {
  final normalized = color.replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    return Theme.of(context).colorScheme.primary;
  }
  return Color(0xFF000000 | parsed);
}

Color _budgetStatusColor(BuildContext context, double percentage) {
  final colorScheme = Theme.of(context).colorScheme;
  if (percentage >= 100) {
    return colorScheme.error;
  }
  if (percentage >= 80) {
    return AppTheme.warningColor;
  }
  return AppTheme.incomeColor;
}

String _formatMoney(double value) {
  return '¥${value.toStringAsFixed(2)}';
}
