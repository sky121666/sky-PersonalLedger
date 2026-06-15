import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../budgets/data/budget_repository.dart';
import '../../statistics/data/statistics_models.dart';
import '../data/family_repository.dart';

class FamilyPage extends ConsumerStatefulWidget {
  const FamilyPage({super.key});

  @override
  ConsumerState<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends ConsumerState<FamilyPage> {
  var _submittingMember = false;
  late DateTime _selectedMonth;
  StatisticsPeriod _selectedPeriod = StatisticsPeriod.month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _invalidateFamilyData() {
    ref
      ..invalidate(familyMembersProvider)
      ..invalidate(familySummaryProvider)
      ..invalidate(familySummaryByPeriodProvider)
      ..invalidate(familyStatisticsProvider)
      ..invalidate(familyStatisticsByPeriodProvider)
      ..invalidate(memberBudgetsProvider);
  }

  Future<void> _showMemberSheet([FamilyMember? member]) async {
    final request = await showModalBottomSheet<FamilyMemberRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FamilyMemberFormSheet(member: member),
    );
    if (request == null || !mounted) {
      return;
    }

    setState(() => _submittingMember = true);
    try {
      final repository = ref.read(familyRepositoryProvider);
      if (member == null) {
        await repository.createMember(request);
      } else {
        await repository.updateMember(member.id, request);
      }
      _invalidateFamilyData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(member == null ? '成员已添加' : '成员已保存')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('成员保存失败')));
      }
    } finally {
      if (mounted) {
        setState(() => _submittingMember = false);
      }
    }
  }

  Future<void> _disableMember(FamilyMember member) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '停用成员',
      message: '停用「${member.name}」？',
      confirmText: '停用',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _submittingMember = true);
    try {
      await ref.read(familyRepositoryProvider).deleteMember(member.id);
      _invalidateFamilyData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成员已停用')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('成员停用失败')));
      }
    } finally {
      if (mounted) {
        setState(() => _submittingMember = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersState = ref.watch(familyMembersProvider);
    final query = FamilyPeriodQuery(
      month: _formatPeriodMonth(_selectedMonth),
      period: _selectedPeriod,
    );
    final summaryState = ref.watch(familySummaryByPeriodProvider(query));
    final memberBudgetsState = ref.watch(memberBudgetsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭成员'),
        actions: [
          IconButton(
            key: const ValueKey('family-add-member'),
            onPressed: _submittingMember ? null : () => _showMemberSheet(),
            tooltip: null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: AdaptivePageContainer(
        child: membersState.when(
          loading: () => const AppLoadingView(message: '正在加载家庭成员'),
          error: (error, stackTrace) => AppErrorView(
            message: '家庭成员加载失败',
            onRetry: () => ref.invalidate(familyMembersProvider),
          ),
          data: (members) {
            if (members.isEmpty) {
              return const _FamilyEmptyState();
            }
            final summary = summaryState.valueOrNull;
            final statisticsState = ref.watch(
              familyStatisticsByPeriodProvider(query),
            );
            final statistics = statisticsState.valueOrNull;
            return _FamilyBody(
              members: members,
              selectedPeriod: _selectedPeriod,
              summary: summary,
              loadingSummary: summaryState.isLoading,
              summaryHasError: summaryState.hasError,
              budgets: memberBudgetsState.valueOrNull ?? const [],
              statistics: statistics,
              statisticsHasError: statisticsState.hasError,
              submitting: _submittingMember,
              onPeriodChanged: (value) {
                setState(() => _selectedPeriod = value);
              },
              onEdit: _showMemberSheet,
              onDisable: _disableMember,
            );
          },
        ),
      ),
    );
  }
}

class _FamilyBody extends StatelessWidget {
  const _FamilyBody({
    required this.members,
    required this.selectedPeriod,
    required this.summary,
    required this.loadingSummary,
    required this.summaryHasError,
    required this.budgets,
    required this.statistics,
    required this.statisticsHasError,
    required this.submitting,
    required this.onPeriodChanged,
    required this.onEdit,
    required this.onDisable,
  });

  final List<FamilyMember> members;
  final StatisticsPeriod selectedPeriod;
  final FamilySummary? summary;
  final bool loadingSummary;
  final bool summaryHasError;
  final List<BudgetItem> budgets;
  final FamilyStatistics? statistics;
  final bool statisticsHasError;
  final bool submitting;
  final ValueChanged<StatisticsPeriod> onPeriodChanged;
  final ValueChanged<FamilyMember> onEdit;
  final ValueChanged<FamilyMember> onDisable;

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final bottom = index == rows.length - 1 ? 0.0 : 12.0;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: switch (row.kind) {
            _FamilyRowKind.summary => _FamilySummaryHeader(
              members: members,
              selectedPeriod: selectedPeriod,
              summary: summary,
              loadingSummary: loadingSummary,
              onPeriodChanged: onPeriodChanged,
            ),
            _FamilyRowKind.sectionTitle => _FamilySectionTitle(
              title: row.title!,
            ),
            _FamilyRowKind.member => _FamilyMemberCard(
              member: row.member!,
              submitting: submitting,
              onEdit: () => onEdit(row.member!),
              onDisable: row.member!.isEnabled
                  ? () => onDisable(row.member!)
                  : null,
            ),
            _FamilyRowKind.insights => _FamilyInsightsSurface(
              budgets: budgets,
              summary: summary,
              statistics: statistics,
              summaryHasError: summaryHasError,
              statisticsHasError: statisticsHasError,
            ),
            _FamilyRowKind.summaryError => PremiumSurface(
              accentColor: Theme.of(context).colorScheme.error,
              child: const Text('家庭汇总加载失败'),
            ),
            _FamilyRowKind.statisticsError => PremiumSurface(
              accentColor: Theme.of(context).colorScheme.error,
              child: const Text('分类统计加载失败'),
            ),
          },
        );
      },
    );
  }

  List<_FamilyRow> _buildRows() {
    final hasCategoryStats =
        statistics?.members.any((member) => member.categories.isNotEmpty) ??
        false;
    return [
      const _FamilyRow(_FamilyRowKind.summary),
      const _FamilyRow(_FamilyRowKind.sectionTitle, title: '成员'),
      for (final member in members)
        _FamilyRow(_FamilyRowKind.member, member: member),
      if (budgets.isNotEmpty ||
          summaryHasError ||
          statisticsHasError ||
          (summary?.members.isNotEmpty ?? false) ||
          hasCategoryStats)
        const _FamilyRow(_FamilyRowKind.insights),
    ];
  }
}

