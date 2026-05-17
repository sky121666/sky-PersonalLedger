import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../accounts/data/account.dart';
import '../data/reminder_repository.dart';

class ReminderPage extends ConsumerStatefulWidget {
  const ReminderPage({super.key});

  @override
  ConsumerState<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends ConsumerState<ReminderPage> {
  String? _busyAction;
  String? _errorMessage;

  bool get _isBusy => _busyAction != null;

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(reminderDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('负债管理'),
        actions: [
          IconButton(
            onPressed: _isBusy ? null : () => _openReminderForm(),
            icon: const Icon(Icons.add),
            tooltip: '新增负债提醒',
          ),
          IconButton(
            onPressed: _isBusy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: dashboardState.when(
        loading: () => const AppLoadingView(message: '正在加载负债提醒...'),
        error: (error, _) => _ReminderErrorView(
          message: error.toString(),
          onRetry: _refresh,
          onRefresh: () => ref.refresh(reminderDashboardProvider.future),
        ),
        data: (dashboard) => _ReminderContent(
          dashboard: dashboard,
          busyAction: _busyAction,
          errorMessage: _errorMessage,
          onRefresh: () => ref.refresh(reminderDashboardProvider.future),
          onToggle: _toggleReminder,
          onEdit: (reminder) => _openReminderForm(
            reminder: reminder,
            debtAccounts: dashboard.debtAccounts,
          ),
          onDelete: _deleteReminder,
          onRecordPayment: (reminder) =>
              _openPaymentDialog(reminder, dashboard.paymentAccounts),
        ),
      ),
    );
  }

  void _refresh() {
    setState(() => _errorMessage = null);
    ref.invalidate(reminderDashboardProvider);
  }

  Future<void> _toggleReminder(ReminderItem reminder) async {
    await _runAction(
      action: 'toggle-${reminder.id}',
      successMessage: reminder.isEnabled ? '提醒已暂停' : '提醒已启用',
      request: () => ref
          .read(reminderRepositoryProvider)
          .toggleReminder(reminder.id)
          .then((_) {}),
    );
  }

  Future<void> _openReminderForm({
    ReminderItem? reminder,
    List<Account> debtAccounts = const [],
  }) async {
    final dashboard = ref.read(reminderDashboardProvider).valueOrNull;
    final accounts = debtAccounts.isEmpty
        ? dashboard?.debtAccounts ?? const <Account>[]
        : debtAccounts;
    final result = await _showReminderFormDialog(
      context: context,
      reminder: reminder,
      debtAccounts: accounts,
    );
    if (result == null || !mounted) {
      return;
    }

    await _runAction(
      action: reminder == null ? 'create' : 'edit-${reminder.id}',
      successMessage: reminder == null ? '负债提醒已创建' : '负债提醒已更新',
      request: () {
        final repository = ref.read(reminderRepositoryProvider);
        if (reminder == null) {
          return repository.createReminder(result).then((_) {});
        }
        return repository.updateReminder(reminder.id, result).then((_) {});
      },
    );
  }

  Future<void> _deleteReminder(ReminderItem reminder) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除负债提醒',
      message: '删除后相关还款记录也将从提醒中移除。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    await _runAction(
      action: 'delete-${reminder.id}',
      successMessage: '负债提醒已删除',
      request: () =>
          ref.read(reminderRepositoryProvider).deleteReminder(reminder.id),
    );
  }

