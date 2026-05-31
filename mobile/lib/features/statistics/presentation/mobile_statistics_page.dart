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
            tooltip: '刷新',
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
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 1,
              child: _OverviewCard(overview: dashboard.overview),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 2,
              child: _StatisticsInsightDeck(dashboard: dashboard),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 3,
              child: _StatisticsThemeDataStrip(
                dashboard: dashboard,
                settings: themeSettings,
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 4,
              child: _TrendCard(trend: dashboard.trend),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 5,
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
      key: const ValueKey('statistics-period-command-center'),
      accentColor: palette.seedColor,
      padding: const EdgeInsets.all(14),
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
                      '统计分析',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '周期指挥台 · ${palette.label}',
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
              _StatisticsSignalPill(overview: overview),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
                tooltip: '上个月',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsPeriodCard(
                  monthLabel: _formatMonthLabel(selectedMonth),
                  signalLabel: _statisticsSignalLabel(overview.balance),
                  color: balanceColor,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
                tooltip: '下个月',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatisticsHeaderMetric(
                  label: '收入',
                  value: _formatCurrency(overview.income),
                  icon: Icons.south_west_rounded,
                  color: financeColors.income,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsHeaderMetric(
                  label: '支出',
                  value: _formatCurrency(overview.expense),
                  icon: Icons.north_east_rounded,
                  color: financeColors.expense,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsHeaderMetric(
                  label: '结余',
                  value: _formatCurrency(overview.balance),
                  icon: Icons.account_balance_wallet_outlined,
                  color: balanceColor,
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
  const _StatisticsPeriodCard({
    required this.monthLabel,
    required this.signalLabel,
    required this.color,
  });

  final String monthLabel;
  final String signalLabel;
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
          const SizedBox(height: 2),
          Text(
            signalLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsHeaderMetric extends StatelessWidget {
  const _StatisticsHeaderMetric({
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
      constraints: const BoxConstraints(minHeight: 64),
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
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsSignalPill extends StatelessWidget {
  const _StatisticsSignalPill({required this.overview});

  final StatisticsOverviewData overview;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final color = overview.balance > 0
        ? financeColors.income
        : overview.balance < 0
        ? colorScheme.error
        : colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          Icon(_statisticsSignalIcon(overview.balance), color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            _statisticsSignalLabel(overview.balance),
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

class _StatisticsInsightDeck extends StatelessWidget {
  const _StatisticsInsightDeck({required this.dashboard});

  final StatisticsDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final overview = dashboard.overview;
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final balanceColor = overview.balance >= 0
        ? financeColors.income
        : colorScheme.error;
    final savingRate = _savingRate(overview);

    return PremiumSurface(
      key: const ValueKey('statistics-insight-deck'),
      accentColor: balanceColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.query_stats_outlined,
                color: balanceColor,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据洞察台',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_statisticsSignalLabel(overview.balance)} · 结余率 ${savingRate.toStringAsFixed(0)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _StatisticsSignalBadge(overview: overview),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatisticsDeckMetric(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '净现金流',
                  value: _formatCurrency(overview.balance),
                  color: balanceColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsDeckMetric(
                  icon: Icons.savings_outlined,
                  label: '结余率',
                  value: '${savingRate.toStringAsFixed(0)}%',
                  color: balanceColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsDeckMetric(
                  icon: Icons.receipt_long_outlined,
                  label: '交易活跃',
                  value: '${overview.transactionCount} 笔',
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatisticsDeckMetric(
                  icon: Icons.stacked_bar_chart_outlined,
                  label: '趋势节点',
                  value: '${dashboard.trend.items.length} 个',
                  color: colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsDeckMetric(
                  icon: Icons.donut_large_outlined,
                  label: '分类样本',
                  value: '${dashboard.categories.items.length} 类',
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

class _StatisticsSignalBadge extends StatelessWidget {
  const _StatisticsSignalBadge({required this.overview});

  final StatisticsOverviewData overview;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final color = overview.balance > 0
        ? financeColors.income
        : overview.balance < 0
        ? colorScheme.error
        : colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statisticsSignalIcon(overview.balance), size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            overview.balance >= 0 ? '现金流正向' : '现金流承压',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsDeckMetric extends StatelessWidget {
  const _StatisticsDeckMetric({
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
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(9),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsThemeDataStrip extends StatelessWidget {
  const _StatisticsThemeDataStrip({
    required this.dashboard,
    required this.settings,
  });

  final StatisticsDashboard dashboard;
  final AppThemeSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;
    final overview = dashboard.overview;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final savingRate = _savingRate(overview);
    return PremiumSurface(
      key: const ValueKey('statistics-theme-data-strip'),
      accentColor: palette.seedColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.gradient_outlined,
                color: palette.seedColor,
                size: 40,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据皮肤',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${palette.label} · 图表、分类和现金流语义色同步',
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
              _StatisticsPaletteSwatches(palette: palette),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatisticsToneChip(
                  label: '收入',
                  value: _formatCurrency(overview.income),
                  icon: Icons.south_west_rounded,
                  color: financeColors.income,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsToneChip(
                  label: '支出',
                  value: _formatCurrency(overview.expense),
                  icon: Icons.north_east_rounded,
                  color: financeColors.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatisticsToneChip(
                  label: '结余率',
                  value: '${savingRate.toStringAsFixed(0)}%',
                  icon: Icons.savings_outlined,
                  color: overview.balance >= 0
                      ? financeColors.income
                      : financeColors.expense,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatisticsToneChip(
                  label: '主题',
                  value: palette.signature,
                  icon: Icons.palette_outlined,
                  color: palette.seedColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatisticsToneChip extends StatelessWidget {
  const _StatisticsToneChip({
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

class _StatisticsPaletteSwatches extends StatelessWidget {
  const _StatisticsPaletteSwatches({required this.palette});

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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.overview});

  final StatisticsOverviewData overview;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final balanceColor = overview.balance >= 0
        ? financeColors.income
        : Theme.of(context).colorScheme.error;
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '本月总支出 ${_formatCurrency(overview.expense)}',
      child: PremiumSurface(
        accentColor: financeColors.expense,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: Icons.payments_outlined,
                  color: financeColors.expense,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '本月总支出',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _formatCurrency(overview.expense),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            _OverviewInsightStrip(overview: overview),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                MetricPill(
                  label: '收入',
                  value: _formatCurrency(overview.income),
                  icon: Icons.south_west,
                  color: financeColors.income,
                ),
                MetricPill(
                  label: '结余',
                  value: _formatCurrency(overview.balance),
                  icon: Icons.trending_up,
                  color: balanceColor,
                ),
                MetricPill(
                  label: '日均支出',
                  value: _formatCurrency(overview.dailyAverage),
                  icon: Icons.calendar_today_outlined,
                  color: colorScheme.primary,
                ),
                MetricPill(
                  label: '交易笔数',
                  value: '${overview.transactionCount} 笔',
                  icon: Icons.receipt_long_outlined,
                  color: colorScheme.outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewInsightStrip extends StatelessWidget {
  const _OverviewInsightStrip({required this.overview});

  final StatisticsOverviewData overview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final savingRate = _savingRate(overview);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _InsightChip(
            icon: Icons.savings_outlined,
            label: '结余率',
            value: '${savingRate.toStringAsFixed(0)}%',
            color: overview.balance >= 0
                ? financeColors.income
                : financeColors.expense,
          ),
          _InsightChip(
            icon: _changeIcon(overview.incomeChange),
            label: '收入变化',
            value: _formatPercentChange(overview.incomeChange),
            color: _changeColor(
              context,
              overview.incomeChange,
              positiveGood: true,
            ),
          ),
          _InsightChip(
            icon: _changeIcon(overview.expenseChange),
            label: '支出变化',
            value: _formatPercentChange(overview.expenseChange),
            color: _changeColor(
              context,
              overview.expenseChange,
              positiveGood: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                child: Text(
                  '分类排行',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
            Text(
              '总计 ${_formatCurrency(response.total)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in response.items)
              CategoryRankTile(
                name: item.categoryName,
                icon: item.icon,
                amount: _formatCurrency(item.amount),
                percentage: item.percentage,
                count: item.count,
                color: _parseColor(
                  item.color,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
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

double _savingRate(StatisticsOverviewData overview) {
  return overview.income > 0
      ? (overview.balance / overview.income * 100).clamp(-999.0, 999.0)
      : 0.0;
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

String _statisticsSignalLabel(double balance) {
  if (balance > 0) {
    return '本月现金流稳健';
  }
  if (balance < 0) {
    return '本月现金流承压';
  }
  return '本月现金流持平';
}

IconData _statisticsSignalIcon(double balance) {
  if (balance > 0) {
    return Icons.verified_outlined;
  }
  if (balance < 0) {
    return Icons.priority_high_outlined;
  }
  return Icons.drag_handle_outlined;
}

String _formatPercentChange(double value) {
  if (value == 0) {
    return '0%';
  }
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(0)}%';
}

IconData _changeIcon(double value) {
  if (value > 0) {
    return Icons.trending_up;
  }
  if (value < 0) {
    return Icons.trending_down;
  }
  return Icons.trending_flat;
}

Color _changeColor(
  BuildContext context,
  double value, {
  required bool positiveGood,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final financeColors = AppTheme.financeColors(context);
  if (value == 0) {
    return colorScheme.outline;
  }
  final isGood = positiveGood ? value > 0 : value < 0;
  return isGood ? financeColors.income : financeColors.expense;
}
