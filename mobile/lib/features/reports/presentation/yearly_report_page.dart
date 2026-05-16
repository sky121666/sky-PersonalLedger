import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
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
            _YearSelector(
              years: dashboard.years,
              selectedYear: selectedYear,
              onYearChanged: onYearChanged,
            ),
            const SizedBox(height: 16),
            _SummaryCard(report: report),
            const SizedBox(height: 16),
            _AnnualHighlightsCard(report: report),
            const SizedBox(height: 16),
            _MonthlyTrendCard(items: report.monthlyData),
            const SizedBox(height: 16),
            _CategoryRankCard(
              title: '年度支出 Top',
              items: report.topExpenses,
              emptyText: '本年暂无支出分类数据',
            ),
            const SizedBox(height: 12),
            _CategoryRankCard(
              title: '年度收入 Top',
              items: report.topIncomes,
              emptyText: '本年暂无收入分类数据',
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '年度报告',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$selectedYear 年账本汇总',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
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
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final YearlyReport report;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final savingsColor = report.netSavings >= 0
        ? Colors.green
        : colorScheme.error;
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '净结余',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _formatCurrency(report.netSavings),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: '收入',
                    value: _formatCurrency(report.totalIncome),
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    label: '支出',
                    value: _formatCurrency(report.totalExpense),
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    label: '储蓄率',
                    value: '${report.savingsRate.toStringAsFixed(1)}%',
                    color: savingsColor,
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

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '年度摘要',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            _HighlightLine(
              label: '交易笔数',
              value: '${report.transactionCount} 笔',
            ),
            _HighlightLine(label: '活跃天数', value: '${report.activeDays} 天'),
            _HighlightLine(
              label: '月均收入',
              value: _formatCurrency(report.averageIncome),
            ),
            _HighlightLine(
              label: '月均支出',
              value: _formatCurrency(report.averageExpense),
            ),
            _HighlightLine(label: '最佳结余月', value: report.bestSavingsMonth),
            _HighlightLine(
              label: '最大单笔支出',
              value: _formatCurrency(report.maxSingleExpense),
            ),
            if (report.maxExpenseRemark.isNotEmpty)
              _HighlightLine(label: '最大支出说明', value: report.maxExpenseRemark),
          ],
        ),
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
    final maxAmount = items.fold<double>(
      0,
      (current, item) =>
          math.max(current, math.max(item.income.abs(), item.expense.abs())),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '月度收支',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const _EmptyLine(text: '暂无月度数据')
            else
              SizedBox(
                height: 164,
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
    final incomeHeight = _barHeight(item.income);
    final expenseHeight = _barHeight(item.expense);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Bar(height: incomeHeight, color: Colors.green),
              const SizedBox(width: 2),
              _Bar(
                height: expenseHeight,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          item.month.replaceAll('月', ''),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
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
      width: 6,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              _EmptyLine(text: emptyText)
            else
              for (final item in items.take(5)) _CategoryRankLine(item: item),
          ],
        ),
      ),
    );
  }
}

class _CategoryRankLine extends StatelessWidget {
  const _CategoryRankLine({required this.item});

  final ReportCategoryStat item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            child: Text(item.categoryIcon.isEmpty ? '📝' : item.categoryIcon),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.count} 笔 · ${item.percentage.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatCurrency(item.amount),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
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
