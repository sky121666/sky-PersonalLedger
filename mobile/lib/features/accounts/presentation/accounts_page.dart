import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/ledger_icon.dart';
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
      return AppEmptyView(
        title: '暂无账户',
        message: '添加现金、银行卡或支付账户后即可开始记账。',
        icon: Icons.account_balance_wallet_outlined,
        action: FilledButton.icon(
          onPressed: () => _openAccountForm(context),
          icon: const Icon(Icons.add),
          label: const Text('新增账户'),
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
          _AccountSummaryCard(result: result),
          const SizedBox(height: 16),
          _AccountSection(
            title: '正常账户',
            accounts: activeAccounts,
            sortable: true,
          ),
          if (archivedAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AccountSection(title: '已归档账户', accounts: archivedAccounts),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('资产概览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(
              _formatMoney(result.netAssets),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: '总资产',
                    value: _formatMoney(result.totalAssets),
                  ),
                ),
                Expanded(
                  child: _SummaryItem(
                    label: '总负债',
                    value: _formatMoney(result.totalLiabilities),
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

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.title,
    required this.accounts,
    this.sortable = false,
  });

  final String title;
  final List<Account> accounts;
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final entry in accounts.indexed)
                _AccountListTile(
                  account: entry.$2,
                  sectionAccountIds: accountIds,
                  accountIndex: entry.$1,
                  canSort: sortable,
                ),
            ],
          ),
        ),
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
    final color = _parseColor(
      account.color,
      Theme.of(context).colorScheme.primary,
    );
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: LedgerIcon(
          icon: account.icon.isEmpty ? account.type : account.icon,
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(account.name)),
          if (account.isArchived)
            const Chip(
              label: Text('已归档'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      subtitle: Text(_accountTypeLabel(account.type)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_formatMoney(account.currentBalance)),
          PopupMenuButton<_AccountAction>(
            onSelected: (action) => _handleAction(context, ref, action),
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
                  enabled: accountIndex < sectionAccountIds.length - 1,
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEditing ? '编辑账户' : '新增账户',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('account-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '账户名称',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入账户名称' : null,
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
                    : (value) => setState(() => _type = value ?? _type),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^-?\d*\.?\d{0,2}'),
                  ),
                ],
              ),
              if (_isDebtAccount(_type)) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '负债信息',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('account-payment-day'),
                        controller: _paymentDayController,
                        decoration: const InputDecoration(
                          labelText: '还款日',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: _validateOptionalDay,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('account-billing-day'),
                        controller: _billingDayController,
                        decoration: const InputDecoration(
                          labelText: '账单日',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
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
                        controller: _creditLimitController,
                        decoration: const InputDecoration(
                          labelText: '授信/本金',
                          prefixText: '¥ ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'\d*\.?\d{0,2}'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('account-interest-rate'),
                        controller: _interestRateController,
                        decoration: const InputDecoration(
                          labelText: '年利率',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'\d*\.?\d{0,4}'),
                          ),
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
                        controller: _startDateController,
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
                        controller: _targetDateController,
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
                  controller: _remarkController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 3,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _icon,
                decoration: const InputDecoration(
                  labelText: '图标',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _icon = value.trim(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in _accountColors)
                    ChoiceChip(
                      label: const SizedBox(width: 16, height: 16),
                      selected: _color == color,
                      backgroundColor: _parseColor(color, Colors.blue),
                      selectedColor: _parseColor(color, Colors.blue),
                      onSelected: (_) => setState(() => _color = color),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('account-save'),
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '保存中...' : '保存'),
              ),
            ],
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

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  /// 构建汇总字段。
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

enum _AccountAction { logs, edit, moveUp, moveDown, archive, delete }

class _AccountTypeOption {
  const _AccountTypeOption(this.value, this.label);

  final String value;
  final String label;
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
