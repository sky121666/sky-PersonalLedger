import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../data/home_repository.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  /// 构建首页概览页面。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryState = ref.watch(homeSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(homeSummaryProvider),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
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
          onRefresh: () => ref.refresh(homeSummaryProvider.future),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.summary, required this.onRefresh});

  final HomeSummary summary;
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
            Text(
              '个人记账',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '下拉可刷新账户、统计和预算数据',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            _NetAssetsCard(accounts: summary.accounts),
            const SizedBox(height: 16),
            _MonthlyOverviewCard(overview: summary.overview),
            const SizedBox(height: 16),
            _AccountOverviewCard(
              accounts: visibleAccounts,
              totalCount: accounts.length,
            ),
            const SizedBox(height: 16),
            _BudgetSummaryCard(summary: summary.budgetSummary),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => context.push(AppRoutePaths.legacyWebView),
              child: const Text('进入 Legacy WebView 兜底页'),
            ),
          ],
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
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '净资产',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _formatCurrency(accounts.netAssets),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: '总资产',
                    value: _formatCurrency(accounts.totalAssets),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricTile(
                    label: '总负债',
                    value: _formatCurrency(accounts.totalLiabilities),
                    icon: Icons.credit_card_outlined,
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

class _MonthlyOverviewCard extends StatelessWidget {
  const _MonthlyOverviewCard({required this.overview});

  final StatisticsOverview overview;

  /// 构建本月收支卡片。
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本月收支',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _AmountColumn(
                    label: '收入',
                    value: overview.income,
                    color: Colors.redAccent,
                  ),
                ),
                Expanded(
                  child: _AmountColumn(
                    label: '支出',
                    value: overview.expense,
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _AmountColumn(
                    label: '结余',
                    value: overview.balance,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '本月已记 ${overview.transactionCount} 笔',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '账户概览',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$totalCount 个账户',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (accounts.isEmpty)
              const _EmptyCardLine(text: '暂无账户，请先创建账户')
            else
              ...accounts.map((account) => _AccountLine(account: account)),
          ],
        ),
      ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '预算摘要',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (!hasBudget)
              const _EmptyCardLine(text: '本月暂未设置预算')
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('已用 ${summary.percentage.toStringAsFixed(1)}%'),
                  Text(
                    '${_formatCurrency(summary.totalSpent)} / ${_formatCurrency(summary.totalAmount)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _BudgetInfoItem(
                      label: '剩余预算',
                      value: _formatCurrency(summary.remainingAmount),
                    ),
                  ),
                  Expanded(
                    child: _BudgetInfoItem(
                      label: '日可用',
                      value: _formatCurrency(summary.dailyAvailable),
                    ),
                  ),
                  Expanded(
                    child: _BudgetInfoItem(
                      label: '剩余天数',
                      value: '${summary.daysRemaining} 天',
                    ),
                  ),
                ],
              ),
              if (summary.overBudgetCategories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '超预算：${summary.overBudgetCategories.map((item) => item.name).join('、')}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  /// 构建净资产指标项。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.onPrimaryContainer),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  const _AmountColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  /// 构建本月收支金额列。
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          _formatCurrency(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.account});

  final Account account;

  /// 构建账户列表行。
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Text(account.icon, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatCurrency(account.currentBalance),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: account.isDebt ? Colors.redAccent : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetInfoItem extends StatelessWidget {
  const _BudgetInfoItem({required this.label, required this.value});

  final String label;
  final String value;

  /// 构建预算信息项。
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
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