class _FamilyRow {
  const _FamilyRow(this.kind, {this.member, this.title});

  final _FamilyRowKind kind;
  final FamilyMember? member;
  final String? title;
}

enum _FamilyRowKind {
  summary,
  sectionTitle,
  member,
  insights,
  summaryError,
  statisticsError,
}

class _FamilySectionTitle extends StatelessWidget {
  const _FamilySectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _FamilyEmptyState extends StatelessWidget {
  const _FamilyEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.asset,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: Icons.diversity_3_outlined,
            color: colorScheme.primary,
            size: 42,
            iconSize: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '还没有家庭成员',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '添加成员',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilySummaryHeader extends StatelessWidget {
  const _FamilySummaryHeader({
    required this.members,
    required this.selectedPeriod,
    required this.summary,
    required this.loadingSummary,
    required this.onPeriodChanged,
  });

  final List<FamilyMember> members;
  final StatisticsPeriod selectedPeriod;
  final FamilySummary? summary;
  final bool loadingSummary;
  final ValueChanged<StatisticsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final enabledCount = members.where((member) => member.isEnabled).length;
    final periodLabel = summary?.label.isNotEmpty == true
        ? summary!.label
        : selectedPeriod.label;
    return PremiumSurface(
      accentColor: financeColors.warning,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$periodLabel 家庭支出',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<StatisticsPeriod>(
            key: const ValueKey('family-period-selector'),
            segments: const [
              ButtonSegment(value: StatisticsPeriod.month, label: Text('当月')),
              ButtonSegment(value: StatisticsPeriod.year, label: Text('今年')),
              ButtonSegment(value: StatisticsPeriod.history, label: Text('往年')),
            ],
            selected: {selectedPeriod},
            showSelectedIcon: false,
            onSelectionChanged: (values) => onPeriodChanged(values.first),
          ),
          const SizedBox(height: 8),
          Text(
            loadingSummary ? '加载中' : _formatMoney(summary?.totalExpense ?? 0),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$enabledCount 位启用 · 共 ${members.length} 位',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyInsightsSurface extends StatelessWidget {
  const _FamilyInsightsSurface({
    required this.budgets,
    required this.summary,
    required this.statistics,
    required this.summaryHasError,
    required this.statisticsHasError,
  });

  final List<BudgetItem> budgets;
  final FamilySummary? summary;
  final FamilyStatistics? statistics;
  final bool summaryHasError;
  final bool statisticsHasError;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final hasSummary = summary?.members.isNotEmpty ?? false;
    final hasCategory =
        statistics?.members.any((member) => member.categories.isNotEmpty) ??
        false;
    return Material(
      key: const ValueKey('family-insights-surface'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            financeColors.asset.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.13
                  : 0.07,
            ),
            Theme.of(context).colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: financeColors.asset.withValues(alpha: 0.1)),
        ),
        child: ExpansionTile(
          key: const ValueKey('family-insights-toggle'),
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '统计',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.insights_outlined,
                size: 18,
                color: financeColors.asset,
              ),
            ],
          ),
          children: [
            if (budgets.isNotEmpty) _FamilyBudgetSurface(budgets: budgets),
            if (summaryHasError) const _FamilyInlineMessage(text: '家庭汇总加载失败'),
            if (hasSummary) _FamilyRankingSurface(summary: summary!),
            if (hasCategory) _FamilyCategorySurface(statistics: statistics!),
            if (statisticsHasError)
              const _FamilyInlineMessage(text: '分类统计加载失败'),
          ],
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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

class _FamilyInlineMessage extends StatelessWidget {
  const _FamilyInlineMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 14),
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
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 14),
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

