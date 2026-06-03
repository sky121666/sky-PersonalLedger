import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/ledger_icon.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../transactions/data/transaction_models.dart';
import '../data/home_repository.dart';
import 'widgets/home_dashboard_widgets.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  DateTime _selectedDate = _dateOnly(DateTime.now());

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _selectedDate = _dateOnly(picked));
  }

  /// 构建首页概览页面。
  @override
  Widget build(BuildContext context) {
    final summaryState = ref.watch(homeSummaryProvider);
    final dateTransactionsState = ref.watch(
      homeDateTransactionsProvider(_selectedDate),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(homeSummaryProvider),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新首页概览',
          ),
        ],
      ),
      body: summaryState.when(
        loading: () => const AppLoadingView(message: '正在加载首页数据...'),
        error: (error, stackTrace) => _HomeErrorView(
          message: '首页数据加载失败',
          onRefresh: () => ref.refresh(homeSummaryProvider.future),
          onRetry: () => ref.invalidate(homeSummaryProvider),
        ),
        data: (summary) => _HomeContent(
          summary: summary,
          selectedDate: _selectedDate,
          dateTransactionsState: dateTransactionsState,
          onSelectDate: _selectDate,
          onRefresh: () => ref.refresh(homeSummaryProvider.future),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.summary,
    required this.selectedDate,
    required this.dateTransactionsState,
    required this.onSelectDate,
    required this.onRefresh,
  });

  final HomeSummary summary;
  final DateTime selectedDate;
  final AsyncValue<List<TransactionItem>> dateTransactionsState;
  final VoidCallback onSelectDate;
  final Future<void> Function() onRefresh;

  /// 构建首页数据内容。
  @override
  Widget build(BuildContext context) {
    final accounts = summary.accounts.activeAccounts;
    final visibleAccounts = _prioritizedHomeAccounts(accounts).take(3).toList();
    final rows = [
      _HomeRow(_NetAssetsCard(accounts: summary.accounts)),
      _HomeRow(_MonthlyOverviewCard(overview: summary.overview)),
      _HomeRow(
        _AccountOverviewCard(
          accounts: visibleAccounts,
          totalCount: accounts.length,
        ),
      ),
      _HomeRow(_BudgetSummaryCard(summary: summary.budgetSummary)),
      _HomeRow(FamilyHomeSummaryCard(summary: summary.familySummary)),
      _HomeRow(_RecentTransactionsCard(items: summary.recentTransactions)),
      _HomeRow(
        _DateTransactionsCard(
          selectedDate: selectedDate,
          state: dateTransactionsState,
          onSelectDate: onSelectDate,
        ),
      ),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: rows.length,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.only(bottom: index == rows.length - 1 ? 0 : 10),
            child: rows[index].child,
          ),
        ),
      ),
    );
  }
}

class _HomeRow {
  const _HomeRow(this.child);

  final Widget child;
}

class _RecentTransactionsCard extends StatelessWidget {
  const _RecentTransactionsCard({required this.items});

  static const _previewCount = 3;

  final List<TransactionItem> items;

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
              const Icon(Icons.receipt_long_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '最近交易',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => context.push(AppRoutePaths.transactions),
                icon: const Icon(Icons.arrow_forward_rounded),
                tooltip: '查看全部明细',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const _HomeEmptyLine(text: '还没有交易')
          else
            ...items
                .take(_previewCount)
                .map((item) => _HomeTransactionRow(item: item)),
        ],
      ),
    );
  }
}

class _DateTransactionsCard extends StatelessWidget {
  const _DateTransactionsCard({
    required this.selectedDate,
    required this.state,
    required this.onSelectDate,
  });

  static const _previewCount = 3;