  Future<void> _openPaymentDialog(
    ReminderItem reminder,
    List<Account> paymentAccounts,
  ) async {
    final result = await _showPaymentDialog(
      context: context,
      reminder: reminder,
      paymentAccounts: paymentAccounts,
    );
    if (result == null || !mounted) {
      return;
    }

    await _runAction(
      action: 'payment-${reminder.id}',
      successMessage: '还款已记录',
      request: () => ref
          .read(reminderRepositoryProvider)
          .recordPayment(
            reminder.id,
            amount: result.amount,
            accountId: result.accountId,
            principalAmount: result.principalAmount,
            interestAmount: result.interestAmount,
          )
          .then((_) {}),
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
      ref.invalidate(reminderDashboardProvider);
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

class _ReminderContent extends StatelessWidget {
  const _ReminderContent({
    required this.dashboard,
    required this.busyAction,
    required this.errorMessage,
    required this.onRefresh,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRecordPayment,
  });

  final ReminderDashboard dashboard;
  final String? busyAction;
  final String? errorMessage;
  final Future<void> Function() onRefresh;
  final ValueChanged<ReminderItem> onToggle;
  final ValueChanged<ReminderItem> onEdit;
  final ValueChanged<ReminderItem> onDelete;
  final ValueChanged<ReminderItem> onRecordPayment;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (errorMessage != null) ...[
              _MessagePanel(message: errorMessage!),
              const SizedBox(height: 12),
            ],
            _DebtSummaryCard(summary: dashboard.summary),
            const SizedBox(height: 16),
            if (dashboard.reminders.isEmpty)
              const _EmptyReminderCard()
            else ...[
              _ReminderSection(
                title: '进行中',
                reminders: dashboard.activeReminders,
                busyAction: busyAction,
                onToggle: onToggle,
                onEdit: onEdit,
                onDelete: onDelete,
                onRecordPayment: onRecordPayment,
              ),
              _ReminderSection(
                title: '已暂停',
                reminders: dashboard.inactiveReminders,
                busyAction: busyAction,
                onToggle: onToggle,
                onEdit: onEdit,
                onDelete: onDelete,
                onRecordPayment: onRecordPayment,
              ),
              _ReminderSection(
                title: '已还清',
                reminders: dashboard.paidOffReminders,
                busyAction: busyAction,
                onToggle: onToggle,
                onEdit: onEdit,
                onDelete: onDelete,
                onRecordPayment: onRecordPayment,
                readOnly: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderErrorView extends StatelessWidget {
  const _ReminderErrorView({
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

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
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

class _DebtSummaryCard extends StatelessWidget {
  const _DebtSummaryCard({required this.summary});

  final DebtSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = math.min(summary.progress, 100) / 100;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.track_changes_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '上岸进度',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${summary.progress.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryMetric(
                    label: '待还',
                    value: _formatMoney(summary.totalDebt),
                  ),
                ),
                Expanded(
                  child: _SummaryMetric(
                    label: '已还',
                    value: _formatMoney(summary.totalPaid),
                  ),
                ),
                Expanded(
                  child: _SummaryMetric(
                    label: '本金',
                    value: _formatMoney(summary.totalPrincipal),
                  ),
                ),
              ],
            ),
            if (summary.nextPaymentName.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                summary.daysUntilNext == 0
                    ? '今天还款：${summary.nextPaymentName}'
                    : '${summary.daysUntilNext} 天后还款：${summary.nextPaymentName}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ReminderSection extends StatelessWidget {
  const _ReminderSection({
    required this.title,
    required this.reminders,
    required this.busyAction,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRecordPayment,
    this.readOnly = false,
  });

  final String title;
  final List<ReminderItem> reminders;
  final String? busyAction;
  final ValueChanged<ReminderItem> onToggle;
  final ValueChanged<ReminderItem> onEdit;
  final ValueChanged<ReminderItem> onDelete;
  final ValueChanged<ReminderItem> onRecordPayment;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            '$title (${reminders.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final reminder in reminders) ...[
          _ReminderCard(
            reminder: reminder,
            busyAction: busyAction,
            readOnly: readOnly,
            onToggle: () => onToggle(reminder),
            onEdit: () => onEdit(reminder),
            onDelete: () => onDelete(reminder),
            onRecordPayment: () => onRecordPayment(reminder),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.busyAction,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRecordPayment,
    required this.readOnly,
  });

  final ReminderItem reminder;
  final String? busyAction;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRecordPayment;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = reminder.daysUntilPayment(DateTime.now());
    final busy =
        busyAction == 'toggle-${reminder.id}' ||
        busyAction == 'delete-${reminder.id}' ||
        busyAction == 'payment-${reminder.id}';

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
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(_loanTypeIcon(reminder.loanType)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        days == 0
                            ? '今天还款'
                            : '每月 ${reminder.paymentDay} 日，$days 天后',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: days <= reminder.advanceDays
                              ? Colors.orange
                              : colorScheme.outline,
                        ),
                      ),
                      if (reminder.accountName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          reminder.accountName,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.outline),
                        ),
                      ],
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  PopupMenuButton<_ReminderMenuAction>(
                    tooltip: '更多操作',
                    onSelected: (action) {
                      switch (action) {
                        case _ReminderMenuAction.payment:
                          onRecordPayment();
                        case _ReminderMenuAction.edit:
                          onEdit();
                        case _ReminderMenuAction.toggle:
                          onToggle();
                        case _ReminderMenuAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      if (!readOnly && reminder.principal != null)
                        const PopupMenuItem(
                          value: _ReminderMenuAction.payment,
                          child: Text('记录还款'),
                        ),
                      if (!readOnly)
                        const PopupMenuItem(
                          value: _ReminderMenuAction.edit,
                          child: Text('编辑'),
                        ),
                      PopupMenuItem(
                        value: _ReminderMenuAction.toggle,
                        child: Text(reminder.isEnabled ? '暂停提醒' : '启用提醒'),
                      ),
                      const PopupMenuItem(
                        value: _ReminderMenuAction.delete,
                        child: Text('删除'),
                      ),
                    ],
                  ),
              ],
            ),
            if (reminder.principal != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: reminder.progress / 100,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${reminder.progress.toStringAsFixed(0)}%'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (reminder.principal != null)
                  _InfoChip(
                    label: '本金',
                    value: _formatMoney(reminder.principal!),
                  ),
                if (reminder.currentBalance != null)
                  _InfoChip(
                    label: '待还',
                    value: _formatMoney(reminder.currentBalance!),
                  ),
                if (reminder.amount != null)
                  _InfoChip(label: '月供', value: _formatMoney(reminder.amount!)),
              ],
            ),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label $value'),
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.surfaceContainerHighest,
    );
  }
}

