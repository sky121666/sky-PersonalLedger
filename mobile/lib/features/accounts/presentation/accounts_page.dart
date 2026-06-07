import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
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
            key: const ValueKey('account-add'),
            onPressed: () => _openAccountForm(context, ref),
            tooltip: null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: AdaptivePageContainer(
        child: state.when(
          data: (result) => _AccountContent(result: result),
          loading: () => const AppLoadingView(message: '账户加载中...'),
          error: (error, _) => AppErrorView(
            message: '账户加载失败',
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

class _AccountContent extends ConsumerStatefulWidget {
  const _AccountContent({required this.result});

  final AccountListResult result;

  @override
  ConsumerState<_AccountContent> createState() => _AccountContentState();
}

class _AccountContentState extends ConsumerState<_AccountContent> {
  bool _showArchivedAccounts = false;

  /// 构建账户汇总和列表内容。
  @override
  Widget build(BuildContext context) {
    final result = widget.result;

    if (result.accounts.isEmpty) {
      return const _AccountsEmptyState(
        title: '还没有账户',
        message: '右上角添加',
        icon: Icons.account_balance_wallet_outlined,
      );
    }

    final activeAccounts = result.accounts
        .where((item) => !item.isArchived)
        .toList();
    final archivedAccounts = result.accounts
        .where((item) => item.isArchived)
        .toList();
    final accountIds = archivedAccounts.map((item) => item.id).toList();

    final rows = <Widget>[
      _SectionHeader(
        title: '正常账户',
        subtitle: '${activeAccounts.length} 个账户',
        icon: Icons.account_balance_wallet_outlined,
      ),
      const SizedBox(height: 8),
      for (final entry in activeAccounts.indexed)
        _AccountListTile(
          account: entry.$2,
          sectionAccountIds: activeAccounts.map((item) => item.id).toList(),
          accountIndex: entry.$1,
          canSort: true,
        ),
    ];

    if (archivedAccounts.isNotEmpty) {
      rows.add(const SizedBox(height: 16));
      rows.add(
        _SectionHeaderWithAction(
          title: '已归档账户',
          subtitle: '${archivedAccounts.length} 个账户',
          icon: Icons.archive_outlined,
          isExpanded: _showArchivedAccounts,
          onTap: () =>
              setState(() => _showArchivedAccounts = !_showArchivedAccounts),
        ),
      );
      if (_showArchivedAccounts) {
        rows
          ..add(const SizedBox(height: 8))
          ..addAll(
            archivedAccounts.indexed.map(
              (entry) => _AccountListTile(
                account: entry.$2,
                sectionAccountIds: accountIds,
                accountIndex: entry.$1,
                canSort: false,
              ),
            ),
          );
      }
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(accountListControllerProvider.notifier).load(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: rows.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _AccountSummaryCard(result: result);
          }
          if (index == 1) {
            return const SizedBox(height: 16);
          }
          return rows[index - 2];
        },
      ),
    );
  }
}

class _AccountsEmptyState extends StatelessWidget {
  const _AccountsEmptyState({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.square(
                dimension: 34,
                child: Icon(icon, size: 18, color: colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 11, 14, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
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

class _SectionHeaderWithAction extends StatelessWidget {
  const _SectionHeaderWithAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isExpanded,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
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
            const SizedBox(width: 10),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            ),
            const SizedBox(width: 6),
            Icon(
              icon,
              size: 18,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ],
        ),
      ),
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
    return Semantics(
      label: '净资产 ${_formatMoney(result.netAssets)}',
      child: PremiumSurface(
        accentColor: financeColors.asset,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '净资产',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatMoney(result.netAssets),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 10),
            _AccountSummaryLine(
              label: '总资产',
              value: _formatMoney(result.totalAssets),
              color: financeColors.income,
            ),
            const SizedBox(height: 6),
            _AccountSummaryLine(
              label: '总负债',
              value: _formatMoney(result.totalLiabilities),
              color: financeColors.expense,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSummaryLine extends StatelessWidget {
  const _AccountSummaryLine({
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
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountLeadingIcon extends StatelessWidget {
  const _AccountLeadingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.1), surface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}

class _AccountActionTextButton extends StatelessWidget {
  const _AccountActionTextButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: buttonKey,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

class _AccountListTile extends ConsumerStatefulWidget {
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
  ConsumerState<_AccountListTile> createState() => _AccountListTileState();
}

class _AccountListTileState extends ConsumerState<_AccountListTile> {
  bool _expanded = false;

  Account get account => widget.account;
  List<String> get sectionAccountIds => widget.sectionAccountIds;
  int get accountIndex => widget.accountIndex;
  bool get canSort => widget.canSort;

  @override
  Widget build(BuildContext context) {
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
            borderRadius: BorderRadius.circular(16),
            onTap: () => _handleAction(context, ref, _AccountAction.logs),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AccountLeadingIcon(
                        icon: _accountIconData(account),
                        color: color,
                      ),
                      const SizedBox(width: 10),
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
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              account.isArchived
                                  ? '${_accountTypeLabel(account.type)} · 已归档'
                                  : _accountTypeLabel(account.type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
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
                        ],
                      ),
                      IconButton(
                        key: ValueKey('account-toggle-details-${account.id}'),
                        tooltip: null,
                        onPressed: () => setState(() {
                          _expanded = !_expanded;
                        }),
                        icon: Icon(_expanded ? Icons.remove : Icons.add),
                        iconSize: 19,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 10),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.52),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: [
                          _AccountActionTextButton(
                            buttonKey: ValueKey(
                              'account-action-logs-${account.id}',
                            ),
                            onPressed: () => _handleAction(
                              context,
                              ref,
                              _AccountAction.logs,
                            ),
                            label: '流水',
                          ),
                          _AccountActionTextButton(
                            buttonKey: ValueKey(
                              'account-action-edit-${account.id}',
                            ),
                            onPressed: () => _handleAction(
                              context,
                              ref,
                              _AccountAction.edit,
                            ),
                            label: '编辑',
                          ),
                          if (canSort)
                            _AccountActionTextButton(
                              buttonKey: ValueKey(
                                'account-action-move-up-${account.id}',
                              ),
                              onPressed: accountIndex > 0
                                  ? () => _handleAction(
                                      context,
                                      ref,
                                      _AccountAction.moveUp,
                                    )
                                  : null,
                              label: '上移',
                            ),
                          if (canSort)
                            _AccountActionTextButton(
                              buttonKey: ValueKey(
                                'account-action-move-down-${account.id}',
                              ),
                              onPressed:
                                  accountIndex < sectionAccountIds.length - 1
                                  ? () => _handleAction(
                                      context,
                                      ref,
                                      _AccountAction.moveDown,
                                    )
                                  : null,
                              label: '下移',
                            ),
                          _AccountActionTextButton(
                            buttonKey: ValueKey(
                              'account-action-archive-${account.id}',
                            ),
                            onPressed: () => _handleAction(
                              context,
                              ref,
                              _AccountAction.archive,
                            ),
                            label: account.isArchived ? '恢复' : '归档',
                          ),
                          _AccountActionTextButton(
                            buttonKey: ValueKey(
                              'account-action-delete-${account.id}',
                            ),
                            onPressed: () => _handleAction(
                              context,
                              ref,
                              _AccountAction.delete,
                            ),
                            label: '删除',
                          ),
                        ],
                      ),
                    ),
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
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          await context.push(
            '${AppRoutePaths.accountLogs}/${account.id}',
            extra: AccountLogPageAccount(account),
          );
          return;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请在主应用中打开流水详情。')));
        }
        return;
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
          title: '删除账户',
          message: '删除「${account.name}」？',
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
            ).showSnackBar(const SnackBar(content: Text('账户删除失败')));
          }
        }
    }
  }

  Future<void> _moveAccount(
    BuildContext context,
    WidgetRef ref,
    int offset,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
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
      if (messenger != null) {
        messenger.showSnackBar(const SnackBar(content: Text('账户排序已更新')));
      }
    } catch (error) {
      if (messenger != null) {
        messenger.showSnackBar(const SnackBar(content: Text('账户排序失败')));
      }
    }
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
  bool _showVisualOptions = false;
  bool _showDebtOptions = false;

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
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isEditing ? '编辑账户' : '新增账户',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: null,
                        icon: const Icon(Icons.close),
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
                        const SizedBox(height: 8),
                        _VisualOptionsToggle(
                          expanded: _showVisualOptions,
                          color: accentColor,
                          onPressed: () => setState(() {
                            _showVisualOptions = !_showVisualOptions;
                          }),
                        ),
                        if (_showVisualOptions) ...[
                          const SizedBox(height: 10),
                          _AccountFormSection(
                            title: '外观',
                            icon: Icons.tune_outlined,
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
                                        onSelected: () => setState(
                                          () => _icon = option.value,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
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
                        ],
                        if (_isDebtAccount(_type)) ...[
                          const SizedBox(height: 12),
                          IconButton(
                            key: const ValueKey('account-debt-options-toggle'),
                            onPressed: () => setState(() {
                              _showDebtOptions = !_showDebtOptions;
                            }),
                            tooltip: null,
                            icon: Icon(
                              _showDebtOptions ? Icons.remove : Icons.add,
                            ),
                          ),
                          if (_showDebtOptions)
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
                        Text(_submitting ? '保存中' : '保存账户'),
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
        ).showSnackBar(const SnackBar(content: Text('账户保存失败')));
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

class _VisualOptionsToggle extends StatelessWidget {
  const _VisualOptionsToggle({
    required this.expanded,
    required this.color,
    required this.onPressed,
  });

  final bool expanded;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('account-style-toggle'),
      onPressed: onPressed,
      tooltip: null,
      icon: Icon(expanded ? Icons.remove_rounded : Icons.add_rounded, size: 18),
      color: color,
      style: IconButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainer,
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
                    labelText: '额度/本金',
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
                    hintText: '2026-05-01',
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
                    hintText: '2026-12-31',
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
      avatar: IconBadge(
        icon: option.icon,
        color: selected ? color : colorScheme.outline,
        size: 24,
        iconSize: 14,
      ),
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
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : color,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        children: [
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
          const SizedBox(width: 10),
          Icon(
            icon,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          ),
        ],
      ),
    );
  }
}

class _AccountInfoChip extends StatelessWidget {
  const _AccountInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chipColor = colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          chipColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.12
                : 0.06,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipColor.withValues(alpha: 0.1)),
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
    return '请输入有效日期';
  }
  return null;
}

/// 解析十六进制颜色。
Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
