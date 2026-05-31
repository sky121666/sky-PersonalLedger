import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
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
    final themeSettings = ref.watch(themeControllerProvider);
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
                const SizedBox(height: 12),
                StaggeredEntrance(
                  index: 1,
                  child: _FamilyCollaborationHub(
                    members: members,
                    summary: summary,
                    budgets: memberBudgetsState.valueOrNull ?? const [],
                    statistics: statistics,
                    themeSettings: themeSettings,
                  ),
                ),
                const SizedBox(height: 12),
                StaggeredEntrance(
                  index: 2,
                  child: _FamilyGovernanceSurface(
                    members: members,
                    budgets: memberBudgetsState.valueOrNull ?? const [],
                    themeSettings: themeSettings,
                  ),
                ),
                const SizedBox(height: 12),
                StaggeredEntrance(
                  index: 3,
                  child: _FamilyReadinessSurface(
                    members: members,
                    budgets: memberBudgetsState.valueOrNull ?? const [],
                    statistics: statistics,
                    themeSettings: themeSettings,
                  ),
                ),
                if (memberBudgetsState.valueOrNull?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: 4,
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
                    index: 5,
                    child: _FamilyRankingSurface(summary: summary),
                  ),
                ],
                if (statistics != null &&
                    statistics.members.any(
                      (member) => member.categories.isNotEmpty,
                    )) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: 6,
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
                      index: index + 7,
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
    final financeColors = AppTheme.financeColors(context);
    return Center(
      child: PremiumSurface(
        accentColor: financeColors.asset,
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
    final financeColors = AppTheme.financeColors(context);
    final enabledCount = members.where((member) => member.isEnabled).length;
    final month = summary?.month.isNotEmpty == true ? summary!.month : '本月';
    return Row(
      children: [
        Expanded(
          child: PremiumSurface(
            accentColor: financeColors.income,
            child: _FamilyMetric(
              label: '启用成员',
              value: '$enabledCount',
              helper: '共 ${members.length} 位',
              statusLabel: enabledCount > 0 ? '协同中' : '待启用',
              statusColor: enabledCount > 0
                  ? financeColors.income
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: PremiumSurface(
            accentColor: financeColors.warning,
            child: _FamilyMetric(
              label: '$month 家庭支出',
              value: loadingSummary
                  ? '加载中'
                  : _formatMoney(summary?.totalExpense ?? 0),
              helper: '按成员归属聚合',
              statusLabel: loadingSummary ? '同步中' : '已汇总',
              statusColor: loadingSummary
                  ? Theme.of(context).colorScheme.primary
                  : financeColors.warning,
            ),
          ),
        ),
      ],
    );
  }
}

class _FamilyCollaborationHub extends StatelessWidget {
  const _FamilyCollaborationHub({
    required this.members,
    required this.summary,
    required this.budgets,
    required this.statistics,
    required this.themeSettings,
  });

  final List<FamilyMember> members;
  final FamilySummary? summary;
  final List<BudgetItem> budgets;
  final FamilyStatistics? statistics;
  final AppThemeSettings themeSettings;

  @override
  Widget build(BuildContext context) {
    final palette = themeSettings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final enabledCount = members.where((member) => member.isEnabled).length;
    final budgetAmount = budgets.fold<double>(
      0,
      (sum, budget) => sum + budget.amount,
    );
    final categoryCount =
        statistics?.members.fold<int>(
          0,
          (sum, member) => sum + member.categories.length,
        ) ??
        0;
    final familyExpense = summary?.totalExpense ?? 0;
    final budgetCoverage = budgetAmount <= 0
        ? 0.0
        : (familyExpense / budgetAmount * 100).clamp(0.0, 999.0);
    return PremiumSurface(
      key: const ValueKey('family-collaboration-hub'),
      accentColor: palette.seedColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.hub_outlined,
                color: palette.seedColor,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '家庭协同中枢',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${palette.label} · 成员、预算、分类归属统一展示',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _FamilyPaletteSwatches(palette: palette),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FamilyHubMetric(
                  label: '启用成员',
                  value: '$enabledCount/${members.length}',
                  icon: Icons.groups_2_outlined,
                  color: enabledCount > 0
                      ? financeColors.income
                      : colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FamilyHubMetric(
                  label: '家庭支出',
                  value: _formatMoney(familyExpense),
                  icon: Icons.receipt_long_outlined,
                  color: financeColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _FamilyHubMetric(
                  label: '预算覆盖',
                  value: budgetAmount <= 0
                      ? '未设置'
                      : '${budgetCoverage.toStringAsFixed(0)}%',
                  icon: Icons.savings_outlined,
                  color: budgetAmount <= 0
                      ? colorScheme.outline
                      : financeColors.asset,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FamilyHubMetric(
                  label: '分类拆分',
                  value: '$categoryCount 类',
                  icon: Icons.donut_large_outlined,
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyHubMetric extends StatelessWidget {
  const _FamilyHubMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
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

class _FamilyPaletteSwatches extends StatelessWidget {
  const _FamilyPaletteSwatches({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = [
      palette.seedColor,
      palette.assetColor,
      palette.incomeColor,
      palette.expenseColor,
    ];
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          for (var index = 0; index < colors.length; index += 1)
            Positioned(
              left: (index % 2) * 18,
              top: (index ~/ 2) * 18,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors[index],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FamilyGovernanceSurface extends StatelessWidget {
  const _FamilyGovernanceSurface({
    required this.members,
    required this.budgets,
    required this.themeSettings,
  });

  final List<FamilyMember> members;
  final List<BudgetItem> budgets;
  final AppThemeSettings themeSettings;

  @override
  Widget build(BuildContext context) {
    final palette = themeSettings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final enabledCount = members.where((member) => member.isEnabled).length;
    final defaultCount = members.where((member) => member.isDefault).length;
    final disabledCount = members.length - enabledCount;
    final roleStatus = defaultCount > 0 ? '已指定' : '待指定';
    final budgetStatus = budgets.isEmpty ? '预留' : '${budgets.length} 项';
    return PremiumSurface(
      key: const ValueKey('family-governance-surface'),
      accentColor: colorScheme.tertiary,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.admin_panel_settings_outlined,
                color: colorScheme.tertiary,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '家庭治理预留',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${palette.signature} · 角色、权限、预算规则分层接入',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _FamilyGovernancePill(
                label: '阶段 1',
                icon: Icons.flag_outlined,
                color: palette.seedColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FamilyGovernanceTile(
                  icon: Icons.manage_accounts_outlined,
                  label: '角色入口',
                  value: roleStatus,
                  caption: defaultCount > 0 ? '默认成员就绪' : '需要默认成员',
                  color: financeColors.asset,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FamilyGovernanceTile(
                  icon: Icons.rule_folder_outlined,
                  label: '预算规则',
                  value: budgetStatus,
                  caption: budgets.isEmpty ? '后续可扩展' : '成员预算已接入',
                  color: financeColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FamilyGovernancePill(
                label: '启用 $enabledCount',
                icon: Icons.person_outline,
                color: financeColors.income,
              ),
              _FamilyGovernancePill(
                label: '停用 $disabledCount',
                icon: Icons.person_off_outlined,
                color: disabledCount > 0
                    ? colorScheme.outline
                    : financeColors.income,
              ),
              _FamilyGovernancePill(
                label: '权限预留',
                icon: Icons.lock_outline,
                color: colorScheme.tertiary,
              ),
              _FamilyGovernancePill(
                label: '家庭预算',
                icon: Icons.savings_outlined,
                color: financeColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyGovernanceTile extends StatelessWidget {
  const _FamilyGovernanceTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.17
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyGovernancePill extends StatelessWidget {
  const _FamilyGovernancePill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 32, maxWidth: 148),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyReadinessSurface extends StatelessWidget {
  const _FamilyReadinessSurface({
    required this.members,
    required this.budgets,
    required this.statistics,
    required this.themeSettings,
  });

  final List<FamilyMember> members;
  final List<BudgetItem> budgets;
  final FamilyStatistics? statistics;
  final AppThemeSettings themeSettings;

  @override
  Widget build(BuildContext context) {
    final palette = themeSettings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final enabledCount = members.where((member) => member.isEnabled).length;
    final hasDefault = members.any((member) => member.isDefault);
    final categoryCount =
        statistics?.members.fold<int>(
          0,
          (sum, member) => sum + member.categories.length,
        ) ??
        0;
    final readyScore = [
      enabledCount > 0,
      hasDefault,
      budgets.isNotEmpty,
      categoryCount > 0,
    ].where((ready) => ready).length;
    final readinessColor = readyScore >= 3
        ? financeColors.income
        : readyScore >= 2
        ? financeColors.warning
        : colorScheme.outline;
    final readinessLabel = readyScore >= 3
        ? '阶段可用'
        : readyScore >= 2
        ? '继续完善'
        : '待配置';

    return PremiumSurface(
      key: const ValueKey('family-readiness-surface'),
      accentColor: readinessColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.fact_check_outlined,
                color: readinessColor,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '家庭功能成熟度',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${palette.sceneLabel} · 成员、预算、统计和权限预留的阶段状态',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _FamilyGovernancePill(
                label: readinessLabel,
                icon: readyScore >= 3
                    ? Icons.verified_outlined
                    : Icons.pending_actions_outlined,
                color: readinessColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: readyScore / 4,
              color: readinessColor,
              backgroundColor: colorScheme.outlineVariant.withValues(
                alpha: 0.42,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FamilyReadinessTile(
                  icon: Icons.groups_2_outlined,
                  label: '成员启用',
                  value: '$enabledCount/${members.length}',
                  color: enabledCount > 0
                      ? financeColors.income
                      : colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FamilyReadinessTile(
                  icon: Icons.admin_panel_settings_outlined,
                  label: '默认成员',
                  value: hasDefault ? '已指定' : '待指定',
                  color: hasDefault ? palette.assetColor : colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FamilyReadinessTile(
                  icon: Icons.savings_outlined,
                  label: '预算规则',
                  value: '${budgets.length}',
                  color: budgets.isNotEmpty
                      ? financeColors.warning
                      : colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FamilyReadinessTile(
                  icon: Icons.donut_large_outlined,
                  label: '分类统计',
                  value: '$categoryCount',
                  color: categoryCount > 0
                      ? colorScheme.tertiary
                      : colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyReadinessTile extends StatelessWidget {
  const _FamilyReadinessTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyBudgetSurface extends StatelessWidget {
  const _FamilyBudgetSurface({required this.budgets});

  final List<BudgetItem> budgets;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
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
      accentColor: financeColors.warning,
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
    this.statusLabel,
    this.statusColor,
  });

  final String label;
  final String value;
  final String helper;
  final String? statusLabel;
  final Color? statusColor;

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
        if (statusLabel != null && statusColor != null) ...[
          const SizedBox(height: 8),
          _FamilyStatusPill(label: statusLabel!, color: statusColor!),
        ],
      ],
    );
  }
}

class _FamilyStatusPill extends StatelessWidget {
  const _FamilyStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.10,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_2_outlined, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyCategorySurface extends StatelessWidget {
  const _FamilyCategorySurface({required this.statistics});

  final FamilyStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final visibleMembers = statistics.members
        .where((member) => member.categories.isNotEmpty)
        .take(4)
        .toList();
    return PremiumSurface(
      accentColor: financeColors.asset,
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
    final financeColors = AppTheme.financeColors(context);
    final ranked = [...summary.members]
      ..sort((a, b) => b.expenseTotal.compareTo(a.expenseTotal));
    final topMember = ranked.isEmpty ? null : ranked.first;
    return PremiumSurface(
      accentColor: financeColors.asset,
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
          if (topMember != null) ...[
            const SizedBox(height: 12),
            _FamilyConcentrationStrip(
              member: topMember,
              total: summary.totalExpense,
            ),
          ],
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

class _FamilyConcentrationStrip extends StatelessWidget {
  const _FamilyConcentrationStrip({required this.member, required this.total});

  final FamilyMemberSummary member;
  final double total;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _memberColor(context, member.color);
    final ratio = total <= 0 ? 0.0 : (member.expenseTotal / total * 100);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.10,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.hub_outlined, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '支出集中度',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '${member.name.isEmpty ? '未命名成员' : member.name} ${ratio.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
    final financeColors = AppTheme.financeColors(context);
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
                _MemberStateChip(
                  label: '默认',
                  icon: Icons.check_circle_outline,
                  color: financeColors.income,
                ),
              _MemberStateChip(
                label: member.isEnabled ? '启用' : '停用',
                icon: member.isEnabled
                    ? Icons.person_outline
                    : Icons.person_off_outlined,
                color: member.isEnabled
                    ? financeColors.asset
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
  final financeColors = AppTheme.financeColors(context);
  if (percentage >= 100) {
    return colorScheme.error;
  }
  if (percentage >= 80) {
    return financeColors.warning;
  }
  return financeColors.income;
}

String _formatMoney(double value) {
  return '¥${value.toStringAsFixed(2)}';
}
