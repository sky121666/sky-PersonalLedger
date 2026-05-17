import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../accounts/data/account.dart';
import '../data/lending_repository.dart';

class LendingPage extends ConsumerStatefulWidget {
  const LendingPage({super.key});

  @override
  ConsumerState<LendingPage> createState() => _LendingPageState();
}

class _LendingPageState extends ConsumerState<LendingPage> {
  _LendingTab _tab = _LendingTab.lendOut;
  String? _busyAction;
  String? _errorMessage;

  bool get _isBusy => _busyAction != null;

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(lendingDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('借贷往来'),
        actions: [
          IconButton(
            onPressed: _isBusy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: dashboardState.when(
        loading: () => const AppLoadingView(message: '正在加载借贷记录...'),
        error: (error, _) =>
            AppErrorView(message: error.toString(), onRetry: _refresh),
        data: (dashboard) => AdaptivePageContainer(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 12),
                ],
                _SummarySection(summary: dashboard.summary),
                const SizedBox(height: 16),
                _QuickActions(
                  busy: _isBusy,
                  onCreate: (type) => _openCreateForm(type, dashboard.accounts),
                ),
                const SizedBox(height: 16),
                SegmentedButton<_LendingTab>(
                  segments: const [
                    ButtonSegment(
                      value: _LendingTab.lendOut,
                      icon: Icon(Icons.north_east),
                      label: Text('借出'),
                    ),
                    ButtonSegment(
                      value: _LendingTab.borrowIn,
                      icon: Icon(Icons.south_west),
                      label: Text('借入'),
                    ),
                    ButtonSegment(
                      value: _LendingTab.settled,
                      icon: Icon(Icons.check_circle_outline),
                      label: Text('结清'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: _isBusy
                      ? null
                      : (value) => setState(() => _tab = value.single),
                ),
                const SizedBox(height: 12),
                _LendingList(
                  lendings: _itemsForTab(dashboard),
                  tab: _tab,
                  busyAction: _busyAction,
                  onEdit: (item) => _openEditForm(item, dashboard.accounts),
                  onDelete: _deleteLending,
                  onRepay: (item) =>
                      _openRepaymentDialog(item, dashboard.activeAccounts),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<LendingItem> _itemsForTab(LendingDashboard dashboard) {
    return switch (_tab) {
      _LendingTab.lendOut => dashboard.activeLendOut,
      _LendingTab.borrowIn => dashboard.activeBorrowIn,
      _LendingTab.settled => dashboard.settled,
    };
  }

  void _refresh() {
    setState(() => _errorMessage = null);
    ref.invalidate(lendingDashboardProvider);
  }

  Future<void> _openCreateForm(LendingType type, List<Account> accounts) async {
    final request = await showDialog<CreateLendingRequest>(
      context: context,
      builder: (context) => _LendingFormDialog(type: type, accounts: accounts),
    );
    if (request == null || !mounted) {
      return;
    }

    await _runAction(
      action: 'create',
      successMessage: request.type == LendingType.lendOut
          ? '借出记录已创建'
          : '借入记录已创建',
      request: () =>
          ref.read(lendingRepositoryProvider).create(request).then((_) {}),
    );
  }

  Future<void> _openEditForm(LendingItem item, List<Account> accounts) async {
    final request = await showDialog<UpdateLendingRequest>(
      context: context,
      builder: (context) => _LendingFormDialog(
        type: item.type,
        accounts: accounts,
        editingItem: item,
      ),
    );
    if (request == null || !mounted) {
      return;
    }

    await _runAction(
      action: 'edit-${item.id}',
      successMessage: '借贷记录已更新',
      request: () => ref
          .read(lendingRepositoryProvider)
          .update(item.id, request)
          .then((_) {}),
    );
  }

  Future<void> _openRepaymentDialog(
    LendingItem item,
    List<Account> accounts,
  ) async {
    final request = await showDialog<RecordRepaymentRequest>(
      context: context,
      builder: (context) => _RepaymentDialog(item: item, accounts: accounts),
    );
    if (request == null || !mounted) {
      return;
    }

    await _runAction(
      action: 'repay-${item.id}',
      successMessage: '还款已记录',
      request: () => ref
          .read(lendingRepositoryProvider)
          .recordRepayment(item.id, request)
          .then((_) {}),
    );
  }

  Future<void> _deleteLending(LendingItem item) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除借贷记录',
      message: '删除后该笔借贷和还款记录将无法恢复。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    await _runAction(
      action: 'delete-${item.id}',
      successMessage: '借贷记录已删除',
      request: () => ref.read(lendingRepositoryProvider).delete(item.id),
    );
  }

  Future<void> _runAction({
    required String action,
    required String successMessage,
    required Future<void> Function() request,
  }) async {
    setState(() {
      _busyAction = action;
      _errorMessage = null;
    });

    try {
      await request();
      if (!mounted) {
        return;
      }
      ref.invalidate(lendingDashboardProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }
}

enum _LendingTab { lendOut, borrowIn, settled }

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary});

  final LendingSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.north_east,
                label: '应收',
                value: _formatMoney(summary.totalReceivable),
                caption: '${summary.activeLendOut} 笔进行中',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.south_west,
                label: '应付',
                value: _formatMoney(summary.totalPayable),
                caption: '${summary.activeBorrowIn} 笔进行中',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('净借贷影响'),
            trailing: Text(
              _formatSignedMoney(summary.netLending),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: summary.netLending >= 0
                    ? Colors.teal.shade700
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.busy, required this.onCreate});

  final bool busy;
  final ValueChanged<LendingType> onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('lending-add-lend-out'),
            onPressed: busy ? null : () => onCreate(LendingType.lendOut),
            icon: const Icon(Icons.north_east),
            label: const Text('记一笔借出'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            key: const ValueKey('lending-add-borrow-in'),
            onPressed: busy ? null : () => onCreate(LendingType.borrowIn),
            icon: const Icon(Icons.south_west),
            label: const Text('记一笔借入'),
          ),
        ),
      ],
    );
  }
}