  final DateTime selectedDate;
  final AsyncValue<List<TransactionItem>> state;
  final VoidCallback onSelectDate;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.income,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当日交易',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onSelectDate,
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: Text(_formatDateLabel(selectedDate)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          state.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
            error: (error, stackTrace) =>
                Text('明细加载失败', style: Theme.of(context).textTheme.bodySmall),
            data: (items) => items.isEmpty
                ? const _HomeEmptyLine(text: '当日无交易')
                : Column(
                    children: [
                      for (final item in items.take(_previewCount))
                        _HomeTransactionRow(item: item),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HomeTransactionRow extends StatefulWidget {
  const _HomeTransactionRow({required this.item});

  final TransactionItem item;

  @override
  State<_HomeTransactionRow> createState() => _HomeTransactionRowState();
}

class _HomeTransactionRowState extends State<_HomeTransactionRow> {
  bool _showRemark = false;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final item = widget.item;
    final color = switch (item.type) {
      TransactionType.income => financeColors.income,
      TransactionType.transfer => Theme.of(context).colorScheme.primary,
      TransactionType.expense => financeColors.expense,
    };
    return InkWell(
      onTap: () => context.push(AppRoutePaths.quickTransaction, extra: item),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_transactionIcon(item.type), color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.remark.isNotEmpty)
                        IconButton(
                          onPressed: () {
                            setState(() => _showRemark = !_showRemark);
                          },
                          icon: Icon(_showRemark ? Icons.remove : Icons.add),
                          tooltip: _showRemark ? '收起备注' : '展开备注',
                          iconSize: 18,
                        ),
                      Text(
                        _formatSignedTransactionAmount(item),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_showRemark && item.remark.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.remark,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeEmptyLine extends StatelessWidget {
  const _HomeEmptyLine({required this.text});

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
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: financeColors.income,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '本月现金流',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${overview.transactionCount} 笔',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniMoneyStat(
                  label: '收入',
                  value: _formatCurrency(overview.income),
                  color: financeColors.income,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniMoneyStat(
                  label: '支出',
                  value: _formatCurrency(overview.expense),
                  color: financeColors.expense,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniMoneyStat(
                  label: '结余',
                  value: _formatCurrency(overview.balance),
                  color: balanceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CashFlowBar(overview: overview),
        ],
      ),
    );
  }
}

class _MiniMoneyStat extends StatelessWidget {
  const _MiniMoneyStat({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.07),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
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

class _CashFlowBar extends StatelessWidget {
  const _CashFlowBar({required this.overview});

  final StatisticsOverview overview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final totalFlow = overview.income + overview.expense;
    final incomeRatio = totalFlow > 0 ? overview.income / totalFlow : 0.0;
    final expenseRatio = totalFlow > 0 ? overview.expense / totalFlow : 0.0;

    if (totalFlow <= 0) {
      return Text(
        '本月无现金流',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: (incomeRatio * 100).round().clamp(1, 100),
                  child: ColoredBox(color: financeColors.income),
                ),
                Expanded(
                  flex: (expenseRatio * 100).round().clamp(1, 100),
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
          ],
        ),
      ],
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
                          label: hasBudget ? '已设置' : '未启用',
                          color: hasBudget
                              ? financeColors.warning
                              : colorScheme.outline,
                        ),
                        Text(
                          hasBudget
                              ? '${_formatCurrency(summary.totalSpent)} / ${_formatCurrency(summary.totalAmount)}'
                              : '本月未设置预算',
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
            const _EmptyCardLine(text: '还没有账户')
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
        '$totalCount 个',
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
      child: Container(
        key: ValueKey('home-account-line-${account.id}'),
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
                  const SizedBox(height: 4),
                  Text(
                    account.isArchived ? '$typeLabel · 已归档' : typeLabel,
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

List<Account> _prioritizedHomeAccounts(List<Account> accounts) {
  final indexed = accounts.indexed.toList();
  indexed.sort((left, right) {
    final leftAccount = left.$2;
    final rightAccount = right.$2;
    final leftScore = _homeAccountPriority(leftAccount);
    final rightScore = _homeAccountPriority(rightAccount);
    final scoreCompare = rightScore.compareTo(leftScore);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final balanceCompare = rightAccount.currentBalance.abs().compareTo(
      leftAccount.currentBalance.abs(),
    );
    if (balanceCompare != 0) {
      return balanceCompare;
    }
    return left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList();
}

int _homeAccountPriority(Account account) {
  var score = 0;
  if (account.currentBalance.abs() > 0.005) {
    score += 4;
  }
  if (account.isDebt) {
    score += 2;
  }
  if (account.type == 'cash' || account.type == 'bank') {
    score += 1;
  }
  return score;
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
    return Container(
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

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String _formatDateLabel(DateTime date) {
  return '${date.month}月${date.day}日';
}

IconData _transactionIcon(TransactionType type) {
  return switch (type) {
    TransactionType.income => Icons.south_west_rounded,
    TransactionType.transfer => Icons.swap_horiz_rounded,
    TransactionType.expense => Icons.north_east_rounded,
  };
}

String _formatSignedTransactionAmount(TransactionItem item) {
  final prefix = switch (item.type) {
    TransactionType.income => '+',
    TransactionType.expense => '-',
    TransactionType.transfer => '',
  };
  return '$prefix${_formatCurrency(item.amount)}';
}
