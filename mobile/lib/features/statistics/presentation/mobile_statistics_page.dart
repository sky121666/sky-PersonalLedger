import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/money_formatter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../data/statistics_models.dart';
import '../data/statistics_repository.dart';

class MobileStatisticsPage extends ConsumerStatefulWidget {
  const MobileStatisticsPage({super.key});

  @override
  ConsumerState<MobileStatisticsPage> createState() =>
      _MobileStatisticsPageState();
}

class _MobileStatisticsPageState extends ConsumerState<MobileStatisticsPage> {
  late DateTime _selectedMonth;
  StatisticsPeriod _selectedPeriod = StatisticsPeriod.month;
  String _categoryType = 'expense';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final query = StatisticsDashboardQuery(
      month: _formatMonth(_selectedMonth),
      period: _selectedPeriod,
      categoryType: _categoryType,
    );
    final dashboardState = ref.watch(statisticsDashboardProvider(query));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 20,
        title: Text(
          '统计',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
      ),
      body: dashboardState.when(
        loading: () => const _StatisticsLoadingView(),
        error: (error, _) => _StatisticsErrorView(
          message: '统计数据加载失败',
          onRetry: () => ref.invalidate(statisticsDashboardProvider(query)),
          onRefresh: () =>
              ref.refresh(statisticsDashboardProvider(query).future),
        ),
        data: (dashboard) => _StatisticsContent(
          dashboard: dashboard,
          selectedMonth: _selectedMonth,
          selectedPeriod: _selectedPeriod,
          categoryType: _categoryType,
          onPreviousMonth: _goPreviousMonth,
          onNextMonth: _canGoNextMonth ? _goNextMonth : null,
          onPeriodChanged: (value) {
            setState(() => _selectedPeriod = value);
          },
          onCategoryTypeChanged: (value) {
            setState(() => _categoryType = value);
          },
          onRefresh: () =>
              ref.refresh(statisticsDashboardProvider(query).future),
        ),
      ),
    );
  }

  bool get _canGoNextMonth {
    if (_selectedPeriod == StatisticsPeriod.history) {
      return false;
    }
    final now = DateTime.now();
    final currentAnchor = _selectedPeriod == StatisticsPeriod.year
        ? DateTime(now.year)
        : DateTime(now.year, now.month);
    final selectedAnchor = _selectedPeriod == StatisticsPeriod.year
        ? DateTime(_selectedMonth.year)
        : _selectedMonth;
    return selectedAnchor.isBefore(currentAnchor);
  }

  void _goPreviousMonth() {
    setState(() {
      _selectedMonth = _selectedPeriod == StatisticsPeriod.year
          ? DateTime(_selectedMonth.year - 1, _selectedMonth.month)
          : DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _goNextMonth() {
    if (!_canGoNextMonth) {
      return;
    }
    setState(() {
      _selectedMonth = _selectedPeriod == StatisticsPeriod.year
          ? DateTime(_selectedMonth.year + 1, _selectedMonth.month)
          : DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({
    required this.dashboard,
    required this.selectedMonth,
    required this.selectedPeriod,
    required this.categoryType,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onPeriodChanged,
    required this.onCategoryTypeChanged,
    required this.onRefresh,
  });

  final StatisticsDashboard dashboard;
  final DateTime selectedMonth;
  final StatisticsPeriod selectedPeriod;
  final String categoryType;
  final VoidCallback onPreviousMonth;
  final VoidCallback? onNextMonth;
  final ValueChanged<StatisticsPeriod> onPeriodChanged;
  final ValueChanged<String> onCategoryTypeChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _StatisticsRow(
        _MonthHeader(
          selectedMonth: selectedMonth,
          selectedPeriod: selectedPeriod,
          overview: dashboard.overview,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onPeriodChanged: onPeriodChanged,
        ),
      ),
      _StatisticsRow(
        _TrendCard(trend: dashboard.trend, period: selectedPeriod),
      ),
      _StatisticsRow(
        _CategoryRankCard(
          response: dashboard.categories,
          period: selectedPeriod,
          categoryType: categoryType,
          onCategoryTypeChanged: onCategoryTypeChanged,
        ),
        0,
      ),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == rows.length - 1 ? 0 : row.bottomSpacing,
              ),
              child: row.child,
            );
          },
        ),
      ),
    );
  }
}

class _StatisticsRow {
  const _StatisticsRow(this.child, [this.bottomSpacing = 12]);

  final Widget child;
  final double bottomSpacing;
}

class _StatisticsErrorView extends StatelessWidget {
  const _StatisticsErrorView({
    required this.message,
    required this.onRetry,
    required this.onRefresh,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final rows = [
      const SizedBox(height: 48),
      AppErrorView(message: message, onRetry: onRetry),
    ];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: rows.length,
          itemBuilder: (context, index) => rows[index],
        ),
      ),
    );
  }
}

