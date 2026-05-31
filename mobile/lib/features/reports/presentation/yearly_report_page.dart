import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/ledger_icon.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../data/yearly_report_models.dart';
import '../data/yearly_report_repository.dart';

class YearlyReportPage extends ConsumerStatefulWidget {
  const YearlyReportPage({super.key});

  @override
  ConsumerState<YearlyReportPage> createState() => _YearlyReportPageState();
}

class _YearlyReportPageState extends ConsumerState<YearlyReportPage> {
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(
      yearlyReportDashboardProvider(_selectedYear),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('年度报告'),
        actions: [
          IconButton(
            onPressed: () =>
                ref.invalidate(yearlyReportDashboardProvider(_selectedYear)),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: dashboardState.when(
        loading: () => const AppLoadingView(message: '正在加载年度报告...'),
        error: (error, _) => _ReportErrorView(
          message: error.toString(),
          onRetry: () =>
              ref.invalidate(yearlyReportDashboardProvider(_selectedYear)),
          onRefresh: () =>
              ref.refresh(yearlyReportDashboardProvider(_selectedYear).future),
        ),
        data: (dashboard) => _ReportContent(
          dashboard: dashboard,
          selectedYear: _selectedYear,
          onYearChanged: (year) => setState(() => _selectedYear = year),
          onRefresh: () =>
              ref.refresh(yearlyReportDashboardProvider(_selectedYear).future),
        ),
      ),
    );
  }
}

class _ReportErrorView extends StatelessWidget {
  const _ReportErrorView({
    required this.message,
    required this.onRetry,
    required this.onRefresh,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            AppErrorView(message: message, onRetry: onRetry),
          ],
        ),
      ),
    );
  }
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({
    required this.dashboard,
    required this.selectedYear,
    required this.onYearChanged,
    required this.onRefresh,
  });

  final YearlyReportDashboard dashboard;
  final int selectedYear;
  final ValueChanged<int> onYearChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final report = dashboard.report;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            StaggeredEntrance(
              index: 0,
              child: _YearSelector(
                years: dashboard.years,
                selectedYear: selectedYear,
                onYearChanged: onYearChanged,
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(index: 1, child: _SummaryCard(report: report)),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 2,
              child: _AnnualHighlightsCard(report: report),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 3,
              child: _MonthlyTrendCard(items: report.monthlyData),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 4,
              child: _CategoryRankCard(
                title: '年度支出 Top',
                items: report.topExpenses,
                emptyText: '本年暂无支出分类数据',
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 5,
              child: _CategoryRankCard(
                title: '年度收入 Top',
                items: report.topIncomes,
                emptyText: '本年暂无收入分类数据',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.years,
    required this.selectedYear,
    required this.onYearChanged,
  });

  final List<int> years;
  final int selectedYear;
  final ValueChanged<int> onYearChanged;

  @override
  Widget build(BuildContext context) {
    final sortedYears = {...years, selectedYear}.toList()
      ..sort((a, b) => b.compareTo(a));
    return PremiumSurface(
      padding: const EdgeInsets.all(18),
      accentColor: Theme.of(context).colorScheme.primary,
      child: Row(
        children: [
          IconBadge(
            icon: Icons.insights_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 48,
            iconSize: 25,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '年度报告',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$selectedYear 年账本汇总',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          DropdownMenu<int>(
            initialSelection: selectedYear,
            width: 128,
            dropdownMenuEntries: [
              for (final year in sortedYears)
                DropdownMenuEntry(value: year, label: '$year 年'),
            ],
            onSelected: (value) {
              if (value != null) {
                onYearChanged(value);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final YearlyReport report;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final savingsColor = report.netSavings >= 0
        ? financeColors.income
        : colorScheme.error;
    return PremiumSurface(
      accentColor: savingsColor,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: report.netSavings >= 0
                    ? Icons.trending_up
                    : Icons.trending_down,
                color: savingsColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '净结余',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _YearlySignalPill(
                      label: _yearlySignalLabel(report.netSavings),
                      color: savingsColor,
                      positive: report.netSavings >= 0,
                    ),
                  ],
                ),
              ),
              _SavingsRatePill(rate: report.savingsRate, color: savingsColor),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _formatCurrency(report.netSavings),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: savingsColor,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final tiles = [
                _SummaryTile(
                  label: '收入',
                  value: _formatCurrency(report.totalIncome),
                  color: financeColors.income,
                  icon: Icons.south_west,
                ),
                _SummaryTile(
                  label: '支出',
                  value: _formatCurrency(report.totalExpense),
                  color: financeColors.expense,
                  icon: Icons.north_east,
                ),
                _SummaryTile(
                  label: '储蓄率',
                  value: '${report.savingsRate.toStringAsFixed(1)}%',
                  color: savingsColor,
                  icon: Icons.savings_outlined,
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    for (final tile in tiles) ...[
                      tile,
                      if (tile != tiles.last) const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (final tile in tiles) ...[
                    Expanded(child: tile),
                    if (tile != tiles.last) const SizedBox(width: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _YearlySignalPill extends StatelessWidget {
  const _YearlySignalPill({
    required this.label,
    required this.color,
    required this.positive,
  });

  final String label;
  final Color color;
  final bool positive;

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
          Icon(
            positive ? Icons.verified_outlined : Icons.priority_high_outlined,
            color: color,
            size: 14,
          ),
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

class _SavingsRatePill extends StatelessWidget {
  const _SavingsRatePill({required this.rate, required this.color});

  final double rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${rate.toStringAsFixed(1)}%',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.08),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 34, iconSize: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _AnnualHighlightsCard extends StatelessWidget {
  const _AnnualHighlightsCard({required this.report});

  final YearlyReport report;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.asset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.auto_graph_outlined,
                color: financeColors.asset,
              ),
              const SizedBox(width: 10),
              Text(
                '年度摘要',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MetricPill(
                label: '交易笔数',
                value: '${report.transactionCount} 笔',
                icon: Icons.receipt_long_outlined,
                color: financeColors.asset,
              ),
              MetricPill(
                label: '活跃天数',
                value: '${report.activeDays} 天',
                icon: Icons.event_available_outlined,
                color: financeColors.income,
              ),
              MetricPill(
                label: '月均收入',
                value: _formatCurrency(report.averageIncome),
                icon: Icons.south_west,
                color: financeColors.income,
              ),
              MetricPill(
                label: '月均支出',
                value: _formatCurrency(report.averageExpense),
                icon: Icons.north_east,
                color: financeColors.expense,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _HighlightLine(label: '最佳结余月', value: report.bestSavingsMonth),
          _HighlightLine(
            label: '最大单笔支出',
            value: _formatCurrency(report.maxSingleExpense),
          ),
          if (report.maxExpenseRemark.isNotEmpty)
            _HighlightLine(label: '最大支出说明', value: report.maxExpenseRemark),
        ],
      ),
    );
  }
}

class _HighlightLine extends StatelessWidget {
  const _HighlightLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyTrendCard extends StatelessWidget {
  const _MonthlyTrendCard({required this.items});

  final List<MonthlyReportData> items;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final maxAmount = items.fold<double>(
      0,
      (current, item) =>
          math.max(current, math.max(item.income.abs(), item.expense.abs())),
    );

    return PremiumSurface(
      accentColor: financeColors.income,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.stacked_bar_chart_outlined,
                color: financeColors.income,
              ),
              const SizedBox(width: 10),
              Text(
                '月度收支',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const _EmptyLine(text: '暂无月度数据')
          else
            SizedBox(
              height: 174,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final item in items)
                    Expanded(
                      child: _MonthlyBar(item: item, maxAmount: maxAmount),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthlyBar extends StatelessWidget {
  const _MonthlyBar({required this.item, required this.maxAmount});

  final MonthlyReportData item;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final incomeHeight = _barHeight(item.income);
    final expenseHeight = _barHeight(item.expense);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Bar(height: incomeHeight, color: financeColors.income),
              const SizedBox(width: 3),
              _Bar(height: expenseHeight, color: financeColors.expense),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          item.month.replaceAll('月', ''),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.outline,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  double _barHeight(double value) {
    if (maxAmount <= 0 || value <= 0) {
      return 4;
    }
    return math.max(value / maxAmount * 116, 6);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0.52)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
    );
  }
}

class _CategoryRankCard extends StatelessWidget {
  const _CategoryRankCard({
    required this.title,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final List<ReportCategoryStat> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final accentColor = title.contains('收入')
        ? financeColors.income
        : financeColors.expense;
    final maxAmount = items.fold<double>(
      0,
      (current, item) => math.max(current, item.amount),
    );
    return PremiumSurface(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: title.contains('收入')
                    ? Icons.account_balance_wallet_outlined
                    : Icons.local_fire_department_outlined,
                color: accentColor,
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            _EmptyLine(text: emptyText)
          else
            for (final (index, item) in items.take(5).indexed)
              _CategoryRankLine(
                item: item,
                index: index,
                maxAmount: maxAmount,
                accentColor: accentColor,
              ),
        ],
      ),
    );
  }
}

class _CategoryRankLine extends StatelessWidget {
  const _CategoryRankLine({
    required this.item,
    required this.index,
    required this.maxAmount,
    required this.accentColor,
  });

  final ReportCategoryStat item;
  final int index;
  final double maxAmount;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = maxAmount <= 0
        ? 0.0
        : (item.amount / maxAmount).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '#${index + 1}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: LedgerIcon(
                    icon: item.categoryIcon,
                    fallback: Icons.category_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.count} 笔 · ${item.percentage.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatCurrency(item.amount),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: accentColor,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

String _formatCurrency(double value) {
  return '¥${value.toStringAsFixed(2)}';
}

String _yearlySignalLabel(double netSavings) {
  if (netSavings > 0) {
    return '年度现金流稳健';
  }
  if (netSavings < 0) {
    return '年度现金流承压';
  }
  return '年度现金流持平';
}
