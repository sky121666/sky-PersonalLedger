import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../account_logs/presentation/account_log_page.dart';
import '../application/account_controller.dart';
import '../data/account.dart';

const _accountTypes = [
  _AccountTypeOption('cash', '现金'),
  _AccountTypeOption('bank_card', '银行卡'),
  _AccountTypeOption('savings', '储蓄卡'),
  _AccountTypeOption('alipay', '支付宝'),
  _AccountTypeOption('wechat', '微信'),
  _AccountTypeOption('qq_pay', 'QQ钱包'),
  _AccountTypeOption('jd_pay', '京东钱包'),
  _AccountTypeOption('apple_pay', 'Apple Pay'),
  _AccountTypeOption('credit', '信用卡'),
  _AccountTypeOption('loan', '贷款'),
  _AccountTypeOption('mortgage', '房贷'),
  _AccountTypeOption('car_loan', '车贷'),
  _AccountTypeOption('consumer_loan', '消费贷'),
  _AccountTypeOption('huabei', '花呗'),
  _AccountTypeOption('baitiao', '白条'),
  _AccountTypeOption('receivable', '应收款'),
  _AccountTypeOption('payable', '应付款'),
  _AccountTypeOption('investment', '投资账户'),
  _AccountTypeOption('fund', '基金'),
  _AccountTypeOption('stock', '股票'),
  _AccountTypeOption('crypto', '数字货币'),
  _AccountTypeOption('prepaid', '充值卡'),
  _AccountTypeOption('other', '其他'),
];

const _debtAccountTypes = {
  'credit',
  'loan',
  'mortgage',
  'car_loan',
  'consumer_loan',
  'huabei',
  'baitiao',
};

const _accountColors = [
  '#3B82F6',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#8B5CF6',
  '#06B6D4',
  '#EC4899',
  '#64748B',
];

const _accountIconOptions = [
  _AccountIconOption('cash', '现金', Icons.payments_outlined),
  _AccountIconOption('bank_card', '卡片', Icons.credit_card_outlined),
  _AccountIconOption('apple_pay', '钱包', Icons.account_balance_wallet_outlined),
  _AccountIconOption('credit', '信用', Icons.credit_score_outlined),
  _AccountIconOption('mortgage', '贷款', Icons.request_quote_outlined),
  _AccountIconOption('investment', '投资', Icons.show_chart_outlined),
  _AccountIconOption('prepaid', '储值', Icons.card_giftcard_outlined),
  _AccountIconOption('other', '其他', Icons.grid_view_outlined),
];

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  /// 构建账户管理页。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountListControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户'),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(accountListControllerProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新账户列表',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAccountForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新增账户'),
      ),
      body: AdaptivePageContainer(
        child: state.when(
          data: (result) => _AccountContent(result: result),
          loading: () => const AppLoadingView(message: '账户加载中...'),
          error: (error, _) => AppErrorView(
            message: error.toString(),
            onRetry: () =>
                ref.read(accountListControllerProvider.notifier).load(),
          ),
        ),
      ),
    );
  }

  /// 打开新增或编辑账户表单。
  Future<void> _openAccountForm(
    BuildContext context,
    WidgetRef ref, {
    Account? account,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AccountFormSheet(account: account),
    );
  }
}

class _AccountContent extends ConsumerWidget {
  const _AccountContent({required this.result});

  final AccountListResult result;

  /// 构建账户汇总和列表内容。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeControllerProvider);
    if (result.accounts.isEmpty) {
      return StaggeredEntrance(
        index: 0,
        child: AppEmptyView(
          title: '暂无账户',
          message: '添加现金、银行卡或支付账户后即可开始记账。',
          icon: Icons.account_balance_wallet_outlined,
          action: FilledButton.icon(
            onPressed: () => _openAccountForm(context),
            icon: const Icon(Icons.add),
            label: const Text('新增账户'),
          ),
        ),
      );
    }

    final activeAccounts = result.accounts
        .where((item) => !item.isArchived)
        .toList();
    final archivedAccounts = result.accounts
        .where((item) => item.isArchived)
        .toList();
    return RefreshIndicator(
      onRefresh: () => ref.read(accountListControllerProvider.notifier).load(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          StaggeredEntrance(
            index: 0,
            child: _AccountSummaryCard(result: result),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 1,
            child: _AccountPortfolioControlStrip(
              result: result,
              themePalette: themeSettings.palette,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 2,
            child: _AccountPortfolioMatrixPanel(
              result: result,
              themePalette: themeSettings.palette,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 3,
            child: _AccountHealthScorePanel(
              result: result,
              themePalette: themeSettings.palette,
            ),
          ),
          const SizedBox(height: 16),
          _AccountSection(
            title: '正常账户',
            accounts: activeAccounts,
            sortable: true,
            startIndex: 4,
          ),
          if (archivedAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AccountSection(
              title: '已归档账户',
              accounts: archivedAccounts,
              startIndex: activeAccounts.length + 4,
            ),
          ],
        ],
      ),
    );
  }

