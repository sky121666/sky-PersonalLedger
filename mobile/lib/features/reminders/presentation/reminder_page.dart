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
    required this.onDelete,
    required this.onRecordPayment,
  });

  final ReminderDashboard dashboard;
  final String? busyAction;
  final String? errorMessage;
  final Future<void> Function() onRefresh;
  final ValueChanged<ReminderItem> onToggle;
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
                onDelete: onDelete,
                onRecordPayment: onRecordPayment,
              ),
              _ReminderSection(
                title: '已暂停',
                reminders: dashboard.inactiveReminders,
                busyAction: busyAction,
                onToggle: onToggle,
                onDelete: onDelete,
                onRecordPayment: onRecordPayment,
              ),
              _ReminderSection(
                title: '已还清',
                reminders: dashboard.paidOffReminders,
                busyAction: busyAction,
                onToggle: onToggle,
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
    required this.onDelete,
    required this.onRecordPayment,
    this.readOnly = false,
  });

  final String title;
  final List<ReminderItem> reminders;
  final String? busyAction;
  final ValueChanged<ReminderItem> onToggle;
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
    required this.onDelete,
    required this.onRecordPayment,
    required this.readOnly,
  });

  final ReminderItem reminder;
  final String? busyAction;
  final VoidCallback onToggle;
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

enum _ReminderMenuAction { payment, toggle, delete }

double? _parseOptionalAmount(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }
  return double.tryParse(text);
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
