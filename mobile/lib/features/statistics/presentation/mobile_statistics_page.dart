import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
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
      categoryType: _categoryType,
    );
    final dashboardState = ref.watch(statisticsDashboardProvider(query));
    final themeSettings = ref.watch(themeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(statisticsDashboardProvider(query)),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新统计数据',
          ),
        ],
      ),
      body: dashboardState.when(
        loading: () => const AppLoadingView(message: '正在加载统计数据...'),
        error: (error, _) => _StatisticsErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(statisticsDashboardProvider(query)),
          onRefresh: () =>
              ref.refresh(statisticsDashboardProvider(query).future),
        ),
        data: (dashboard) => _StatisticsContent(
          dashboard: dashboard,
          themeSettings: themeSettings,
          selectedMonth: _selectedMonth,
          categoryType: _categoryType,
          onPreviousMonth: _goPreviousMonth,
          onNextMonth: _canGoNextMonth ? _goNextMonth : null,
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
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    return _selectedMonth.isBefore(currentMonth);
  }

  void _goPreviousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _goNextMonth() {
    if (!_canGoNextMonth) {
      return;
    }
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({
    required this.dashboard,
    required this.themeSettings,
    required this.selectedMonth,
    required this.categoryType,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onCategoryTypeChanged,
    required this.onRefresh,
  });

  final StatisticsDashboard dashboard;
  final AppThemeSettings themeSettings;
  final DateTime selectedMonth;
  final String categoryType;
  final VoidCallback onPreviousMonth;
  final VoidCallback? onNextMonth;
  final ValueChanged<String> onCategoryTypeChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            StaggeredEntrance(
              index: 0,
              child: _MonthHeader(
                selectedMonth: selectedMonth,
                overview: dashboard.overview,
                settings: themeSettings,
                onPreviousMonth: onPreviousMonth,
                onNextMonth: onNextMonth,
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 1,
              child: _TrendCard(trend: dashboard.trend),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 2,
              child: _CategoryRankCard(
                response: dashboard.categories,
                categoryType: categoryType,
                onCategoryTypeChanged: onCategoryTypeChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
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

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.selectedMonth,
    required this.overview,
    required this.settings,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime selectedMonth;
  final StatisticsOverviewData overview;
  final AppThemeSettings settings;
  final VoidCallback onPreviousMonth;
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final balanceColor = overview.balance >= 0
        ? financeColors.income
        : financeColors.expense;
    return PremiumSurface(
      key: const ValueKey('statistics-period-header'),
      accentColor: palette.seedColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.space_dashboard_outlined,
                color: palette.seedColor,
                size: 44,
                iconSize: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本月概览',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatMonthLabel(selectedMonth),
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
            ],
          ),
          const SizedBox(height: 14),
          _StatisticsBalanceHero(
            label: '结余',
            value: _formatCurrency(overview.balance),
            color: balanceColor,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
                tooltip:
                    '切换到 ${_formatMonthLabel(DateTime(selectedMonth.year, selectedMonth.month - 1))}',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsPeriodCard(
                  monthLabel: _formatMonthLabel(selectedMonth),
                  color: balanceColor,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
                tooltip:
                    '切换到 ${_formatMonthLabel(DateTime(selectedMonth.year, selectedMonth.month + 1))}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatisticsAmountPill(
                  label: '收入',
                  value: _formatCurrency(overview.income),
                  icon: Icons.south_west_rounded,
                  color: financeColors.income,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsAmountPill(
                  label: '支出',
                  value: _formatCurrency(overview.expense),
                  icon: Icons.north_east_rounded,
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
  const _StatisticsPeriodCard({required this.monthLabel, required this.color});

  final String monthLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            monthLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsBalanceHero extends StatelessWidget {
  const _StatisticsBalanceHero({
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
          IconBadge(
            icon: Icons.account_balance_wallet_outlined,
            color: color,
            size: 38,
            iconSize: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});

  final TrendResponse trend;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final items = trend.items;
    final maxAmount = items.fold<double>(
      0,
      (maxValue, item) => [
        maxValue,
        item.income.abs(),
        item.expense.abs(),
      ].reduce((a, b) => a > b ? a : b),
    );

    return PremiumSurface(
      accentColor: Theme.of(context).colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.stacked_bar_chart_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '收支趋势',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const _TrendLegend(),
            ],
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const _EmptyLine(text: '本月暂无趋势数据')
          else
            RoundedBarChart(
              maxValue: maxAmount,
              items: [
                for (final item in items)
                  RoundedBarChartItem(
                    label: _dayLabel(item.date),
                    primaryValue: item.income,
                    secondaryValue: item.expense,
                    primaryColor: financeColors.income,
                    secondaryColor: Theme.of(context).colorScheme.error,
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
    required this.categoryType,
    required this.onCategoryTypeChanged,
  });

  final CategoryStatResponse response;
  final String categoryType;
  final ValueChanged<String> onCategoryTypeChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final accentColor = categoryType == 'expense'
        ? financeColors.expense
        : financeColors.income;
    return PremiumSurface(
      key: const ValueKey('statistics-category-rank-card'),
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.donut_large_outlined,
                color: accentColor,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分类排行',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      categoryType == 'expense' ? '支出分类' : '收入分类',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _CategoryRankTotalPill(
                amount: _formatCurrency(response.total),
                color: accentColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 16),
          if (response.items.isEmpty)
            const _EmptyLine(text: '本月暂无分类数据')
          else ...[
            for (final item in response.items.indexed)
              CategoryRankTile(
                key: ValueKey('statistics-category-rank-${item.$2.categoryId}'),
                name: item.$2.categoryName,
                icon: item.$2.icon,
                amount: _formatCurrency(item.$2.amount),
                percentage: item.$2.percentage,
                count: item.$2.count,
                color: _parseColor(
                  item.$2.color,
                  Theme.of(context).colorScheme.primary,
                ),
                rank: item.$1 + 1,
              ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRankTotalPill extends StatelessWidget {
  const _CategoryRankTotalPill({required this.amount, required this.color});

  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 32, maxWidth: 132),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.summarize_outlined, color: color, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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

String _formatMonth(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}

String _formatMonthLabel(DateTime date) {
  return '${date.year}年${date.month}月';
}

String _dayLabel(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) {
    return value.length >= 2 ? value.substring(value.length - 2) : value;
  }
  return date.day.toString();
}

Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
