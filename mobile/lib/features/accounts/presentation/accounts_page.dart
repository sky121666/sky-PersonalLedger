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
            tooltip: '刷新',
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
          const SizedBox(height: 16),
          _AccountSection(
            title: '正常账户',
            accounts: activeAccounts,
            sortable: true,
            startIndex: 1,
          ),
          if (archivedAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AccountSection(
              title: '已归档账户',
              accounts: archivedAccounts,
              startIndex: activeAccounts.length + 2,
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
    final activeCount = result.accounts
        .where((item) => !item.isArchived)
        .length;
    return FinanceHeroCard(
      label: '资产概览',
      amount: result.netAssets,
      accentColor: financeColors.asset,
      semanticLabel: '净资产 ${_formatMoney(result.netAssets)}',
      metrics: [
        FinanceMetricData(
          label: '总资产',
          value: _formatMoney(result.totalAssets),
          icon: Icons.trending_up,
          color: financeColors.income,
        ),
        FinanceMetricData(
          label: '总负债',
          value: _formatMoney(result.totalLiabilities),
          icon: Icons.trending_down,
          color: financeColors.expense,
        ),
        FinanceMetricData(
          label: '活跃账户',
          value: '$activeCount 个',
          icon: Icons.account_balance_wallet_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        FinanceMetricData(
          label: '全部账户',
          value: '${result.accounts.length} 个',
          icon: Icons.grid_view_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      ],
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
    return PremiumSurface(
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
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
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
                          const SizedBox(height: 3),
                          Text(
                            _accountTypeLabel(account.type),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _formatMoney(account.currentBalance),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: balanceColor,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    PopupMenuButton<_AccountAction>(
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
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBadge(
          icon: icon,
          color: Theme.of(context).colorScheme.primary,
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.outline),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
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