  /// 打开新增账户表单。
  Future<void> _openAccountForm(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AccountFormSheet(),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({required this.result});

  final AccountListResult result;

  /// 构建账户资产汇总卡片。
  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final activeCount = result.accounts
        .where((item) => !item.isArchived)
        .length;
    final activeDebtCount = result.accounts
        .where((item) => !item.isArchived && _isDebtAccount(item.type))
        .length;
    final activeAssetCount = activeCount - activeDebtCount;
    return Semantics(
      label: '净资产 ${_formatMoney(result.netAssets)}',
      child: PremiumSurface(
        accentColor: financeColors.asset,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: Icons.account_balance_wallet_outlined,
                  color: financeColors.asset,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '资产概览',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _AssetHealthPill(result: result),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _formatMoney(result.netAssets),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            _AssetMixStrip(result: result),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                MetricPill(
                  label: '总资产',
                  value: _formatMoney(result.totalAssets),
                  icon: Icons.trending_up,
                  color: financeColors.income,
                ),
                MetricPill(
                  label: '总负债',
                  value: _formatMoney(result.totalLiabilities),
                  icon: Icons.trending_down,
                  color: financeColors.expense,
                ),
                MetricPill(
                  label: '资产账户',
                  value: '$activeAssetCount 个',
                  icon: Icons.account_balance_wallet_outlined,
                  color: colorScheme.primary,
                ),
                MetricPill(
                  label: '负债账户',
                  value: '$activeDebtCount 个',
                  icon: Icons.request_quote_outlined,
                  color: financeColors.expense,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetHealthPill extends StatelessWidget {
  const _AssetHealthPill({required this.result});

  final AccountListResult result;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final color = result.netAssets >= 0
        ? financeColors.income
        : financeColors.expense;
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
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        result.netAssets >= 0 ? '资产安全垫' : '负债承压',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AssetMixStrip extends StatelessWidget {
  const _AssetMixStrip({required this.result});

  final AccountListResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final total = result.totalAssets.abs() + result.totalLiabilities.abs();
    final assetRatio = total > 0 ? result.totalAssets.abs() / total : 0.0;
    final debtRatio = total > 0 ? result.totalLiabilities.abs() / total : 0.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          financeColors.asset.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: financeColors.asset.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AssetMixLegend(label: '资产占比', color: financeColors.income),
              const SizedBox(width: 12),
              _AssetMixLegend(label: '负债占比', color: financeColors.expense),
              const Spacer(),
              Text(
                total > 0
                    ? '${(assetRatio * 100).toStringAsFixed(0)}% / ${(debtRatio * 100).toStringAsFixed(0)}%'
                    : '-- / --',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
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
                    flex: math.max(1, (assetRatio * 100).round()),
                    child: ColoredBox(color: financeColors.income),
                  ),
                  Expanded(
                    flex: math.max(1, (debtRatio * 100).round()),
                    child: ColoredBox(color: financeColors.expense),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetMixLegend extends StatelessWidget {
  const _AssetMixLegend({required this.label, required this.color});

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

class _AccountPortfolioControlStrip extends StatelessWidget {
  const _AccountPortfolioControlStrip({
    required this.result,
    required this.themePalette,
  });

  final AccountListResult result;
  final AppThemePalette themePalette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final activeAccounts = result.accounts
        .where((account) => !account.isArchived)
        .toList();
    final archivedCount = result.accounts.length - activeAccounts.length;
    final debtAccounts = activeAccounts
        .where((account) => _isDebtAccount(account.type))
        .toList();
    final liquidAccounts = activeAccounts
        .where((account) => !_isDebtAccount(account.type))
        .toList();
    final debtRatio = result.totalAssets.abs() <= 0
        ? 0.0
        : result.totalLiabilities.abs() / result.totalAssets.abs();
    final debtExposureLabel = debtRatio > 1
        ? '高风险'
        : '${(debtRatio * 100).toStringAsFixed(0)}%';
    final primaryAccount = liquidAccounts.isEmpty
        ? null
        : liquidAccounts.reduce(
            (a, b) => a.currentBalance >= b.currentBalance ? a : b,
          );
    final healthColor = result.netAssets >= 0
        ? financeColors.income
        : financeColors.expense;

    return PremiumSurface(
      key: const ValueKey('account-portfolio-control-strip'),
      accentColor: themePalette.assetColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.dashboard_customize_outlined,
                color: themePalette.assetColor,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '资产控制中枢',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      primaryAccount == null
                          ? '等待建立主要资产账户'
                          : '${primaryAccount.name} · ${_formatMoney(primaryAccount.currentBalance)}',
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
              _AccountControlPill(
                icon: result.netAssets >= 0
                    ? Icons.verified_outlined
                    : Icons.warning_amber_rounded,
                label: result.netAssets >= 0 ? '净资产为正' : '负债承压',
                color: healthColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AccountControlPill(
                icon: Icons.palette_outlined,
                label: themePalette.label,
                color: themePalette.seedColor,
              ),
              _AccountControlPill(
                icon: Icons.account_balance_wallet_outlined,
                label: '活跃 ${activeAccounts.length} 个',
                color: themePalette.assetColor,
              ),
              _AccountControlPill(
                icon: archivedCount > 0
                    ? Icons.inventory_2_outlined
                    : Icons.inventory_outlined,
                label: archivedCount > 0 ? '归档 $archivedCount 个' : '无归档',
                color: archivedCount > 0
                    ? colorScheme.outline
                    : financeColors.income,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 420
                  ? (constraints.maxWidth - 16) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AccountControlMetric(
                    width: itemWidth,
                    icon: Icons.savings_outlined,
                    label: '流动账户',
                    value: '${liquidAccounts.length} 个',
                    color: financeColors.income,
                  ),
                  _AccountControlMetric(
                    width: itemWidth,
                    icon: Icons.request_quote_outlined,
                    label: '负债暴露',
                    value: debtExposureLabel,
                    color: debtAccounts.isEmpty
                        ? colorScheme.outline
                        : financeColors.expense,
                  ),
                  _AccountControlMetric(
                    width: itemWidth,
                    icon: Icons.route_outlined,
                    label: '资产路径',
                    value: result.netAssets >= 0 ? '稳健' : '收缩',
                    color: themePalette.warningColor,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountControlPill extends StatelessWidget {
  const _AccountControlPill({
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

class _AccountControlMetric extends StatelessWidget {
  const _AccountControlMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      width: width,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(10),
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
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
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

class _AccountPortfolioMatrixPanel extends StatelessWidget {
  const _AccountPortfolioMatrixPanel({
    required this.result,
    required this.themePalette,
  });

  final AccountListResult result;
  final AppThemePalette themePalette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final activeAccounts = result.accounts
        .where((account) => !account.isArchived)
        .toList();
    final assetAccounts = activeAccounts
        .where((account) => !_isDebtAccount(account.type))
        .toList();
    final debtAccounts = activeAccounts
        .where((account) => _isDebtAccount(account.type))
        .toList();
    final primaryAsset = assetAccounts.isEmpty
        ? null
        : assetAccounts.reduce(
            (a, b) => a.currentBalance >= b.currentBalance ? a : b,
          );
    final primaryDebt = debtAccounts.isEmpty
        ? null
        : debtAccounts.reduce(
            (a, b) => a.currentBalance.abs() >= b.currentBalance.abs() ? a : b,
          );
    final totalExposure =
        result.totalAssets.abs() + result.totalLiabilities.abs();
    final assetShare = totalExposure <= 0
        ? 0.0
        : result.totalAssets.abs() / totalExposure;
    final debtShare = totalExposure <= 0
        ? 0.0
        : result.totalLiabilities.abs() / totalExposure;
    final liquidityLabel = assetAccounts.length >= debtAccounts.length
        ? '流动优先'
        : '负债优先';
    final matrixColor = result.netAssets >= 0
        ? themePalette.assetColor
        : financeColors.expense;

    return PremiumSurface(
      key: const ValueKey('account-portfolio-matrix-panel'),
      accentColor: matrixColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.grid_view_outlined,
                color: matrixColor,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '账户资产矩阵',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      primaryAsset == null
                          ? '等待创建可用于记账的流动账户'
                          : '${primaryAsset.name} 是当前主要流动账户',
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
              _AccountControlPill(
                icon: Icons.account_tree_outlined,
                label: liquidityLabel,
                color: matrixColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AccountExposureBar(
            assetShare: assetShare,
            debtShare: debtShare,
            assetColor: financeColors.income,
            debtColor: financeColors.expense,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 420
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AccountMatrixTile(
                    width: itemWidth,
                    icon: Icons.savings_outlined,
                    label: '主资产账户',
                    value: primaryAsset?.name ?? '未建立',
                    meta: primaryAsset == null
                        ? '0 份'
                        : _formatMoney(primaryAsset.currentBalance),
                    color: financeColors.income,
                  ),
                  _AccountMatrixTile(
                    width: itemWidth,
                    icon: Icons.request_quote_outlined,
                    label: '主要负债',
                    value: primaryDebt?.name ?? '无负债',
                    meta: primaryDebt == null
                        ? '0 份'
                        : _formatMoney(primaryDebt.currentBalance),
                    color: primaryDebt == null
                        ? colorScheme.outline
                        : financeColors.expense,
                  ),
                  _AccountMatrixTile(
                    width: itemWidth,
                    icon: Icons.account_balance_wallet_outlined,
                    label: '账户覆盖',
                    value: '${activeAccounts.length} 个活跃',
                    meta:
                        '${assetAccounts.length} 资产 / ${debtAccounts.length} 负债',
                    color: themePalette.assetColor,
                  ),
                  _AccountMatrixTile(
                    width: itemWidth,
                    icon: Icons.auto_graph_outlined,
                    label: '结构比例',
                    value:
                        '${(assetShare * 100).toStringAsFixed(0)}% / ${(debtShare * 100).toStringAsFixed(0)}%',
                    meta: '资产 / 负债',
                    color: themePalette.warningColor,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountExposureBar extends StatelessWidget {
  const _AccountExposureBar({
    required this.assetShare,
    required this.debtShare,
    required this.assetColor,
    required this.debtColor,
  });

  final double assetShare;
  final double debtShare;
  final Color assetColor;
  final Color debtColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _AssetMixLegend(label: '资产池', color: assetColor),
            const SizedBox(width: 12),
            _AssetMixLegend(label: '负债池', color: debtColor),
            const Spacer(),
            Text(
              '矩阵占比',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                Expanded(
                  flex: math.max(1, (assetShare * 100).round()),
                  child: ColoredBox(color: assetColor),
                ),
                Expanded(
                  flex: math.max(1, (debtShare * 100).round()),
                  child: ColoredBox(color: debtColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountMatrixTile extends StatelessWidget {
  const _AccountMatrixTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.meta,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String meta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      width: width,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 92),
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
      child: Row(
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 10),
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
                const SizedBox(height: 3),
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
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

class _AccountHealthScorePanel extends StatelessWidget {
  const _AccountHealthScorePanel({
    required this.result,
    required this.themePalette,
  });

  final AccountListResult result;
  final AppThemePalette themePalette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final activeAccounts = result.accounts
        .where((account) => !account.isArchived)
        .toList();
    final assetAccounts = activeAccounts
        .where((account) => !_isDebtAccount(account.type))
        .toList();
    final debtAccounts = activeAccounts
        .where((account) => _isDebtAccount(account.type))
        .toList();
    final exposureRatio = result.totalAssets.abs() <= 0
        ? 1.0
        : (result.totalLiabilities.abs() / result.totalAssets.abs()).clamp(
            0.0,
            1.0,
          );
    final positiveNet = result.netAssets >= 0;
    final hasAssetBase = result.totalAssets > 0;
    final controlledDebt =
        result.totalAssets <= 0 ||
        result.totalLiabilities.abs() <= result.totalAssets.abs();
    final hasActiveAccounts = activeAccounts.isNotEmpty;
    final score = [
      positiveNet,
      hasAssetBase,
      controlledDebt,
      hasActiveAccounts,
    ].where((item) => item).length;
    final scoreRatio = score / 4;
    final scoreColor = score >= 3
        ? financeColors.income
        : score >= 2
        ? themePalette.warningColor
        : financeColors.expense;

    return PremiumSurface(
      key: const ValueKey('account-health-score-panel'),
      accentColor: scoreColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.health_and_safety_outlined,
                color: scoreColor,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '资产健康评分',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      positiveNet ? '净资产形成正向安全垫' : '优先压低负债暴露，恢复资产安全垫',
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
              _AccountControlPill(
                icon: positiveNet
                    ? Icons.shield_outlined
                    : Icons.priority_high_rounded,
                label: positiveNet ? '安全垫' : '承压',
                color: scoreColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                scoreColor.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.18
                      : 0.10,
                ),
                colorScheme.surface,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scoreColor.withValues(alpha: 0.16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '风险分',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$score / 4',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scoreColor,
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
                    minHeight: 10,
                    value: scoreRatio,
                    color: scoreColor,
                    backgroundColor: colorScheme.outlineVariant.withValues(
                      alpha: 0.34,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth >= 420
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AccountHealthMetric(
                    width: itemWidth,
                    icon: Icons.account_balance_outlined,
                    label: '资产安全垫',
                    value: _formatMoney(result.netAssets),
                    color: positiveNet
                        ? financeColors.income
                        : financeColors.expense,
                  ),
                  _AccountHealthMetric(
                    width: itemWidth,
                    icon: Icons.radar_outlined,
                    label: '负债暴露',
                    value: '${(exposureRatio * 100).toStringAsFixed(0)}% 占用',
                    color: debtAccounts.isEmpty
                        ? colorScheme.outline
                        : financeColors.expense,
                  ),
                  _AccountHealthMetric(
                    width: itemWidth,
                    icon: Icons.hub_outlined,
                    label: '账户覆盖',
                    value: '${activeAccounts.length} 个账户',
                    color: themePalette.assetColor,
                  ),
                  _AccountHealthMetric(
                    width: itemWidth,
                    icon: Icons.account_tree_outlined,
                    label: '资产结构',
                    value:
                        '${assetAccounts.length} 资产 / ${debtAccounts.length} 负债',
                    color: themePalette.warningColor,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountHealthMetric extends StatelessWidget {
  const _AccountHealthMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      width: width,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.15
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(width: 10),
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
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
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

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.title,
    required this.accounts,
    required this.startIndex,
    this.sortable = false,
  });

  final String title;
  final List<Account> accounts;
  final int startIndex;
  final bool sortable;

  /// 构建账户分组列表。
  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const SizedBox.shrink();
    }
    final accountIds = accounts.map((item) => item.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StaggeredEntrance(
          index: startIndex,
          child: _SectionHeader(
            title: title,
            subtitle: '${accounts.length} 个账户',
            icon: title == '已归档账户'
                ? Icons.archive_outlined
                : Icons.account_balance_wallet_outlined,
            sortable: sortable,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in accounts.indexed) ...[
          StaggeredEntrance(
            index: startIndex + entry.$1 + 1,
            child: _AccountListTile(
              account: entry.$2,
              sectionAccountIds: accountIds,
              accountIndex: entry.$1,
              canSort: sortable,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AccountListTile extends ConsumerWidget {
  const _AccountListTile({
    required this.account,
    required this.sectionAccountIds,
    required this.accountIndex,
    required this.canSort,
  });

  final Account account;
  final List<String> sectionAccountIds;
  final int accountIndex;
  final bool canSort;

  /// 构建账户列表项。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeColors = AppTheme.financeColors(context);
    final color = _parseColor(
      account.color,
      Theme.of(context).colorScheme.primary,
    );
    final isDebt = _isDebtAccount(account.type);
    final balanceColor = isDebt
        ? financeColors.expense
        : account.currentBalance >= 0
        ? financeColors.income
        : Theme.of(context).colorScheme.error;
    final delta = account.currentBalance - account.initialBalance;
    final deltaColor = isDebt
        ? financeColors.expense
        : delta >= 0
        ? financeColors.income
        : Theme.of(context).colorScheme.error;
    final statusLabel = account.isArchived
        ? '已归档'
        : isDebt
        ? '负债账户'
        : '资产账户';
    return Semantics(
      label:
          '${account.name}，${_accountTypeLabel(account.type)}，$statusLabel，当前余额${_formatMoney(account.currentBalance)}',
      button: true,
      child: PremiumSurface(
        key: ValueKey('account-card-${account.id}'),
        accentColor: color,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _handleAction(context, ref, _AccountAction.logs),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBadge(
                        icon: _accountIconData(account),
                        color: color,
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
                                Flexible(
                                  child: Text(
                                    account.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                if (account.isArchived) ...[
                                  const SizedBox(width: 8),
                                  const Chip(
                                    label: Text('已归档'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _AccountInfoChip(
                                  icon: _accountIconData(account),
                                  label: _accountTypeLabel(account.type),
                                  color: color,
                                ),
                                _AccountInfoChip(
                                  icon: isDebt
                                      ? Icons.request_quote_outlined
                                      : Icons.savings_outlined,
                                  label: isDebt ? '负债类' : '资产类',
                                  color: isDebt
                                      ? financeColors.expense
                                      : financeColors.income,
                                ),
                                _AccountInfoChip(
                                  icon: account.isArchived
                                      ? Icons.inventory_2_outlined
                                      : Icons.verified_outlined,
                                  label: account.isArchived ? '归档' : '正常',
                                  color: account.isArchived
                                      ? Theme.of(context).colorScheme.outline
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatMoney(account.currentBalance),
                            key: ValueKey('account-balance-${account.id}'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: balanceColor,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isDebt ? '剩余负债' : '当前余额',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      PopupMenuButton<_AccountAction>(
                        tooltip: '更多账户操作 ${account.name}',
                        onSelected: (action) =>
                            _handleAction(context, ref, action),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _AccountAction.logs,
                            child: Text('查看流水'),
                          ),
                          const PopupMenuItem(
                            value: _AccountAction.edit,
                            child: Text('编辑'),
                          ),
                          if (canSort) ...[
                            PopupMenuItem(
                              value: _AccountAction.moveUp,
                              enabled: accountIndex > 0,
                              child: const Text('上移'),
                            ),
                            PopupMenuItem(
                              value: _AccountAction.moveDown,
                              enabled:
                                  accountIndex < sectionAccountIds.length - 1,
                              child: const Text('下移'),
                            ),
                          ],
                          PopupMenuItem(
                            value: _AccountAction.archive,
                            child: Text(account.isArchived ? '恢复' : '归档'),
                          ),
                          const PopupMenuItem(
                            value: _AccountAction.delete,
                            child: Text('删除'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AccountBalanceSignal(
                    account: account,
                    isDebt: isDebt,
                    accentColor: color,
                    balanceColor: balanceColor,
                    deltaColor: deltaColor,
                  ),
                  const SizedBox(height: 12),
                  _AccountOperationsRail(
                    account: account,
                    canSort: canSort,
                    isDebt: isDebt,
                    accentColor: color,
                  ),
                  if (isDebt || account.remark.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (isDebt && account.paymentDay != null)
                          _AccountInfoChip(
                            icon: Icons.event_available_outlined,
                            label: '还款日 ${account.paymentDay} 日',
                          ),
                        if (isDebt && account.interestRate != null)
                          _AccountInfoChip(
                            icon: Icons.percent_outlined,
                            label: '年利率 ${account.interestRate}%',
                          ),
                        if (account.remark.isNotEmpty)
                          _AccountInfoChip(
                            icon: Icons.notes_outlined,
                            label: account.remark,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 处理账户列表项操作。
  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _AccountAction action,
  ) async {
    switch (action) {
      case _AccountAction.logs:
        context.push(
          '${AppRoutePaths.accountLogs}/${account.id}',
          extra: AccountLogPageAccount(account),
        );
      case _AccountAction.edit:
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (context) => _AccountFormSheet(account: account),
        );
      case _AccountAction.moveUp:
        await _moveAccount(context, ref, -1);
      case _AccountAction.moveDown:
        await _moveAccount(context, ref, 1);
      case _AccountAction.archive:
        await ref.read(accountListControllerProvider.notifier).archive(account);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(account.isArchived ? '已恢复账户' : '已归档账户')),
          );
        }
      case _AccountAction.delete:
        final confirmed = await showAppConfirmDialog(
          context: context,
          title: '确认删除',
          message: '余额不为零或已有交易记录的账户无法删除，可选择归档。',
          confirmText: '删除',
          isDanger: true,
        );
        if (!confirmed) {
          return;
        }
        try {
          await ref
              .read(accountListControllerProvider.notifier)
              .delete(account.id);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('删除成功')));
          }
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }
    }
  }

  Future<void> _moveAccount(
    BuildContext context,
    WidgetRef ref,
    int offset,
  ) async {
    final fromIndex = sectionAccountIds.indexOf(account.id);
    final toIndex = fromIndex + offset;
    if (fromIndex < 0 || toIndex < 0 || toIndex >= sectionAccountIds.length) {
      return;
    }

    final reorderedIds = [...sectionAccountIds];
    final id = reorderedIds.removeAt(fromIndex);
    reorderedIds.insert(toIndex, id);

    try {
      await ref
          .read(accountListControllerProvider.notifier)
          .updateSort(reorderedIds);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('账户排序已更新')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('排序失败：$error')));
      }
    }
  }
}

class _AccountOperationsRail extends StatelessWidget {
  const _AccountOperationsRail({
    required this.account,
    required this.canSort,
    required this.isDebt,
    required this.accentColor,
  });

  final Account account;
  final bool canSort;
  final bool isDebt;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final stateColor = account.isArchived
        ? colorScheme.outline
        : isDebt
        ? financeColors.expense
        : financeColors.income;
    return Container(
      key: ValueKey('account-operations-rail-${account.id}'),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.10
                : 0.045,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 17, color: accentColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '账户操作轨道',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _AccountRailPill(
                label: account.isArchived ? '归档态' : '可管理',
                color: stateColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AccountOperationTile(
                  icon: Icons.receipt_long_outlined,
                  label: '流水入口',
                  value: '一键追踪',
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AccountOperationTile(
                  icon: Icons.tune_outlined,
                  label: '账户参数',
                  value: '可编辑',
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AccountOperationTile(
                  icon: canSort
                      ? Icons.swap_vert_rounded
                      : Icons.lock_outline_rounded,
                  label: canSort ? '排序轨道' : '排序状态',
                  value: canSort ? '支持排序' : '锁定',
                  color: canSort ? financeColors.asset : colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountOperationTile extends StatelessWidget {
  const _AccountOperationTile({
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
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.15
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
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

class _AccountRailPill extends StatelessWidget {
  const _AccountRailPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.11),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AccountBalanceSignal extends StatelessWidget {
  const _AccountBalanceSignal({
    required this.account,
    required this.isDebt,
    required this.accentColor,
    required this.balanceColor,
    required this.deltaColor,
  });

  final Account account;
  final bool isDebt;
  final Color accentColor;
  final Color balanceColor;
  final Color deltaColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseline = account.initialBalance.abs();
    final current = account.currentBalance.abs();
    final progress = baseline <= 0 ? 1.0 : (current / baseline).clamp(0.0, 1.0);
    final delta = account.currentBalance - account.initialBalance;
    final deltaLabel = delta == 0
        ? '无变化'
        : '${delta > 0 ? '+' : ''}${_formatMoney(delta)}';
    final postureLabel = isDebt
        ? '负债追踪'
        : delta > 0
        ? '资产增值'
        : delta < 0
        ? '资产回落'
        : '资产稳定';
    final postureColor = isDebt ? balanceColor : deltaColor;
    return AnimatedContainer(
      key: ValueKey('account-balance-matrix-${account.id}'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accentColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 17, color: accentColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '账户态势',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _AccountRailPill(label: postureLabel, color: postureColor),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _AccountSignalMetric(
                icon: isDebt ? Icons.route_outlined : Icons.monitor_heart,
                label: isDebt ? '偿还进度' : '资产轨道',
                value: isDebt
                    ? '${(progress * 100).toStringAsFixed(0)}%'
                    : _formatMoney(account.initialBalance),
                color: accentColor,
              ),
              const SizedBox(width: 8),
              _AccountSignalMetric(
                icon: delta >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                label: '期初对比',
                value: deltaLabel,
                color: deltaColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: ColoredBox(color: balanceColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSignalMetric extends StatelessWidget {
  const _AccountSignalMetric({
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
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
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
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
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

class _AccountFormSheet extends ConsumerStatefulWidget {
  const _AccountFormSheet({this.account});

  final Account? account;

  @override
  ConsumerState<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends ConsumerState<_AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late final TextEditingController _paymentDayController;
  late final TextEditingController _billingDayController;
  late final TextEditingController _creditLimitController;
  late final TextEditingController _interestRateController;
  late final TextEditingController _startDateController;
  late final TextEditingController _targetDateController;
  late final TextEditingController _remarkController;
  late String _type;
  late String _icon;
  late String _color;
  bool _submitting = false;

  /// 初始化账户表单状态。
  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _nameController = TextEditingController(text: account?.name ?? '');
    _balanceController = TextEditingController(
      text: account == null ? '0' : account.initialBalance.toStringAsFixed(2),
    );
    _paymentDayController = TextEditingController(
      text: account?.paymentDay?.toString() ?? '',
    );
    _billingDayController = TextEditingController(
      text: account?.billingDay?.toString() ?? '',
    );
    _creditLimitController = TextEditingController(
      text: _formatOptionalNumber(account?.creditLimit),
    );
    _interestRateController = TextEditingController(
      text: _formatOptionalNumber(account?.interestRate),
    );
    _startDateController = TextEditingController(
      text: account?.startDate ?? '',
    );
    _targetDateController = TextEditingController(
      text: account?.targetDate ?? '',
    );
    _remarkController = TextEditingController(text: account?.remark ?? '');
    _type = account?.type ?? 'cash';
    _icon = account?.icon ?? '💰';
    _color = account?.color ?? _accountColors.first;
  }

  /// 释放输入框控制器。
  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _paymentDayController.dispose();
    _billingDayController.dispose();
    _creditLimitController.dispose();
    _interestRateController.dispose();
    _startDateController.dispose();
    _targetDateController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  /// 构建账户表单。
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.account != null;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _parseColor(
      _color,
      AppTheme.financeColors(context).asset,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: PremiumSurface(
          accentColor: accentColor,
          padding: EdgeInsets.zero,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Row(
                    children: [
                      IconBadge(
                        icon: _selectedFormIcon(),
                        color: accentColor,
                        size: 46,
                        iconSize: 23,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing ? '编辑账户' : '新增账户',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isEditing ? '更新账户展示、提醒和扩展信息' : '创建可用于记账和资产统计的账户',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AccountFormSection(
                          title: '基础信息',
                          icon: Icons.account_balance_wallet_outlined,
                          accentColor: accentColor,
                          child: Column(
                            children: [
                              TextFormField(
                                key: const ValueKey('account-name'),
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: '账户名称',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? '请输入账户名称'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: const ValueKey('account-type'),
                                initialValue: _type,
                                decoration: const InputDecoration(
                                  labelText: '账户类型',
                                  border: OutlineInputBorder(),
                                ),
                                items: _accountTypes
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item.value,
                                        child: Text(item.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: isEditing
                                    ? null
                                    : (value) => setState(
                                        () => _type = value ?? _type,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                key: const ValueKey('account-initial-balance'),
                                controller: _balanceController,
                                enabled: !isEditing,
                                decoration: const InputDecoration(
                                  labelText: '初始余额',
                                  prefixText: '¥ ',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^-?\d*\.?\d{0,2}'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _AccountFormSection(
                          title: '视觉标识',
                          icon: Icons.auto_awesome_outlined,
                          accentColor: accentColor,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final option in _accountIconOptions)
                                    _AccountIconChoice(
                                      option: option,
                                      selected: _icon == option.value,
                                      color: accentColor,
                                      onSelected: () =>
                                          setState(() => _icon = option.value),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final color in _accountColors)
                                    _AccountColorChoice(
                                      color: _parseColor(
                                        color,
                                        AppTheme.financeColors(context).asset,
                                      ),
                                      selected: _color == color,
                                      onSelected: () =>
                                          setState(() => _color = color),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_isDebtAccount(_type)) ...[
                          const SizedBox(height: 12),
                          _AccountDebtFields(
                            paymentDayController: _paymentDayController,
                            billingDayController: _billingDayController,
                            creditLimitController: _creditLimitController,
                            interestRateController: _interestRateController,
                            startDateController: _startDateController,
                            targetDateController: _targetDateController,
                            remarkController: _remarkController,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: FilledButton(
                    key: const ValueKey('account-save'),
                    onPressed: _submitting ? null : _submit,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_submitting ? Icons.hourglass_top : Icons.check),
                        const SizedBox(width: 8),
                        Text(_submitting ? '保存中...' : '保存'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _selectedFormIcon() {
    final normalized = (_icon.isEmpty ? _type : _icon).trim().toLowerCase();
    return switch (normalized) {
      'cash' || '现金' || '💰' => Icons.payments_outlined,
      'bank_card' ||
      'savings' ||
      '银行卡' ||
      '储蓄卡' ||
      '💳' => Icons.credit_card_outlined,
      'alipay' ||
      'wechat' ||
      'qq_pay' ||
      'jd_pay' ||
      'apple_pay' ||
      '📱' => Icons.account_balance_wallet_outlined,
      'credit' => Icons.credit_score_outlined,
      'loan' ||
      'mortgage' ||
      'car_loan' ||
      'consumer_loan' ||
      'huabei' ||
      'baitiao' ||
      '🏠' => Icons.request_quote_outlined,
      'investment' ||
      'fund' ||
      'stock' ||
      'crypto' => Icons.show_chart_outlined,
      'prepaid' => Icons.card_giftcard_outlined,
      _ => Icons.grid_view_outlined,
    };
  }

  /// 提交账户表单。
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final controller = ref.read(accountListControllerProvider.notifier);
      final account = widget.account;
      if (account == null) {
        await controller.create(
          CreateAccountRequest(
            name: _nameController.text.trim(),
            type: _type,
            icon: _icon.isEmpty ? '💰' : _icon,
            color: _color,
            initialBalance: double.tryParse(_balanceController.text) ?? 0,
            paymentDay: _debtInt(_paymentDayController),
            billingDay: _debtInt(_billingDayController),
            creditLimit: _debtDouble(_creditLimitController),
            interestRate: _debtDouble(_interestRateController),
            startDate: _debtText(_startDateController),
            targetDate: _debtText(_targetDateController),
            remark: _debtText(_remarkController) ?? '',
          ),
        );
      } else {
        await controller.update(
          account.id,
          UpdateAccountRequest(
            name: _nameController.text.trim(),
            icon: _icon.isEmpty ? '💰' : _icon,
            color: _color,
            paymentDay: _debtInt(_paymentDayController),
            billingDay: _debtInt(_billingDayController),
            creditLimit: _debtDouble(_creditLimitController),
            interestRate: _debtDouble(_interestRateController),
            startDate: _debtText(_startDateController),
            targetDate: _debtText(_targetDateController),
            remark: _debtText(_remarkController) ?? '',
          ),
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存成功')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  int? _debtInt(TextEditingController controller) {
    if (!_isDebtAccount(_type)) {
      return null;
    }
    return int.tryParse(controller.text.trim());
  }

  double? _debtDouble(TextEditingController controller) {
    if (!_isDebtAccount(_type)) {
      return null;
    }
    return double.tryParse(controller.text.trim());
  }

  String? _debtText(TextEditingController controller) {
    if (!_isDebtAccount(_type)) {
      return null;
    }
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }
}

class _AccountFormSection extends StatelessWidget {
  const _AccountFormSection({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      accentColor: accentColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accentColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AccountDebtFields extends StatelessWidget {
  const _AccountDebtFields({
    required this.paymentDayController,
    required this.billingDayController,
    required this.creditLimitController,
    required this.interestRateController,
    required this.startDateController,
    required this.targetDateController,
    required this.remarkController,
  });

  final TextEditingController paymentDayController;
  final TextEditingController billingDayController;
  final TextEditingController creditLimitController;
  final TextEditingController interestRateController;
  final TextEditingController startDateController;
  final TextEditingController targetDateController;
  final TextEditingController remarkController;

  @override
  Widget build(BuildContext context) {
    return _AccountFormSection(
      title: '负债信息',
      icon: Icons.request_quote_outlined,
      accentColor: AppTheme.financeColors(context).expense,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('account-payment-day'),
                  controller: paymentDayController,
                  decoration: const InputDecoration(
                    labelText: '还款日',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: _validateOptionalDay,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('account-billing-day'),
                  controller: billingDayController,
                  decoration: const InputDecoration(
                    labelText: '账单日',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: _validateOptionalDay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('account-credit-limit'),
                  controller: creditLimitController,
                  decoration: const InputDecoration(
                    labelText: '授信/本金',
                    prefixText: '¥ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d{0,2}')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('account-interest-rate'),
                  controller: interestRateController,
                  decoration: const InputDecoration(
                    labelText: '年利率',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'\d*\.?\d{0,4}')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('account-start-date'),
                  controller: startDateController,
                  decoration: const InputDecoration(
                    labelText: '开始日期',
                    hintText: 'YYYY-MM-DD',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                  ],
                  validator: _validateOptionalDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('account-target-date'),
                  controller: targetDateController,
                  decoration: const InputDecoration(
                    labelText: '目标结清日',
                    hintText: 'YYYY-MM-DD',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                  ],
                  validator: _validateOptionalDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('account-remark'),
            controller: remarkController,
            decoration: const InputDecoration(
              labelText: '备注',
              border: OutlineInputBorder(),
            ),
            minLines: 2,
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _AccountIconChoice extends StatelessWidget {
  const _AccountIconChoice({
    required this.option,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final _AccountIconOption option;
  final bool selected;
  final Color color;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: Icon(option.icon, size: 17, color: selected ? color : null),
      label: Text(option.label),
      labelStyle: TextStyle(
        color: selected ? color : colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected ? color.withValues(alpha: 0.42) : colorScheme.outline,
      ),
    );
  }
}

class _AccountColorChoice extends StatelessWidget {
  const _AccountColorChoice({
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final Color color;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onSelected,
      radius: 24,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : color,
            width: selected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: selected ? 0.36 : 0.16),
              blurRadius: selected ? 16 : 8,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.sortable,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool sortable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          IconBadge(
            icon: icon,
            color: colorScheme.primary,
            size: 34,
            iconSize: 18,
          ),
          const SizedBox(width: 10),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _SectionModePill(
            icon: sortable ? Icons.swap_vert_rounded : Icons.lock_outline,
            label: sortable ? '支持排序' : '归档区',
          ),
        ],
      ),
    );
  }
}

class _SectionModePill extends StatelessWidget {
  const _SectionModePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountInfoChip extends StatelessWidget {
  const _AccountInfoChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chipColor = color ?? colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          chipColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.10,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: chipColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

enum _AccountAction { logs, edit, moveUp, moveDown, archive, delete }

class _AccountTypeOption {
  const _AccountTypeOption(this.value, this.label);

  final String value;
  final String label;
}

class _AccountIconOption {
  const _AccountIconOption(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

/// 格式化金额展示。
String _formatMoney(double value) {
  return '¥${value.toStringAsFixed(2)}';
}

/// 获取账户类型中文名称。
String _accountTypeLabel(String type) {
  return _accountTypes
      .firstWhere(
        (item) => item.value == type,
        orElse: () => const _AccountTypeOption('other', '其他'),
      )
      .label;
}

/// 判断账户类型是否需要负债扩展字段。
bool _isDebtAccount(String type) {
  return _debtAccountTypes.contains(type);
}

IconData _accountIconData(Account account) {
  final normalized = (account.icon.isEmpty ? account.type : account.icon)
      .trim()
      .toLowerCase();
  return switch (normalized) {
    'cash' || '现金' || '💰' => Icons.payments_outlined,
    'bank_card' ||
    'savings' ||
    '银行卡' ||
    '储蓄卡' ||
    '💳' => Icons.credit_card_outlined,
    'alipay' ||
    'wechat' ||
    'qq_pay' ||
    'jd_pay' ||
    'apple_pay' ||
    '📱' => Icons.account_balance_wallet_outlined,
    'credit' => Icons.credit_score_outlined,
    'loan' ||
    'mortgage' ||
    'car_loan' ||
    'consumer_loan' ||
    'huabei' ||
    'baitiao' ||
    '🏠' => Icons.request_quote_outlined,
    'investment' || 'fund' || 'stock' || 'crypto' => Icons.show_chart_outlined,
    'prepaid' => Icons.card_giftcard_outlined,
    _ => Icons.account_balance_wallet_outlined,
  };
}

/// 格式化可选数字，避免输入框出现多余的 0。
String _formatOptionalNumber(double? value) {
  if (value == null) {
    return '';
  }
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toString();
}

String? _validateOptionalDay(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  final day = int.tryParse(text);
  if (day == null || day < 1 || day > 31) {
    return '请输入 1-31';
  }
  return null;
}

String? _validateOptionalDate(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  final parts = text.split('-');
  if (parts.length != 3 ||
      parts[0].length != 4 ||
      parts[1].length != 2 ||
      parts[2].length != 2 ||
      DateTime.tryParse(text) == null) {
    return '格式为 YYYY-MM-DD';
  }
  return null;
}

/// 解析十六进制颜色。
Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
