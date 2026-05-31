import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../application/ledger_refresh.dart';
import '../application/transaction_list_controller.dart';
import '../data/transaction_models.dart';
import '../data/transaction_repository.dart';

class TransactionDetailsPage extends ConsumerStatefulWidget {
  const TransactionDetailsPage({super.key});

  @override
  ConsumerState<TransactionDetailsPage> createState() =>
      _TransactionDetailsPageState();
}

class _TransactionDetailsPageState
    extends ConsumerState<TransactionDetailsPage> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};

  /// 初始化列表滚动监听。
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  /// 释放列表页面资源。
  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 构建交易明细列表页。
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionListControllerProvider);
    final controller = ref.read(transactionListControllerProvider.notifier);
    final themeSettings = ref.watch(themeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: _selectedIds.isEmpty
            ? null
            : IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
                tooltip: '退出选择',
              ),
        title: Text(
          _selectedIds.isEmpty ? '明细' : '已选择 ${_selectedIds.length} 笔',
        ),
        actions: _selectedIds.isEmpty
            ? [
                IconButton(
                  onPressed: () => context.push(AppRoutePaths.quickTransaction),
                  icon: const Icon(Icons.add),
                  tooltip: '记一笔',
                ),
              ]
            : [
                IconButton(
                  onPressed: state.items.isEmpty
                      ? null
                      : () => _selectCurrentPage(state.items),
                  icon: const Icon(Icons.select_all),
                  tooltip: '全选当前页',
                ),
                IconButton(
                  onPressed: _confirmBatchDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除选中交易',
                ),
              ],
      ),
      body: AdaptivePageContainer(
        child: _buildContent(
          state: state,
          controller: controller,
          palette: themeSettings.palette,
        ),
      ),
    );
  }

  Widget _buildContent({
    required TransactionListState state,
    required TransactionListController controller,
    required AppThemePalette palette,
  }) {
    if (state.isLoading && state.items.isEmpty) {
      return const AppLoadingView(message: '加载交易中...');
    }

    if (state.errorMessage != null && state.items.isEmpty) {
      return AppErrorView(
        message: state.errorMessage!,
        onRetry: controller.refresh,
      );
    }

    if (state.items.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        children: [
          ..._buildHeaderWidgets(state, controller, palette),
          const SizedBox(height: 8),
          AppEmptyView(
            title: state.hasActiveFilter ? '没有匹配的交易' : '暂无交易明细',
            message: state.hasActiveFilter ? '调整筛选条件后再试。' : '点击“记一笔”添加第一条收支记录。',
            icon: Icons.receipt_long_outlined,
            action: FilledButton.tonal(
              onPressed: () => context.push(AppRoutePaths.quickTransaction),
              child: const Text('去记一笔'),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: state.items.length + 5,
        itemBuilder: (context, index) {
          if (index == 0) {
            return StaggeredEntrance(
              index: 0,
              child: _TransactionOverviewCard(state: state),
            );
          }
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StaggeredEntrance(
                index: 1,
                child: _TransactionLedgerSignalStrip(
                  state: state,
                  palette: palette,
                ),
              ),
            );
          }
          if (index == 2) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StaggeredEntrance(
                index: 2,
                child: _TransactionInsightRail(state: state, palette: palette),
              ),
            );
          }
          if (index == 3) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: StaggeredEntrance(
                index: 3,
                child: _TransactionFilterWorkbench(
                  state: state,
                  controller: _searchController,
                  onChanged: controller.updateKeyword,
                  onClear: () {
                    _searchController.clear();
                    controller.clearFilters();
                  },
                  onFilterChanged: controller.updateFilters,
                ),
              ),
            );
          }
          if (index == state.items.length + 4) {
            return _LoadMoreIndicator(state: state);
          }
          final itemIndex = index - 4;
          final item = state.items[itemIndex];
          return StaggeredEntrance(
            index: itemIndex.clamp(0, 5),
            offset: const Offset(0, 8),
            child: _TransactionListTile(
              item: item,
              selectionMode: _selectedIds.isNotEmpty,
              selected: _selectedIds.contains(item.id),
              onTap: () =>
                  context.push(AppRoutePaths.quickTransaction, extra: item),
              onSelectionToggle: () => _toggleSelection(item.id),
              onDelete: () => _confirmDelete(item),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildHeaderWidgets(
    TransactionListState state,
    TransactionListController controller,
    AppThemePalette palette,
  ) {
    return [
      StaggeredEntrance(
        index: 0,
        child: _TransactionOverviewCard(state: state),
      ),
      const SizedBox(height: 8),
      StaggeredEntrance(
        index: 1,
        child: _TransactionLedgerSignalStrip(state: state, palette: palette),
      ),
      const SizedBox(height: 8),
      StaggeredEntrance(
        index: 2,
        child: _TransactionInsightRail(state: state, palette: palette),
      ),
      const SizedBox(height: 8),
      StaggeredEntrance(
        index: 3,
        child: _TransactionFilterWorkbench(
          state: state,
          controller: _searchController,
          onChanged: controller.updateKeyword,
          onClear: () {
            _searchController.clear();
            controller.clearFilters();
          },
          onFilterChanged: controller.updateFilters,
        ),
      ),
    ];
  }

  Future<void> _confirmDelete(TransactionItem item) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除交易',
      message: '确定删除「${item.displayTitle}」这笔交易吗？删除后账户余额会同步回滚。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await ref
          .read(transactionListControllerProvider.notifier)
          .deleteTransaction(item.id);
      ref.invalidateLedgerMutationViews();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('交易已删除')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _confirmBatchDelete() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }

    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除选中交易',
      message: '确定删除选中的 ${ids.length} 笔交易吗？删除后账户余额会同步回滚。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await ref
          .read(transactionListControllerProvider.notifier)
          .deleteTransactions(ids);
      ref.invalidateLedgerMutationViews();
      if (mounted) {
        setState(_selectedIds.clear);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已删除 ${ids.length} 笔交易')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('批量删除失败：$error')));
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _selectCurrentPage(List<TransactionItem> items) {
    setState(() {
      _selectedIds.addAll(items.map((item) => item.id));
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 420) {
      ref.read(transactionListControllerProvider.notifier).loadMore();
    }
  }
}

class _TransactionOverviewCard extends StatelessWidget {
  const _TransactionOverviewCard({required this.state});

  final TransactionListState state;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final income = _sumByType(TransactionType.income);
    final expense = _sumByType(TransactionType.expense);
    final net = income - expense;
    final accent = net >= 0 ? financeColors.income : financeColors.expense;
    final averageAmount = state.items.isEmpty
        ? 0.0
        : state.items.fold<double>(0, (sum, item) => sum + item.amount) /
              state.items.length;

    return PremiumSurface(
      accentColor: accent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.receipt_long_outlined,
                color: accent,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.hasActiveFilter ? '筛选结果概览' : '交易明细总览',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '当前列表 ${state.items.length} 笔 · 共 ${state.total} 笔',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _OverviewDeltaBadge(value: net, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OverviewMetric(
                  label: '收入',
                  value: income,
                  color: financeColors.income,
                  icon: Icons.south_west,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OverviewMetric(
                  label: '支出',
                  value: expense,
                  color: financeColors.expense,
                  icon: Icons.north_east,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OverviewMetric(
                  label: '均笔',
                  value: averageAmount,
                  color: colorScheme.primary,
                  icon: Icons.analytics_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _sumByType(TransactionType type) {
    return state.items
        .where((item) => item.type == type)
        .fold(0, (total, item) => total + item.amount);
  }
}

class _OverviewDeltaBadge extends StatelessWidget {
  const _OverviewDeltaBadge({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sign = value >= 0 ? '+' : '-';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$sign¥${value.abs().toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _OverviewMetricShell(
      label: label,
      value: '¥${value.toStringAsFixed(2)}',
      color: color,
      icon: icon,
    );
  }
}

class _OverviewMetricShell extends StatelessWidget {
  const _OverviewMetricShell({
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.all(8),
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
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 5),
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

class _TransactionLedgerSignalStrip extends StatelessWidget {
  const _TransactionLedgerSignalStrip({
    required this.state,
    required this.palette,
  });

  final TransactionListState state;
  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final incomeCount = state.items
        .where((item) => item.type == TransactionType.income)
        .length;
    final expenseCount = state.items
        .where((item) => item.type == TransactionType.expense)
        .length;
    final transferCount = state.items
        .where((item) => item.type == TransactionType.transfer)
        .length;
    final taggedCount = state.items
        .where((item) => item.tags.isNotEmpty)
        .length;
    final activeFilterCount = [
      state.keyword.trim().isNotEmpty,
      state.type != null,
      state.accountId != null && state.accountId!.isNotEmpty,
      state.categoryId != null && state.categoryId!.isNotEmpty,
    ].where((active) => active).length;
    final signalColor = state.hasActiveFilter
        ? palette.assetColor
        : expenseCount > incomeCount
        ? financeColors.expense
        : financeColors.income;
    final densityLabel = state.items.isEmpty
        ? '等待记录'
        : state.items.length >= 20
        ? '高频'
        : '轻量';

    return PremiumSurface(
      key: const ValueKey('transaction-ledger-signal-strip'),
      accentColor: signalColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.analytics_outlined,
                color: signalColor,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '流水信号带',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.hasActiveFilter
                          ? '筛选视图 · $activeFilterCount 项条件'
                          : '全量视图 · ${state.total} 笔记录',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              _TransactionSignalPill(
                icon: Icons.palette_outlined,
                label: palette.label,
                color: palette.seedColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TransactionSignalPill(
                icon: Icons.south_west,
                label: '收入 $incomeCount',
                color: financeColors.income,
              ),
              _TransactionSignalPill(
                icon: Icons.north_east,
                label: '支出 $expenseCount',
                color: financeColors.expense,
              ),
              _TransactionSignalPill(
                icon: Icons.swap_horiz,
                label: '转账 $transferCount',
                color: palette.assetColor,
              ),
              _TransactionSignalPill(
                icon: taggedCount > 0
                    ? Icons.label_important_outline
                    : Icons.label_outline,
                label: taggedCount > 0 ? '标签 $taggedCount' : '无标签',
                color: colorScheme.secondary,
              ),
              _TransactionSignalPill(
                icon: Icons.speed_outlined,
                label: densityLabel,
                color: palette.warningColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionInsightRail extends StatelessWidget {
  const _TransactionInsightRail({required this.state, required this.palette});

  final TransactionListState state;
  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final largest = state.items.fold<TransactionItem?>(
      null,
      (current, item) =>
          current == null || item.amount > current.amount ? item : current,
    );
    final latest = state.items.fold<TransactionItem?>(
      null,
      (current, item) =>
          current == null ||
              item.transactionDate.isAfter(current.transactionDate)
          ? item
          : current,
    );
    final tagged = state.items.where((item) => item.tags.isNotEmpty).length;
    final transfer = state.items
        .where((item) => item.type == TransactionType.transfer)
        .length;
    final income = state.items
        .where((item) => item.type == TransactionType.income)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final expense = state.items
        .where((item) => item.type == TransactionType.expense)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final net = income - expense;
    final dominantColor = net >= 0
        ? financeColors.income
        : financeColors.expense;
    final coverage = state.items.isEmpty
        ? 0
        : ((tagged / state.items.length) * 100).round();
    final title = state.hasActiveFilter ? '筛选洞察轨道' : '交易洞察轨道';
    final subtitle = state.hasActiveFilter
        ? '当前条件下的金额、标签和最近交易'
        : '从全量列表提炼高频判断信号';

    return PremiumSurface(
      key: const ValueKey('transaction-insight-rail'),
      accentColor: dominantColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.route_outlined,
                color: dominantColor,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _TransactionSignalPill(
                icon: net >= 0 ? Icons.trending_up : Icons.trending_down,
                label: net >= 0 ? '净流入' : '净流出',
                color: dominantColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.8,
            children: [
              _InsightRailTile(
                icon: Icons.bolt_outlined,
                label: '最大金额',
                value: largest == null
                    ? '¥0.00'
                    : '¥${largest.amount.toStringAsFixed(2)}',
                caption: largest?.displayTitle ?? '暂无记录',
                color: largest == null
                    ? colorScheme.outline
                    : _typeColor(context, largest.type),
              ),
              _InsightRailTile(
                icon: Icons.schedule_outlined,
                label: '最近一笔',
                value: latest == null ? '--' : latest.displayTitle,
                caption: latest == null
                    ? '等待同步'
                    : _formatDateTime(latest.transactionDate),
                color: palette.assetColor,
              ),
              _InsightRailTile(
                icon: Icons.sell_outlined,
                label: '标签覆盖',
                value: '$coverage%',
                caption: '$tagged/${state.items.length} 笔已标记',
                color: colorScheme.secondary,
              ),
              _InsightRailTile(
                icon: Icons.swap_calls_outlined,
                label: '转账轨迹',
                value: '$transfer 笔',
                caption: transfer > 0 ? '需要留意账户联动' : '暂无账户迁移',
                color: palette.warningColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightRailTile extends StatelessWidget {
  const _InsightRailTile({
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
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(10),
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
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
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
                const SizedBox(height: 1),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionSignalPill extends StatelessWidget {
  const _TransactionSignalPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 34, maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionFilterWorkbench extends ConsumerWidget {
  const _TransactionFilterWorkbench({
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilterChanged,
  });

  final TransactionListState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Future<void> Function({
    TransactionType? type,
    String? accountId,
    String? categoryId,
    bool clearType,
    bool clearAccount,
    bool clearCategory,
  })
  onFilterChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final activeCount = [
      state.keyword.trim().isNotEmpty,
      state.type != null,
      state.accountId != null && state.accountId!.isNotEmpty,
      state.categoryId != null && state.categoryId!.isNotEmpty,
    ].where((active) => active).length;

    return PremiumSurface(
      key: const ValueKey('transaction-filter-workbench'),
      padding: const EdgeInsets.all(14),
      accentColor: colorScheme.primary,
      child: FutureBuilder<List<LedgerAccount>>(
        future: ref.read(transactionRepositoryProvider).listAccounts(),
        builder: (context, snapshot) {
          final accounts = snapshot.data ?? const <LedgerAccount>[];
          final accountLabel = _selectedAccountLabel(accounts);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: Icons.tune_rounded,
                    color: colorScheme.primary,
                    size: 42,
                    iconSize: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '交易筛选工作台',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.hasActiveFilter
                              ? '已启用 $activeCount 项条件 · 命中 ${state.items.length}/${state.total} 笔'
                              : '快速定位备注、类型和账户流水',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (state.hasActiveFilter)
                    TextButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('清空'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('transaction-search'),
                controller: controller,
                decoration: InputDecoration(
                  hintText: '搜索备注、标签或交易说明',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: onClear,
                          icon: const Icon(Icons.close),
                          tooltip: '清空搜索',
                        ),
                ),
                onChanged: onChanged,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _FilterStatusPill(
                    icon: Icons.segment_outlined,
                    label: state.type?.label ?? '类型不限',
                    color: _typeColor(context, state.type),
                    selected: state.type != null,
                  ),
                  _FilterStatusPill(
                    icon: Icons.account_balance_wallet_outlined,
                    label: accountLabel,
                    color: financeColors.asset,
                    selected:
                        state.accountId != null && state.accountId!.isNotEmpty,
                  ),
                  _FilterStatusPill(
                    icon: Icons.search_rounded,
                    label: state.keyword.trim().isEmpty
                        ? '未输入关键词'
                        : '关键词 ${state.keyword.trim()}',
                    color: colorScheme.secondary,
                    selected: state.keyword.trim().isNotEmpty,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TransactionFilterControls(
                state: state,
                accounts: accounts,
                onChanged: onFilterChanged,
              ),
            ],
          );
        },
      ),
    );
  }

  String _selectedAccountLabel(List<LedgerAccount> accounts) {
    final accountId = state.accountId;
    if (accountId == null || accountId.isEmpty) {
      return '账户不限';
    }
    for (final account in accounts) {
      if (account.id == accountId) {
        return account.name;
      }
    }
    return '指定账户';
  }
}

class _FilterStatusPill extends StatelessWidget {
  const _FilterStatusPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? color.withValues(alpha: 0.13)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.62);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? color.withValues(alpha: 0.28)
              : colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: selected ? color : colorScheme.outline),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? color : colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionFilterControls extends StatelessWidget {
  const _TransactionFilterControls({
    required this.state,
    required this.accounts,
    required this.onChanged,
  });

  final TransactionListState state;
  final List<LedgerAccount> accounts;
  final Future<void> Function({
    TransactionType? type,
    String? accountId,
    String? categoryId,
    bool clearType,
    bool clearAccount,
    bool clearCategory,
  })
  onChanged;

  /// 构建交易筛选栏。
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            avatar: const Icon(Icons.all_inclusive_rounded, size: 18),
            selected: state.type == null,
            label: const Text('全部类型'),
            onSelected: (_) => onChanged(clearType: true),
          ),
          const SizedBox(width: 8),
          for (final type in TransactionType.values) ...[
            FilterChip(
              avatar: Icon(_typeIcon(type), size: 18),
              selected: state.type == type,
              label: Text(type.label),
              onSelected: (_) => onChanged(type: type),
            ),
            const SizedBox(width: 8),
          ],
          if (accounts.isNotEmpty)
            DropdownMenu<String>(
              width: 158,
              initialSelection: state.accountId ?? '',
              leadingIcon: const Icon(Icons.account_balance_wallet_outlined),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: '', label: '全部账户'),
                ...accounts.map(
                  (account) =>
                      DropdownMenuEntry(value: account.id, label: account.name),
                ),
              ],
              onSelected: (value) {
                if (value == null || value.isEmpty) {
                  onChanged(clearAccount: true);
                } else {
                  onChanged(accountId: value);
                }
              },
            ),
        ],
      ),
    );
  }
}

Color _typeColor(BuildContext context, TransactionType? type) {
  final colorScheme = Theme.of(context).colorScheme;
  final financeColors = AppTheme.financeColors(context);
  return switch (type) {
    TransactionType.income => financeColors.income,
    TransactionType.expense => financeColors.expense,
    TransactionType.transfer => colorScheme.primary,
    null => colorScheme.primary,
  };
}

IconData _typeIcon(TransactionType type) {
  return switch (type) {
    TransactionType.income => Icons.south_west,
    TransactionType.expense => Icons.north_east,
    TransactionType.transfer => Icons.swap_horiz,
  };
}

class _TransactionListTile extends StatelessWidget {
  const _TransactionListTile({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onSelectionToggle,
    required this.onDelete,
  });

  final TransactionItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSelectionToggle;
  final VoidCallback onDelete;

  /// 构建单条交易列表项。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final amountColor = switch (item.type) {
      TransactionType.income => financeColors.income,
      TransactionType.expense => colorScheme.error,
      TransactionType.transfer => colorScheme.primary,
    };
    final prefix = switch (item.type) {
      TransactionType.income => '+',
      TransactionType.expense => '-',
      TransactionType.transfer => '',
    };
    final accountLabel = item.type == TransactionType.transfer
        ? '${item.account?.name ?? '转出账户'} → ${item.toAccount?.name ?? '转入账户'}'
        : item.account?.name ?? '账户流水';

    return Semantics(
      label:
          '${item.typeLabel}，${item.displayTitle}，金额$prefix¥${item.amount.toStringAsFixed(2)}，$accountLabel，${_formatDateTime(item.transactionDate)}',
      selected: selected,
      child: Padding(
        key: ValueKey('transaction-item-${item.id}'),
        padding: const EdgeInsets.only(bottom: 10),
        child: PremiumSurface(
          accentColor: selected ? colorScheme.primary : amountColor,
          padding: EdgeInsets.zero,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.surfaceRadius),
              onTap: selectionMode ? onSelectionToggle : onTap,
              onLongPress: onSelectionToggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Checkbox(
                          key: ValueKey('transaction-select-${item.id}'),
                          value: selected,
                          onChanged: (_) => onSelectionToggle(),
                        ),
                      )
                    else
                      IconBadge(
                        icon: _typeIcon(item.type),
                        color: amountColor,
                        size: 42,
                        iconSize: 22,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$prefix¥${item.amount.toStringAsFixed(2)}',
                                key: ValueKey('transaction-amount-${item.id}'),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: amountColor,
                                      fontWeight: FontWeight.w900,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              _TransactionMetaPill(
                                icon: _typeIcon(item.type),
                                label: item.typeLabel,
                                color: amountColor,
                              ),
                              _TransactionMetaPill(
                                icon: Icons.account_balance_wallet_outlined,
                                label: accountLabel,
                                color: colorScheme.primary,
                              ),
                              _TransactionMetaPill(
                                icon: Icons.schedule_outlined,
                                label: _formatDateTime(item.transactionDate),
                                color: colorScheme.outline,
                              ),
                            ],
                          ),
                          if (item.remark.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              item.remark,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                          if (item.tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: item.tags
                                  .map(
                                    (tag) => _TransactionTagChip(
                                      label: tag,
                                      color: amountColor,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!selectionMode)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            onTap();
                          } else if (value == 'delete') {
                            onDelete();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(TransactionType type) {
    return switch (type) {
      TransactionType.income => Icons.south_west,
      TransactionType.expense => Icons.north_east,
      TransactionType.transfer => Icons.swap_horiz,
    };
  }
}

class _TransactionMetaPill extends StatelessWidget {
  const _TransactionMetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 26, maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.09),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

class _TransactionTagChip extends StatelessWidget {
  const _TransactionTagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator({required this.state});

  final TransactionListState state;

  /// 构建分页加载状态提示。
  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text('没有更多了', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return const SizedBox(height: 56);
  }
}

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}