class _StatisticsLoadingView extends StatelessWidget {
  const _StatisticsLoadingView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AdaptivePageContainer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.selectedMonth,
    required this.selectedPeriod,
    required this.overview,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onPeriodChanged,
  });

  final DateTime selectedMonth;
  final StatisticsPeriod selectedPeriod;
  final StatisticsOverviewData overview;
  final VoidCallback onPreviousMonth;
  final VoidCallback? onNextMonth;
  final ValueChanged<StatisticsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final previousAnchor = selectedPeriod == StatisticsPeriod.year
        ? DateTime(selectedMonth.year - 1, selectedMonth.month)
        : DateTime(selectedMonth.year, selectedMonth.month - 1);
    final nextAnchor = selectedPeriod == StatisticsPeriod.year
        ? DateTime(selectedMonth.year + 1, selectedMonth.month)
        : DateTime(selectedMonth.year, selectedMonth.month + 1);
    return PremiumSurface(
      key: const ValueKey('statistics-period-header'),
      accentColor: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatisticsBalanceHero(
            label: '结余',
            value: _formatCurrency(overview.balance),
          ),
          const SizedBox(height: 14),
          SegmentedButton<StatisticsPeriod>(
            key: const ValueKey('statistics-period-selector'),
            segments: const [
              ButtonSegment(value: StatisticsPeriod.month, label: Text('当月')),
              ButtonSegment(value: StatisticsPeriod.year, label: Text('今年')),
              ButtonSegment(value: StatisticsPeriod.history, label: Text('往年')),
            ],
            selected: {selectedPeriod},
            showSelectedIcon: false,
            onSelectionChanged: (values) => onPeriodChanged(values.first),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                key: ValueKey(
                  'statistics-previous-period-${previousAnchor.year}-${previousAnchor.month.toString().padLeft(2, '0')}',
                ),
                onPressed: selectedPeriod == StatisticsPeriod.history
                    ? null
                    : onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
                tooltip:
                    '切换到 ${_periodAnchorLabel(previousAnchor, selectedPeriod)}',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _StatisticsPeriodCard(
                  monthLabel: _periodAnchorLabel(selectedMonth, selectedPeriod),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: ValueKey(
                  'statistics-next-period-${nextAnchor.year}-${nextAnchor.month.toString().padLeft(2, '0')}',
                ),
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
                tooltip:
                    '切换到 ${_periodAnchorLabel(nextAnchor, selectedPeriod)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatisticsAmountPill(
                  label: '收入',
                  value: _formatCurrency(overview.income),
                  color: financeColors.income,
                ),
              ),
              SizedBox(
                height: 34,
                child: VerticalDivider(
                  width: 24,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              Expanded(
                child: _StatisticsAmountPill(
                  label: '支出',
                  value: _formatCurrency(overview.expense),
                  color: financeColors.expense,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatisticsPeriodCard extends StatelessWidget {
  const _StatisticsPeriodCard({required this.monthLabel});

  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            monthLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsBalanceHero extends StatelessWidget {
  const _StatisticsBalanceHero({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsAmountPill extends StatelessWidget {
  const _StatisticsAmountPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend, required this.period});

  final TrendResponse trend;
  final StatisticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final items = trend.items;

    return PremiumSurface(
      accentColor: Theme.of(context).colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '收支趋势',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const _TrendLegend(),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const _EmptyLine(text: '无趋势')
          else
            CashFlowLineChart(
              height: 172,
              items: [
                for (final item in items)
                  CashFlowLineChartItem(
                    label: _trendLabel(item.date, period),
                    income: item.income,
                    expense: item.expense,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend();

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendDot(label: '收入', color: financeColors.income),
        const SizedBox(width: 10),
        _LegendDot(label: '支出', color: Theme.of(context).colorScheme.error),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});

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
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CategoryRankCard extends StatelessWidget {
  const _CategoryRankCard({
    required this.response,
    required this.period,
    required this.categoryType,
    required this.onCategoryTypeChanged,
  });

  final CategoryStatResponse response;
  final StatisticsPeriod period;
  final String categoryType;
  final ValueChanged<String> onCategoryTypeChanged;

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final rankedItems = [...response.items]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return PremiumSurface(
      key: const ValueKey('statistics-category-rank-card'),
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '分类排行',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _CategoryRankTotalPill(amount: _formatCurrency(response.total)),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('支出')),
              ButtonSegment(value: 'income', label: Text('收入')),
            ],
            selected: {categoryType},
            showSelectedIcon: false,
            onSelectionChanged: (values) {
              onCategoryTypeChanged(values.first);
            },
          ),
          const SizedBox(height: 10),
          if (response.items.isEmpty)
            const _EmptyLine(text: '无分类')
          else ...[
            for (final item in rankedItems.take(5).indexed)
              CategoryRankTile(
                key: ValueKey('statistics-category-rank-${item.$2.categoryId}'),
                name: item.$2.categoryName,
                icon: item.$2.icon,
                amount: _formatCurrency(item.$2.amount),
                percentage: item.$2.percentage,
                count: item.$2.count,
                color: accentColor,
                rank: item.$1 + 1,
              ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRankTotalPill extends StatelessWidget {
  const _CategoryRankTotalPill({required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      amount,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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
  return formatMoney(value);
}

String _formatMonth(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}

String _formatMonthLabel(DateTime date) {
  return '${date.year}年${date.month}月';
}

String _periodAnchorLabel(DateTime date, StatisticsPeriod period) {
  return switch (period) {
    StatisticsPeriod.month => _formatMonthLabel(date),
    StatisticsPeriod.year => '${date.year}年',
    StatisticsPeriod.history => '${date.year}年前',
  };
}

String _dayLabel(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) {
    return value.length >= 2 ? value.substring(value.length - 2) : value;
  }
  return date.day.toString();
}

String _trendLabel(String value, StatisticsPeriod period) {
  if (period == StatisticsPeriod.month) {
    return _dayLabel(value);
  }
  if (period == StatisticsPeriod.year) {
    final parts = value.split('-');
    return parts.length >= 2 ? '${int.tryParse(parts[1]) ?? parts[1]}月' : value;
  }
  return value.length >= 4 ? value.substring(0, 4) : value;
}