class _EmptyReminderCard extends StatelessWidget {
  const _EmptyReminderCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: AppEmptyView(
          title: '暂无负债提醒',
          message: '添加分期或还款计划后，可以在这里跟踪上岸进度。',
          icon: Icons.notifications_none_outlined,
        ),
      ),
    );
  }
}

Future<ReminderFormRequest?> _showReminderFormDialog({
  required BuildContext context,
  required List<Account> debtAccounts,
  ReminderItem? reminder,
}) {
  return showDialog<ReminderFormRequest>(
    context: context,
    builder: (context) =>
        _ReminderFormDialog(reminder: reminder, debtAccounts: debtAccounts),
  );
}

class _ReminderFormDialog extends StatefulWidget {
  const _ReminderFormDialog({required this.debtAccounts, this.reminder});

  final ReminderItem? reminder;
  final List<Account> debtAccounts;

  @override
  State<_ReminderFormDialog> createState() => _ReminderFormDialogState();
}

class _ReminderFormDialogState extends State<_ReminderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _paymentDayController;
  late final TextEditingController _billingDayController;
  late final TextEditingController _advanceDaysController;
  late final TextEditingController _amountController;
  late final TextEditingController _principalController;
  late final TextEditingController _currentBalanceController;
  late final TextEditingController _interestRateController;
  late final TextEditingController _remarkController;
  late String _loanType;
  late String _color;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    final reminder = widget.reminder;
    final request = reminder == null
        ? const ReminderFormRequest(
            name: '',
            loanType: 'credit_card',
            paymentDay: 1,
            advanceDays: 3,
          )
        : ReminderFormRequest.fromReminder(reminder);

    _nameController = TextEditingController(text: request.name);
    _paymentDayController = TextEditingController(
      text: request.paymentDay.toString(),
    );
    _billingDayController = TextEditingController(
      text: _formatOptionalInt(request.billingDay),
    );
    _advanceDaysController = TextEditingController(
      text: request.advanceDays.toString(),
    );
    _amountController = TextEditingController(
      text: _formatOptionalNumber(request.amount),
    );
    _principalController = TextEditingController(
      text: _formatOptionalNumber(request.principal),
    );
    _currentBalanceController = TextEditingController(
      text: _formatOptionalNumber(request.currentBalance),
    );
    _interestRateController = TextEditingController(
      text: _formatOptionalNumber(request.interestRate),
    );
    _remarkController = TextEditingController(text: request.remark);
    _loanType = request.loanType;
    _color = request.color;
    final accountId = request.accountId;
    _accountId =
        accountId != null &&
            widget.debtAccounts.any((account) => account.id == accountId)
        ? accountId
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _paymentDayController.dispose();
    _billingDayController.dispose();
    _advanceDaysController.dispose();
    _amountController.dispose();
    _principalController.dispose();
    _currentBalanceController.dispose();
    _interestRateController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.reminder == null ? '新增负债提醒' : '编辑负债提醒'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _loanType,
                  decoration: const InputDecoration(
                    labelText: '分期类型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'credit_card', child: Text('信用卡')),
                    DropdownMenuItem(value: 'mortgage', child: Text('房贷')),
                    DropdownMenuItem(value: 'car_loan', child: Text('车贷')),
                    DropdownMenuItem(
                      value: 'consumer_loan',
                      child: Text('消费贷'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('其他')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _loanType = value;
                      _color = _loanTypeColor(value);
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (widget.debtAccounts.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(
                      labelText: '关联负债账户',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('不关联账户')),
                      for (final account in widget.debtAccounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _accountId = value == null || value.isEmpty
                            ? null
                            : value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '分期名称',
                    hintText: '例如：房贷、花呗',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return '请输入名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _paymentDayController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '还款日',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateDay,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _billingDayController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '账单日',
                          border: OutlineInputBorder(),
                        ),
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
                        controller: _principalController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '分期总额',
                          prefixText: '¥ ',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateOptionalAmount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _currentBalanceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '当前欠款',
                          prefixText: '¥ ',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateOptionalAmount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '月供/最低还款',
                          prefixText: '¥ ',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateOptionalAmount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _advanceDaysController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '提前提醒天数',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateAdvanceDays,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _interestRateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '年化利率',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateOptionalAmount,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarkController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    border: OutlineInputBorder(),
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

  String? _validateDay(String? value) {
    final day = int.tryParse(value?.trim() ?? '');
    if (day == null || day < 1 || day > 31) {
      return '请输入 1-31';
    }
    return null;
  }

  String? _validateOptionalDay(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return _validateDay(text);
  }

  String? _validateAdvanceDays(String? value) {
    final days = int.tryParse(value?.trim() ?? '');
    if (days == null || days < 0 || days > 30) {
      return '请输入 0-30';
    }
    return null;
  }

  String? _validateOptionalAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final amount = double.tryParse(text);
    if (amount == null || amount < 0) {
      return '请输入有效金额';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final principal = _parseOptionalAmount(_principalController.text);
    final currentBalance =
        _parseOptionalAmount(_currentBalanceController.text) ?? principal;

    Navigator.of(context).pop(
      ReminderFormRequest(
        name: _nameController.text.trim(),
        accountId: _accountId,
        loanType: _loanType,
        paymentDay: int.parse(_paymentDayController.text.trim()),
        billingDay: _parseOptionalInt(_billingDayController.text),
        advanceDays: int.parse(_advanceDaysController.text.trim()),
        amount: _parseOptionalAmount(_amountController.text),
        principal: principal,
        currentBalance: currentBalance,
        interestRate: _parseOptionalAmount(_interestRateController.text),
        color: _color,
        remark: _remarkController.text.trim(),
        evidence: '',
      ),
    );
  }
}

Future<_PaymentFormResult?> _showPaymentDialog({
  required BuildContext context,
  required ReminderItem reminder,
  required List<Account> paymentAccounts,
}) {
  return showDialog<_PaymentFormResult>(
    context: context,
    builder: (context) =>
        _PaymentDialog(reminder: reminder, paymentAccounts: paymentAccounts),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.reminder, required this.paymentAccounts});

  final ReminderItem reminder;
  final List<Account> paymentAccounts;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _principalController;
  late final TextEditingController _interestController;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    final amount =
        widget.reminder.amount ?? widget.reminder.currentBalance ?? 0;
    _amountController = TextEditingController(
      text: amount == 0 ? '' : amount.toStringAsFixed(2),
    );
    _principalController = TextEditingController();
    _interestController = TextEditingController();
    _accountId = widget.paymentAccounts.isEmpty
        ? null
        : widget.paymentAccounts.first.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _principalController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('记录还款：${widget.reminder.displayName}'),
      content: widget.paymentAccounts.isEmpty
          ? const Text('暂无可用还款账户，请先创建现金、储蓄卡等资产账户。')
          : Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '还款总额',
                      prefixText: '¥ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validatePositiveAmount,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(
                      labelText: '还款账户',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final account in widget.paymentAccounts)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _accountId = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _principalController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: '本金',
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateOptionalAmount,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _interestController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: '利息',
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateOptionalAmount,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: widget.paymentAccounts.isEmpty ? null : _submit,
          child: const Text('确认还款'),
        ),
      ],
    );
  }

  String? _validatePositiveAmount(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    if (amount == null || amount <= 0) {
      return '请输入大于 0 的金额';
    }
    return null;
  }

  String? _validateOptionalAmount(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final amount = double.tryParse(text);
    if (amount == null || amount < 0) {
      return '请输入有效金额';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      _PaymentFormResult(
        amount: double.parse(_amountController.text.trim()),
        accountId: _accountId,
        principalAmount: _parseOptionalAmount(_principalController.text),
        interestAmount: _parseOptionalAmount(_interestController.text),
      ),
    );
  }
}

