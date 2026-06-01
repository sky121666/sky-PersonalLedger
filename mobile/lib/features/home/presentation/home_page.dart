import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/ledger_icon.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../auth/application/auth_controller.dart';
import '../data/home_repository.dart';
import 'widgets/home_dashboard_widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  /// 构建首页概览页面。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryState = ref.watch(homeSummaryProvider);
    final themeSettings = ref.watch(themeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(homeSummaryProvider),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新首页概览',
          ),
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
          ),
        ],
      ),
      body: summaryState.when(
        loading: () => const AppLoadingView(message: '正在加载首页数据...'),
        error: (error, stackTrace) => _HomeErrorView(
          message: error.toString(),
          onRefresh: () => ref.refresh(homeSummaryProvider.future),
          onRetry: () => ref.invalidate(homeSummaryProvider),
        ),
        data: (summary) => _HomeContent(
          summary: summary,
          themeSettings: themeSettings,
          onRefresh: () => ref.refresh(homeSummaryProvider.future),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.summary,
    required this.themeSettings,
    required this.onRefresh,
  });

  final HomeSummary summary;
  final AppThemeSettings themeSettings;
  final Future<void> Function() onRefresh;

  /// 构建首页数据内容。
  @override
  Widget build(BuildContext context) {
    final accounts = summary.accounts.activeAccounts;
    final visibleAccounts = accounts.take(4).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _entry(0, const _HomeDashboardHeader()),
            const SizedBox(height: 16),
            _entry(
              1,
              _HomeThemeSignalPanel(summary: summary, settings: themeSettings),
            ),
            const SizedBox(height: 16),
            _entry(
              2,
              _HomeActionOrchestrationPanel(
                summary: summary,
                settings: themeSettings,
              ),
            ),
            const SizedBox(height: 16),
            _entry(3, _NetAssetsCard(accounts: summary.accounts)),
            const SizedBox(height: 16),
            _entry(4, const QuickHomeActionCard()),
            const SizedBox(height: 16),
            _entry(5, _MonthlyOverviewCard(overview: summary.overview)),
            const SizedBox(height: 16),
            _entry(6, FamilyHomeSummaryCard(summary: summary.familySummary)),
            const SizedBox(height: 16),
            _entry(
              7,
              _AccountOverviewCard(
                accounts: visibleAccounts,
                totalCount: accounts.length,
              ),
            ),
            const SizedBox(height: 16),
            _entry(8, _BudgetSummaryCard(summary: summary.budgetSummary)),
          ],
        ),
      ),
    );
  }

  Widget _entry(int index, Widget child) {
    return StaggeredEntrance(index: index, child: child);
  }
}

class _HomeDashboardHeader extends StatelessWidget {
  const _HomeDashboardHeader();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '财务控制台',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${now.year} 年 ${now.month} 月 · 私人账本',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        IconBadge(
          icon: Icons.insights_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }
}

class _HomeThemeSignalPanel extends StatelessWidget {
  const _HomeThemeSignalPanel({required this.summary, required this.settings});