class _LendingList extends StatelessWidget {
  const _LendingList({
    required this.lendings,
    required this.tab,
    required this.busyAction,
    required this.onEdit,
    required this.onDelete,
    required this.onRepay,
  });

  final List<LendingItem> lendings;
  final _LendingTab tab;
  final String? busyAction;
  final ValueChanged<LendingItem> onEdit;
  final ValueChanged<LendingItem> onDelete;
  final ValueChanged<LendingItem> onRepay;

  @override
  Widget build(BuildContext context) {
    if (lendings.isEmpty) {
      return AppEmptyView(
        title: switch (tab) {
          _LendingTab.lendOut => '暂无借出记录',
          _LendingTab.borrowIn => '暂无借入记录',
          _LendingTab.settled => '暂无已结清记录',
        },
        message: '可以先从上方按钮新增一笔借贷往来。',
        icon: Icons.handshake_outlined,
      );
    }

    return Column(
      children: [
        for (final item in lendings) ...[
          _LendingCard(
            item: item,
            busy: busyAction?.endsWith(item.id) ?? false,
            onEdit: () => onEdit(item),
            onDelete: () => onDelete(item),
            onRepay: () => onRepay(item),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _LendingCard extends StatelessWidget {
  const _LendingCard({
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onRepay,
  });

  final LendingItem item;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRepay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.type == LendingType.lendOut
        ? Colors.teal.shade700
        : Colors.indigo.shade600;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: accent.withValues(alpha: 0.12),
                  foregroundColor: accent,
                  child: Text(_avatarText(item.contactName)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.contactName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.typeLabel} · ${_formatDate(item.lendDate)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!item.isSettled)
                        IconButton(
                          onPressed: onRepay,
                          icon: const Icon(Icons.payments_outlined),
                          tooltip: '记录还款',
                        ),
                      IconButton(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑借贷记录',
                      ),
                      IconButton(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除借贷记录',
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoChip(
                    label: item.typeLabel,
                    value: _formatMoney(item.principal),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoChip(
                    label: '剩余',
                    value: _formatMoney(item.currentBalance),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoChip(
                    label: '已还',
                    value: _formatMoney(item.totalRepaid),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: item.progress / 100),
            const SizedBox(height: 8),
            Text(
              '剩余 ${_formatMoney(item.currentBalance)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (item.dueDate != null || item.accountName != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (item.dueDate != null) '到期 ${_formatDate(item.dueDate!)}',
                  if (item.accountName != null) '账户 ${item.accountName}',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (item.remark.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.remark, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LendingFormDialog extends StatefulWidget {
  const _LendingFormDialog({
    required this.type,
    required this.accounts,
    this.editingItem,
  });

  final LendingType type;
  final List<Account> accounts;
  final LendingItem? editingItem;

  @override
  State<_LendingFormDialog> createState() => _LendingFormDialogState();
}

class _LendingFormDialogState extends State<_LendingFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _contactController;
  late final TextEditingController _principalController;
  late final TextEditingController _phoneController;
  late final TextEditingController _interestRateController;
  late final TextEditingController _remarkController;
  late DateTime _lendDate;
  DateTime? _dueDate;
  String? _accountId;
  bool _createTransaction = false;

  bool get _isEditing => widget.editingItem != null;

  @override
  void initState() {
    super.initState();
    final item = widget.editingItem;
    _contactController = TextEditingController(text: item?.contactName ?? '');
    _principalController = TextEditingController(
      text: item == null ? '' : _formatPlainNumber(item.principal),
    );
    _phoneController = TextEditingController(text: item?.contactPhone ?? '');
    _interestRateController = TextEditingController(
      text: item?.interestRate == null
          ? ''
          : _formatPlainNumber(item!.interestRate!),
    );
    _remarkController = TextEditingController(text: item?.remark ?? '');
    _lendDate = item?.lendDate ?? DateTime.now();
    _dueDate = item?.dueDate;
    _accountId = item?.accountId;
  }

  @override
  void dispose() {
    _contactController.dispose();
    _principalController.dispose();
    _phoneController.dispose();
    _interestRateController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing
        ? '编辑借贷记录'
        : widget.type == LendingType.lendOut
        ? '记一笔借出'
        : '记一笔借入';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('lending-contact-name'),
                  controller: _contactController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: widget.type == LendingType.lendOut
                        ? '借款人'
                        : '债权人',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写联系人' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('lending-principal'),
                  controller: _principalController,
                  enabled: !_isEditing,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '本金',
                    prefixIcon: Icon(Icons.payments_outlined),
                    prefixText: '¥ ',
                  ),
                  validator: (value) =>
                      _parseAmount(value) <= 0 ? '请输入大于 0 的金额' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '联系电话',
                    prefixIcon: Icon(Icons.call_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _interestRateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '利率',
                    prefixIcon: Icon(Icons.percent),
                    suffixText: '%',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('发生日期'),
                  subtitle: Text(_formatDate(_lendDate)),
                  enabled: !_isEditing,
                  onTap: _isEditing ? null : () => _pickLendDate(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('到期日期'),
                  subtitle: Text(
                    _dueDate == null ? '未设置' : _formatDate(_dueDate!),
                  ),
                  trailing: _dueDate == null
                      ? null
                      : IconButton(
                          onPressed: () => setState(() => _dueDate = null),
                          icon: const Icon(Icons.clear),
                          tooltip: '清除到期日期',
                        ),
                  onTap: () => _pickDueDate(context),
                ),
                if (!_isEditing && widget.accounts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(
                      labelText: '关联账户',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('不关联')),
                      for (final account in widget.accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _accountId = value;
                        _createTransaction = value != null;
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同步更新账户余额'),
                    subtitle: Text(
                      widget.type == LendingType.lendOut
                          ? '从关联账户扣除借出金额'
                          : '向关联账户增加借入金额',
                    ),
                    value: _accountId != null && _createTransaction,
                    onChanged: _accountId == null
                        ? null
                        : (value) => setState(() => _createTransaction = value),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarkController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  Future<void> _pickLendDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _lendDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _lendDate = picked);
  }

  Future<void> _pickDueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _dueDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final contactName = _contactController.text.trim();
    final interestRate = _parseNullableAmount(_interestRateController.text);
    final dueDate = _dueDate == null ? null : _formatRequestDateTime(_dueDate!);

    if (_isEditing) {
      Navigator.of(context).pop(
        UpdateLendingRequest(
          contactName: contactName,
          contactPhone: _phoneController.text.trim(),
          interestRate: interestRate,
          dueDate: dueDate,
          remark: _remarkController.text.trim(),
          evidence: widget.editingItem?.evidence ?? '',
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      CreateLendingRequest(
        type: widget.type,
        contactName: contactName,
        contactPhone: _phoneController.text.trim(),
        principal: _parseAmount(_principalController.text),
        interestRate: interestRate,
        lendDate: _formatRequestDateTime(_lendDate),
        dueDate: dueDate,
        accountId: _accountId,
        remark: _remarkController.text.trim(),
        createTransaction: _accountId != null && _createTransaction,
      ),
    );
  }
}

class _RepaymentDialog extends StatefulWidget {
  const _RepaymentDialog({required this.item, required this.accounts});

  final LendingItem item;
  final List<Account> accounts;

  @override
  State<_RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends State<_RepaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _remarkController;
  DateTime _recordDate = DateTime.now();
  String? _accountId;
  bool _createTransaction = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _formatPlainNumber(widget.item.currentBalance),
    );
    _remarkController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('记录还款'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(widget.item.contactName),
                  subtitle: Text(
                    '剩余 ${_formatMoney(widget.item.currentBalance)}',
                  ),
                ),
                TextFormField(
                  key: const ValueKey('lending-repayment-amount'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '还款金额',
                    prefixIcon: Icon(Icons.payments_outlined),
                    prefixText: '¥ ',
                  ),
                  validator: (value) =>
                      _parseAmount(value) <= 0 ? '请输入大于 0 的还款金额' : null,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('还款日期'),
                  subtitle: Text(_formatDate(_recordDate)),
                  onTap: () => _pickRecordDate(context),
                ),
                if (widget.accounts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(
                      labelText: '关联账户',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('不关联')),
                      for (final account in widget.accounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _accountId = value;
                        _createTransaction = value != null;
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同步更新账户余额'),
                    subtitle: Text(
                      widget.item.type == LendingType.lendOut
                          ? '向关联账户增加还款金额'
                          : '从关联账户扣除还款金额',
                    ),
                    value: _accountId != null && _createTransaction,
                    onChanged: _accountId == null
                        ? null
                        : (value) => setState(() => _createTransaction = value),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarkController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确认还款')),
      ],
    );
  }

  Future<void> _pickRecordDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _recordDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      RecordRepaymentRequest(
        amount: _parseAmount(_amountController.text),
        recordDate: _formatRequestDateTime(_recordDate),
        accountId: _accountId,
        remark: _remarkController.text.trim(),
        createTransaction: _accountId != null && _createTransaction,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _avatarText(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '?';
  }
  return text.characters.first;
}

String _formatMoney(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final buffer = StringBuffer();
  for (var index = 0; index < parts.first.length; index++) {
    if (index > 0 && (parts.first.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(parts.first[index]);
  }
  return '¥${buffer.toString()}.${parts.last}';
}

String _formatSignedMoney(double value) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${_formatMoney(value)}';
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}/${two(value.month)}/${two(value.day)}';
}

String _formatRequestDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}T'
      '${two(value.hour)}:${two(value.minute)}';
}

String _formatPlainNumber(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}

double _parseAmount(String? value) {
  return double.tryParse(value?.trim() ?? '') ?? 0;
}

double? _parseNullableAmount(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  return double.tryParse(text);
}