class _PaymentFormResult {
  const _PaymentFormResult({
    required this.amount,
    this.accountId,
    this.principalAmount,
    this.interestAmount,
  });

  final double amount;
  final String? accountId;
  final double? principalAmount;
  final double? interestAmount;
}

enum _ReminderMenuAction { payment, edit, toggle, delete }

double? _parseOptionalAmount(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  return double.tryParse(text);
}

int? _parseOptionalInt(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  return int.tryParse(text);
}

String _formatOptionalNumber(double? value) {
  if (value == null) {
    return '';
  }
  return value.toStringAsFixed(2);
}

String _formatOptionalInt(int? value) {
  if (value == null) {
    return '';
  }
  return value.toString();
}

String _loanTypeColor(String loanType) {
  return switch (loanType) {
    'credit_card' => '#3B82F6',
    'mortgage' => '#10B981',
    'car_loan' => '#F59E0B',
    'consumer_loan' => '#8B5CF6',
    _ => '#6B7280',
  };
}

IconData _loanTypeIcon(String loanType) {
  return switch (loanType) {
    'credit_card' => Icons.credit_card,
    'mortgage' => Icons.house_outlined,
    'car_loan' => Icons.directions_car_outlined,
    'consumer_loan' => Icons.shopping_bag_outlined,
    _ => Icons.account_balance_outlined,
  };
}

String _formatMoney(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign¥${value.abs().toStringAsFixed(2)}';
}