  final HomeSummary summary;
  final AppThemeSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final familyActive = summary.familySummary.members.isNotEmpty;
    final budgetActive = summary.budgetSummary.totalAmount > 0;
    return PremiumSurface(
      key: const ValueKey('home-theme-signal-panel'),
      accentColor: palette.seedColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.dashboard_customize_outlined,
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
                      '主题仪表盘',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '当前模板同步首页、家庭账本、AI 报告和财务语义色。',
                      maxLines: 2,
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
              _HomePaletteSwatches(palette: palette),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HomeSignalTile(
                  label: '当前主题',
                  value: palette.label,
                  icon: Icons.palette_outlined,
                  color: palette.seedColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HomeSignalTile(
                  label: '现金流',
                  value: _cashFlowSignalLabel(summary.overview),
                  icon: Icons.monitor_heart_outlined,
                  color: summary.overview.balance >= 0
                      ? financeColors.income
                      : financeColors.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _HomeSignalChip(
                  label: budgetActive ? '预算已接入' : '预算待设置',
                  icon: Icons.savings_outlined,
                  color: budgetActive
                      ? financeColors.warning
                      : colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HomeSignalChip(
                  label: familyActive ? '家庭协同中' : '私人模式',
                  icon: Icons.diversity_3_outlined,
                  color: familyActive
                      ? colorScheme.tertiary
                      : palette.assetColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeActionOrchestrationPanel extends StatelessWidget {
  const _HomeActionOrchestrationPanel({
    required this.summary,
    required this.settings,
  });

  final HomeSummary summary;
  final AppThemeSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final budgetActive = summary.budgetSummary.totalAmount > 0;
    final familyActive = summary.familySummary.members.isNotEmpty;
    final cashFlowHealthy = summary.overview.balance >= 0;
    final transactionActive = summary.overview.transactionCount > 0;
    return PremiumSurface(
      key: const ValueKey('home-action-orchestration-panel'),
      accentColor: palette.assetColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.hub_outlined,
                color: palette.assetColor,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '行动编排层',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '把记账、预算、家庭和 AI 周报串成一个可执行的首页工作流。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _HomeActionStatusPill(
                label: transactionActive ? '已启动' : '待记录',
                icon: transactionActive
                    ? Icons.bolt_outlined
                    : Icons.pending_actions_outlined,
                color: transactionActive
                    ? palette.seedColor
                    : colorScheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HomeActionNode(
                  icon: Icons.add_card_outlined,
                  label: '快速记账',
                  value: transactionActive
                      ? '${summary.overview.transactionCount} 笔'
                      : '首笔记录',
                  color: palette.seedColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HomeActionNode(
                  icon: Icons.savings_outlined,
                  label: '预算守护',
                  value: budgetActive
                      ? '${summary.budgetSummary.percentage.toStringAsFixed(0)}%'
                      : '待设置',
                  color: budgetActive
                      ? financeColors.warning
                      : colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _HomeActionNode(
                  icon: Icons.diversity_3_outlined,
                  label: '家庭协同',
                  value: familyActive
                      ? '${summary.familySummary.members.length} 人'
                      : '私人模式',
                  color: familyActive
                      ? colorScheme.tertiary
                      : palette.assetColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HomeActionNode(
                  icon: Icons.auto_awesome_outlined,
                  label: 'AI 周报',
                  value: cashFlowHealthy ? '可分析' : '需关注',
                  color: cashFlowHealthy
                      ? financeColors.income
                      : financeColors.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HomeActionStatusPill(
                label: cashFlowHealthy ? '现金流稳定' : '现金流预警',
                icon: Icons.monitor_heart_outlined,
                color: cashFlowHealthy
                    ? financeColors.income
                    : financeColors.expense,
              ),
              _HomeActionStatusPill(
                label: budgetActive ? '预算已接入' : '预算待设置',
                icon: Icons.rule_outlined,
                color: budgetActive
                    ? financeColors.warning
                    : colorScheme.outline,
              ),
              _HomeActionStatusPill(
                label: familyActive ? '家庭数据在线' : '私人账本',
                icon: Icons.home_work_outlined,
                color: familyActive ? colorScheme.tertiary : palette.assetColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            key: const ValueKey('home-decision-evidence-rail'),
            spacing: 8,
            runSpacing: 8,
            children: [
              _HomeActionStatusPill(
                label: '${summary.overview.transactionCount} 笔记录',
                icon: transactionActive
                    ? Icons.receipt_long_outlined
                    : Icons.post_add_outlined,
                color: transactionActive
                    ? palette.seedColor
                    : colorScheme.outline,
              ),
              _HomeActionStatusPill(
                label: budgetActive ? '预算输入' : '预算缺口',
                icon: budgetActive
                    ? Icons.fact_check_outlined
                    : Icons.rule_folder_outlined,
                color: budgetActive
                    ? financeColors.warning
                    : colorScheme.outline,
              ),
              _HomeActionStatusPill(
                label: cashFlowHealthy ? 'AI 输入就绪' : 'AI 风险输入',
                icon: Icons.auto_graph_outlined,
                color: cashFlowHealthy
                    ? financeColors.income
                    : financeColors.expense,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeActionNode extends StatelessWidget {
  const _HomeActionNode({
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
      padding: const EdgeInsets.all(10),
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
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
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

class _HomeActionStatusPill extends StatelessWidget {
  const _HomeActionStatusPill({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 32, maxWidth: 156),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.09),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
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

class _HomeSignalTile extends StatelessWidget {
  const _HomeSignalTile({
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
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(12),
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
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
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

class _HomeSignalChip extends StatelessWidget {
  const _HomeSignalChip({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.08),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePaletteSwatches extends StatelessWidget {
  const _HomePaletteSwatches({required this.palette});

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
      width: 44,
      height: 44,
      child: Stack(
        children: [
          for (var index = 0; index < colors.length; index += 1)
            Positioned(
              left: (index % 2) * 20,
              top: (index ~/ 2) * 20,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: colors[index],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeErrorView extends StatelessWidget {
  const _HomeErrorView({
    required this.message,
    required this.onRefresh,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  /// 构建支持重试和下拉刷新的错误页。
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
            AppErrorView(message: message, onRetry: onRetry),
          ],
        ),
      ),
    );
  }
}

class _NetAssetsCard extends StatelessWidget {
  const _NetAssetsCard({required this.accounts});

  final AccountListResponse accounts;

  /// 构建净资产卡片。
  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return FinanceHeroCard(
      label: '净资产',
      amount: accounts.netAssets,
      accentColor: financeColors.asset,
      semanticLabel: '净资产 ${_formatCurrency(accounts.netAssets)}',
      metrics: [
        FinanceMetricData(
          label: '总资产',
          value: _formatCurrency(accounts.totalAssets),
          icon: Icons.account_balance_wallet_outlined,
          color: financeColors.asset,
        ),
        FinanceMetricData(
          label: '总负债',
          value: _formatCurrency(accounts.totalLiabilities),
          icon: Icons.credit_card_outlined,
          color: accounts.totalLiabilities > 0
              ? financeColors.expense
              : Theme.of(context).colorScheme.outline,
        ),
      ],
    );
  }
}

class _MonthlyOverviewCard extends StatelessWidget {
  const _MonthlyOverviewCard({required this.overview});

  final StatisticsOverview overview;

  /// 构建本月收支卡片。
  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final balanceColor = overview.balance >= 0
        ? Theme.of(context).colorScheme.primary
        : financeColors.expense;
    return PremiumSurface(
      accentColor: financeColors.income,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.payments_outlined,
                color: financeColors.income,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '本月现金流',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '本月已记 ${overview.transactionCount} 笔',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CashFlowPulse(overview: overview),
          const SizedBox(height: 16),
          Row(
            children: [
              MetricPill(
                label: '收入',
                value: _formatCurrency(overview.income),
                icon: Icons.south_west,
                color: financeColors.income,
                expanded: true,
              ),
              const SizedBox(width: 10),
              MetricPill(
                label: '支出',
                value: _formatCurrency(overview.expense),
                icon: Icons.north_east,
                color: financeColors.expense,
                expanded: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          MetricPill(
            label: '结余',
            value: _formatCurrency(overview.balance),
            icon: Icons.trending_up,
            color: balanceColor,
          ),
        ],
      ),
    );
  }
}

class _CashFlowPulse extends StatelessWidget {
  const _CashFlowPulse({required this.overview});

  final StatisticsOverview overview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final totalFlow = overview.income + overview.expense;
    final incomeRatio = totalFlow > 0 ? overview.income / totalFlow : 0.0;
    final expenseRatio = totalFlow > 0 ? overview.expense / totalFlow : 0.0;
    final savingRate = overview.income > 0
        ? (overview.balance / overview.income * 100).clamp(-999.0, 999.0)
        : 0.0;
    final statusColor = overview.balance >= 0
        ? financeColors.income
        : financeColors.expense;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          statusColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _cashFlowSignalLabel(overview),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '结余率 ${savingRate.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: math.max(1, (incomeRatio * 100).round()),
                    child: ColoredBox(color: financeColors.income),
                  ),
                  Expanded(
                    flex: math.max(1, (expenseRatio * 100).round()),
                    child: ColoredBox(color: financeColors.expense),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _CashFlowLegend(label: '收入', color: financeColors.income),
              const SizedBox(width: 12),
              _CashFlowLegend(label: '支出', color: financeColors.expense),
              const Spacer(),
              Text(
                overview.transactionCount == 0 ? '等待首笔记录' : '本月趋势已同步',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashFlowLegend extends StatelessWidget {
  const _CashFlowLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({required this.summary});

  final BudgetSummary summary;

  /// 构建预算摘要卡片。
  @override
  Widget build(BuildContext context) {
    final hasBudget = summary.totalAmount > 0;
    final progress = hasBudget
        ? (summary.percentage / 100).clamp(0.0, 1.0)
        : 0.0;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);

    return PremiumSurface(
      key: const ValueKey('home-budget-summary-card'),
      accentColor: financeColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(
                value: progress,
                color: hasBudget ? financeColors.warning : colorScheme.outline,
                center: Text(
                  hasBudget
                      ? '${summary.percentage.toStringAsFixed(0)}%'
                      : '--',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '预算摘要',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _BudgetStatusPill(
                          label: hasBudget ? '预算运行中' : '预算待设置',
                          color: hasBudget
                              ? financeColors.warning
                              : colorScheme.outline,
                        ),
                        Text(
                          hasBudget
                              ? '${_formatCurrency(summary.totalSpent)} / ${_formatCurrency(summary.totalAmount)}'
                              : '本月暂未设置预算',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasBudget) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final gap = compact ? 8.0 : 10.0;
                final width = compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - gap * 2) / 3;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: width,
                      child: _BudgetInfoItem(
                        icon: Icons.account_balance_wallet_outlined,
                        color: financeColors.warning,
                        label: '剩余预算',
                        value: _formatCurrency(summary.remainingAmount),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BudgetInfoItem(
                        icon: Icons.today_outlined,
                        color: financeColors.asset,
                        label: '日可用',
                        value: _formatCurrency(summary.dailyAvailable),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _BudgetInfoItem(
                        icon: Icons.hourglass_bottom_outlined,
                        color: colorScheme.tertiary,
                        label: '剩余天数',
                        value: '${summary.daysRemaining} 天',
                      ),
                    ),
                  ],
                );
              },
            ),
            if (summary.overBudgetCategories.isNotEmpty) ...[
              const SizedBox(height: 12),
              _BudgetOverrunAlert(
                names: summary.overBudgetCategories
                    .map((item) => item.name)
                    .join('、'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _BudgetStatusPill extends StatelessWidget {
  const _BudgetStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.09),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BudgetOverrunAlert extends StatelessWidget {
  const _BudgetOverrunAlert({required this.names});

  final String names;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.error.withValues(alpha: 0.08),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '超预算：$names',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountOverviewCard extends StatelessWidget {
  const _AccountOverviewCard({
    required this.accounts,
    required this.totalCount,
  });

  final List<Account> accounts;
  final int totalCount;

  /// 构建账户概览卡片。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      key: const ValueKey('home-account-overview-card'),
      accentColor: financeColors.asset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.account_balance_wallet_outlined,
                color: financeColors.asset,
                size: 40,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '账户概览',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '资产、负债与现金账户一屏扫读',
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
              _HomeAccountCountPill(
                totalCount: totalCount,
                color: financeColors.asset,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (accounts.isEmpty)
            const _EmptyCardLine(text: '暂无账户，请先创建账户')
          else
            ...accounts.map(
              (account) => Padding(
                padding: EdgeInsets.only(
                  bottom: account == accounts.last ? 0 : 10,
                ),
                child: _AccountLine(account: account),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeAccountCountPill extends StatelessWidget {
  const _HomeAccountCountPill({required this.totalCount, required this.color});

  final int totalCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 30, maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$totalCount 个账户',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.account});

  final Account account;

  /// 构建账户列表行。
  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final accent = account.isDebt ? financeColors.expense : financeColors.asset;
    final typeLabel = account.isDebt ? '负债账户' : '资产账户';
    return Semantics(
      label:
          '${account.name}，$typeLabel，余额${_formatCurrency(account.currentBalance)}',
      child: AnimatedContainer(
        key: ValueKey('home-account-line-${account.id}'),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.14
                  : 0.07,
            ),
            colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accent.withValues(alpha: 0.12),
                  colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.16)),
              ),
              child: Center(
                child: LedgerIcon(
                  icon: account.type,
                  color: accent,
                  size: 22,
                  fallback: account.isDebt
                      ? Icons.credit_card_outlined
                      : Icons.account_balance_wallet_outlined,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _AccountStatusPill(label: typeLabel, color: accent),
                      if (account.isArchived) ...[
                        const SizedBox(width: 6),
                        _AccountStatusPill(
                          label: '已归档',
                          color: colorScheme.outline,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatCurrency(account.currentBalance),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: account.isDebt ? financeColors.expense : null,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  account.isDebt ? '待偿还' : '可用余额',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountStatusPill extends StatelessWidget {
  const _AccountStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 24, maxWidth: 86),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.09),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BudgetInfoItem extends StatelessWidget {
  const _BudgetInfoItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  /// 构建预算信息项。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
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

class _EmptyCardLine extends StatelessWidget {
  const _EmptyCardLine({required this.text});

  final String text;

  /// 构建卡片空状态文本。
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

/// 格式化人民币金额。
String _formatCurrency(double value) {
  return '¥${value.toStringAsFixed(2)}';
}

String _cashFlowSignalLabel(StatisticsOverview overview) {
  if (overview.transactionCount == 0) {
    return '暂无现金流';
  }
  if (overview.balance < 0) {
    return '支出高于收入';
  }
  if (overview.income > 0 && overview.balance / overview.income >= 0.5) {
    return '现金流充沛';
  }
  return '现金流稳定';
}