class _FamilyMemberCard extends StatefulWidget {
  const _FamilyMemberCard({
    required this.member,
    required this.submitting,
    required this.onEdit,
    required this.onDisable,
  });

  final FamilyMember member;
  final bool submitting;
  final VoidCallback onEdit;
  final VoidCallback? onDisable;

  @override
  State<_FamilyMemberCard> createState() => _FamilyMemberCardState();
}

class _FamilyMemberCardState extends State<_FamilyMemberCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final submitting = widget.submitting;
    final onEdit = widget.onEdit;
    final onDisable = widget.onDisable;

    final accent = _memberColor(context, member.color);
    final colorScheme = Theme.of(context).colorScheme;
    final relationship = _formatRelationship(member.relationship);
    final relationshipLabel = relationship == member.name ? '' : relationship;
    final initial = member.name.characters.isEmpty
        ? '?'
        : member.name.characters.first;
    return PremiumSurface(
      accentColor: accent,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: SizedBox.square(
              dimension: 42,
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
          const SizedBox(width: 10),
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
                if (relationshipLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    relationshipLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMemberState(member),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              IconButton(
                key: ValueKey('family-member-toggle-${member.id}'),
                tooltip: null,
                onPressed: () => setState(() {
                  _expanded = !_expanded;
                }),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.more_horiz_rounded,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              if (_expanded && !submitting) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton.icon(
                      key: ValueKey('family-member-action-edit-${member.id}'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('编辑'),
                    ),
                    if (onDisable != null)
                      TextButton.icon(
                        key: ValueKey(
                          'family-member-action-disable-${member.id}',
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: onDisable,
                        icon: const Icon(Icons.person_off_outlined, size: 16),
                        label: const Text('停用'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyMemberFormSheet extends StatefulWidget {
  const _FamilyMemberFormSheet({this.member});

  final FamilyMember? member;

  @override
  State<_FamilyMemberFormSheet> createState() => _FamilyMemberFormSheetState();
}

class _FamilyMemberFormSheetState extends State<_FamilyMemberFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _relationshipController;
  late final String _avatar;
  late String _color;
  late bool _isDefault;
  late bool _isEnabled;

  static const _colors = [
    '#2563EB',
    '#059669',
    '#F97316',
    '#DC2626',
    '#7C3AED',
    '#0891B2',
  ];

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    _nameController = TextEditingController(text: member?.name ?? '');
    _relationshipController = TextEditingController(
      text: member?.relationship ?? '',
    );
    _avatar = member?.avatar ?? '';
    _color = member?.color.isNotEmpty == true ? member!.color : _colors.first;
    _isDefault = member?.isDefault ?? false;
    _isEnabled = member?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      FamilyMemberRequest(
        name: _nameController.text.trim(),
        relationship: _relationshipController.text.trim(),
        avatar: _avatar,
        color: _color,
        isDefault: _isDefault,
        isEnabled: _isEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.member == null ? '添加成员' : '编辑成员',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('family-member-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '成员名称',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入成员名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('family-member-relationship'),
                controller: _relationshipController,
                decoration: const InputDecoration(
                  labelText: '关系',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in _colors)
                    InkResponse(
                      key: ValueKey('family-member-color-$color'),
                      onTap: () => setState(() => _color = color),
                      radius: 24,
                      child: SizedBox.square(
                        dimension: 44,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _memberColor(context, color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == color
                                    ? colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: SizedBox.square(
                              dimension: 34,
                              child: _color == color
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 18,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value),
                title: const Text('常用成员'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isEnabled,
                onChanged: (value) => setState(() => _isEnabled = value),
                title: const Text('启用'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('保存成员'),
                ),
              ),
            ],
          ),
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
  final financeColors = AppTheme.financeColors(context);
  if (percentage >= 100) {
    return colorScheme.error;
  }
  if (percentage >= 80) {
    return financeColors.warning;
  }
  return financeColors.income;
}

String _formatRelationship(String relationship) {
  return switch (relationship.trim()) {
    'self' => '本人',
    'spouse' => '伴侣',
    'partner' => '伴侣',
    'family' => '家人',
    'child' => '孩子',
    'parent' => '父母',
    '' => '家庭成员',
    final value => value,
  };
}

String _formatMemberState(FamilyMember member) {
  if (member.isDefault && member.isEnabled) {
    return '常用 · 启用';
  }
  if (member.isDefault) {
    return '常用 · 停用';
  }
  return member.isEnabled ? '启用' : '停用';
}

String _formatMoney(double value) {
  return '¥${value.toStringAsFixed(2)}';
}

String _formatPeriodMonth(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}
