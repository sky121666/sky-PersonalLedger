import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/money_formatter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../accounts/data/account.dart';
import '../../attachments/data/attachment_cleanup.dart';
import '../../attachments/data/attachment_models.dart';
import '../../attachments/data/attachment_repository.dart';
import '../../attachments/presentation/attachment_picker_field.dart';
import '../../transactions/application/ledger_refresh.dart';
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
        title: const Text('负债'),
        actions: [
          IconButton(
            key: const ValueKey('reminder-add'),
            onPressed: _isBusy ? null : () => _openReminderForm(),
            tooltip: '添加负债提醒',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: dashboardState.when(
        loading: () => const AppLoadingView(message: '正在加载负债提醒...'),
        error: (error, _) => _ReminderErrorView(
          message: '负债提醒加载失败',
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
    final request = result.request;

    await _runAction(
      action: reminder == null ? 'create' : 'edit-${reminder.id}',
      successMessage: reminder == null ? '负债提醒已创建' : '负债提醒已更新',
      request: () async {
        final repository = ref.read(reminderRepositoryProvider);
        if (reminder == null) {
          final saved = await repository.createReminder(request);
          if (result.pendingFiles.isEmpty) {
            return;
          }
          if (saved == null || saved.id.isEmpty) {
            throw const FormatException('提醒已创建，但附件暂时无法添加');
          }
          final uploadedAttachments = await _uploadPendingAttachments(
            result.pendingFiles,
            saved.id,
          );
          await repository.updateReminder(
            saved.id,
            request.copyWith(
              evidence: _encodeAttachmentEvidence([
                ...result.attachments,
                ...uploadedAttachments,
              ]),
            ),
          );
          return;
        }
        final saved = await repository.updateReminder(reminder.id, request);
        var retainedAttachments = result.attachments;
        if (result.pendingFiles.isEmpty) {
          await _deleteRemovedAttachments(
            originalPaths: decodeAttachmentPaths(reminder.evidence),
            retainedAttachments: retainedAttachments,
          );
          return;
        }
        final refId = saved?.id.isNotEmpty == true ? saved!.id : reminder.id;
        final uploadedAttachments = await _uploadPendingAttachments(
          result.pendingFiles,
          refId,
        );
        retainedAttachments = [...result.attachments, ...uploadedAttachments];
        await repository.updateReminder(
          refId,
          request.copyWith(
            evidence: _encodeAttachmentEvidence(retainedAttachments),
          ),
        );
        await _deleteRemovedAttachments(
          originalPaths: decodeAttachmentPaths(reminder.evidence),
          retainedAttachments: retainedAttachments,
        );
      },
    );
  }

  Future<void> _deleteReminder(ReminderItem reminder) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除负债提醒',
      message: '删除「${reminder.displayName}」？',
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

  Future<List<LedgerAttachment>> _uploadPendingAttachments(
    List<PendingAttachmentFile> files,
    String refId,
  ) async {
    if (files.isEmpty) {
      return const [];
    }
    final repository = ref.read(attachmentRepositoryProvider);
    final uploadedAttachments = <LedgerAttachment>[];
    for (final file in files) {
      uploadedAttachments.add(
        await repository.upload(
          file: file,
          category: 'reminders',
          refId: refId,
        ),
      );
    }
    return uploadedAttachments;
  }

  Future<void> _deleteRemovedAttachments({
    required Iterable<String> originalPaths,
    required Iterable<LedgerAttachment> retainedAttachments,
  }) async {
    await deleteRemovedAttachments(
      repository: ref.read(attachmentRepositoryProvider),
      originalPaths: originalPaths,
      retainedPaths: retainedAttachments.map((item) => item.path),
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
      ref.invalidateLedgerMutationViews();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = '负债提醒保存失败');
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
    final rows = _buildRows();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final bottom = index == rows.length - 1 ? 0.0 : 12.0;
            return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: switch (row.kind) {
                _ReminderRowKind.error => _MessagePanel(message: errorMessage!),
                _ReminderRowKind.summary => _DebtSummaryCard(
                  summary: dashboard.summary,
                ),
                _ReminderRowKind.empty => const _EmptyReminderCard(),
                _ReminderRowKind.section => _ReminderSectionLabel(
                  title: row.title!,
                  count: row.count!,
                  readOnly: row.readOnly,
                ),
                _ReminderRowKind.item => _ReminderCard(
                  reminder: row.reminder!,
                  busyAction: busyAction,
                  readOnly: row.readOnly,
                  onToggle: () => onToggle(row.reminder!),
                  onEdit: () => onEdit(row.reminder!),
                  onDelete: () => onDelete(row.reminder!),
                  onRecordPayment: () => onRecordPayment(row.reminder!),
                ),
              },
            );
          },
        ),
      ),
    );
  }

  List<_ReminderRow> _buildRows() {
    if (dashboard.reminders.isEmpty) {
      return [
        if (errorMessage != null) const _ReminderRow(_ReminderRowKind.error),
        const _ReminderRow(_ReminderRowKind.summary),
        const _ReminderRow(_ReminderRowKind.empty),
      ];
    }
    return [
      if (errorMessage != null) const _ReminderRow(_ReminderRowKind.error),
      const _ReminderRow(_ReminderRowKind.summary),
      ..._sectionRows('进行中', dashboard.activeReminders),
      ..._sectionRows('已暂停', dashboard.inactiveReminders),
      ..._sectionRows('已还清', dashboard.paidOffReminders, readOnly: true),
    ];
  }

  List<_ReminderRow> _sectionRows(
    String title,
    List<ReminderItem> reminders, {
    bool readOnly = false,
  }) {
    if (reminders.isEmpty) {
      return const [];
    }
    return [
      _ReminderRow(
        _ReminderRowKind.section,
        title: title,
        count: reminders.length,
        readOnly: readOnly,
      ),
      for (final reminder in reminders)
        _ReminderRow(
          _ReminderRowKind.item,
          reminder: reminder,
          readOnly: readOnly,
        ),
    ];
  }
}

class _ReminderRow {
  const _ReminderRow(
    this.kind, {
    this.title,
    this.count,
    this.reminder,
    this.readOnly = false,
  });

  final _ReminderRowKind kind;
  final String? title;
  final int? count;
  final ReminderItem? reminder;
  final bool readOnly;
}

enum _ReminderRowKind { error, summary, empty, section, item }

enum _ReminderMenuAction { none, payment, edit, toggle, delete }

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
    final rows = [
      const _ReminderErrorRow(SizedBox(height: 48)),
      _ReminderErrorRow(AppErrorView(message: message, onRetry: onRetry), 0),
    ];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == rows.length - 1 ? 0 : row.bottomSpacing,
              ),
              child: row.child,
            );
          },
        ),
      ),
    );
  }
}

class _ReminderErrorRow {
  const _ReminderErrorRow(this.child, [this.bottomSpacing = 0]);

  final Widget child;
  final double bottomSpacing;
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

    return PremiumSurface(
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '还款进度',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${summary.progress.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DebtMiniStat(
                  label: '待还',
                  value: _formatMoney(summary.totalDebt),
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DebtMiniStat(
                  label: '已还',
                  value: _formatMoney(summary.totalPaid),
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DebtMiniStat(
                  label: '本金',
                  value: _formatMoney(summary.totalPrincipal),
                  color: colorScheme.secondary,
                ),
              ),
            ],
          ),
          if (summary.nextPaymentName.isNotEmpty) ...[
            const SizedBox(height: 12),
            _NextPaymentBanner(summary: summary),
          ],
        ],
      ),
    );
  }
}

class _DebtMiniStat extends StatelessWidget {
  const _DebtMiniStat({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _NextPaymentBanner extends StatelessWidget {
  const _NextPaymentBanner({required this.summary});

  final DebtSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary.daysUntilNext == 0
                  ? '今天还款：${summary.nextPaymentName}'
                  : '${summary.daysUntilNext} 天后还款：${summary.nextPaymentName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderSectionLabel extends StatelessWidget {
  const _ReminderSectionLabel({
    required this.title,
    required this.count,
    required this.readOnly,
  });

  final String title;
  final int count;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ReminderCard extends ConsumerStatefulWidget {
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
  ConsumerState<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends ConsumerState<_ReminderCard> {
  bool _expanded = false;
  void _onMenuSelected(_ReminderMenuAction action) {
    switch (action) {
      case _ReminderMenuAction.payment:
        widget.onRecordPayment();
        return;
      case _ReminderMenuAction.edit:
        widget.onEdit();
        return;
      case _ReminderMenuAction.toggle:
        widget.onToggle();
        return;
      case _ReminderMenuAction.delete:
        widget.onDelete();
        return;
      case _ReminderMenuAction.none:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final reminder = widget.reminder;
    final days = reminder.daysUntilPayment(DateTime.now());
    final busy =
        widget.busyAction == 'toggle-${reminder.id}' ||
        widget.busyAction == 'delete-${reminder.id}' ||
        widget.busyAction == 'payment-${reminder.id}';
    final accentColor = days <= reminder.advanceDays
        ? financeColors.warning
        : colorScheme.primary;
    final reminderColor = _parseReminderColor(reminder.color, accentColor);
    final dueText = days == 0 ? '今天还款' : '每月 ${reminder.paymentDay} 日，$days 天后';
    final statusLabel = reminder.paidOffAt != null
        ? '已还清'
        : !reminder.isEnabled
        ? '已暂停'
        : days <= reminder.advanceDays
        ? '临近还款'
        : '进行中';
    final statusColor = reminder.paidOffAt != null
        ? financeColors.income
        : !reminder.isEnabled
        ? colorScheme.outline
        : days <= reminder.advanceDays
        ? financeColors.warning
        : reminderColor;

    return Semantics(
      label:
          '${reminder.displayName}，${reminder.loanTypeLabel}，$statusLabel，待还${_formatMoney(reminder.currentBalance ?? 0)}，$dueText',
      button: false,
      child: Container(
        key: ValueKey('reminder-card-${reminder.id}'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          reminder.loanTypeLabel,
                          dueText,
                          if (statusLabel != '进行中') statusLabel,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '待还 ${_formatMoney(reminder.currentBalance ?? 0)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('reminder-toggle-details-${reminder.id}'),
                        tooltip: _expanded
                            ? '收起${reminder.name}详情'
                            : '展开${reminder.name}详情',
                        onPressed: () => setState(() {
                          _expanded = !_expanded;
                        }),
                        icon: Icon(_expanded ? Icons.remove : Icons.add),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      if (_expanded)
                        PopupMenuButton<_ReminderMenuAction>(
                          key: ValueKey('reminder-more-menu-${reminder.id}'),
                          icon: const Icon(
                            Icons.more_horiz,
                            size: 20,
                            semanticLabel: '提醒操作',
                          ),
                          tooltip: '提醒操作',
                          onSelected: _onMenuSelected,
                          itemBuilder: (context) => [
                            if (!widget.readOnly && reminder.principal != null)
                              PopupMenuItem<_ReminderMenuAction>(
                                value: _ReminderMenuAction.payment,
                                key: ValueKey(
                                  'reminder-action-payment-${reminder.id}',
                                ),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.payments_outlined,
                                    size: 16,
                                  ),
                                  title: const Text('记录还款'),
                                ),
                              ),
                            if (!widget.readOnly)
                              PopupMenuItem<_ReminderMenuAction>(
                                value: _ReminderMenuAction.edit,
                                key: ValueKey(
                                  'reminder-action-edit-${reminder.id}',
                                ),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                  ),
                                  title: const Text('编辑'),
                                ),
                              ),
                            PopupMenuItem<_ReminderMenuAction>(
                              value: _ReminderMenuAction.toggle,
                              key: ValueKey(
                                'reminder-action-toggle-${reminder.id}',
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  reminder.isEnabled
                                      ? Icons.pause_circle_outline
                                      : Icons.play_circle_outline,
                                  size: 16,
                                ),
                                title: Text(
                                  reminder.isEnabled ? '暂停提醒' : '启用提醒',
                                ),
                              ),
                            ),
                            PopupMenuItem<_ReminderMenuAction>(
                              value: _ReminderMenuAction.delete,
                              key: ValueKey(
                                'reminder-action-delete-${reminder.id}',
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                title: const Text('删除'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
            if (_expanded && reminder.principal != null) ...[
              _ReminderProgressLine(
                key: ValueKey('reminder-details-${reminder.id}'),
                progress: reminder.progress,
                color: accentColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderProgressLine extends StatelessWidget {
  const _ReminderProgressLine({
    super.key,
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = (progress / 100).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 5,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${progress.toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _EmptyReminderCard extends StatelessWidget {
  const _EmptyReminderCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: PremiumSurface(
        accentColor: colorScheme.primary,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox.square(
                dimension: 42,
                child: Icon(
                  Icons.notifications_none_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '还没有负债提醒',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '右上角添加',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<_ReminderFormResult?> _showReminderFormDialog({
  required BuildContext context,
  required List<Account> debtAccounts,
  ReminderItem? reminder,
}) {
  return showDialog<_ReminderFormResult>(
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
  bool _showMoreDetails = false;
  late List<LedgerAttachment> _attachments;
  List<PendingAttachmentFile> _pendingAttachmentFiles = const [];

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
    _attachments = decodeAttachmentPaths(
      request.evidence,
    ).map(LedgerAttachment.fromPath).toList();
    _showMoreDetails = false;
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
                          labelText: '每月还款',
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
                          labelText: '提前提醒',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateAdvanceDays,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    key: const ValueKey('reminder-more-details'),
                    onPressed: () =>
                        setState(() => _showMoreDetails = !_showMoreDetails),
                    icon: Icon(
                      _showMoreDetails
                          ? Icons.remove_rounded
                          : Icons.add_rounded,
                    ),
                    tooltip: _showMoreDetails ? '收起更多负债信息' : '展开更多负债信息',
                  ),
                ),
                if (_showMoreDetails) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _interestRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '利率',
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
                  const SizedBox(height: 12),
                  AttachmentPickerField(
                    attachments: _attachments,
                    pendingFiles: _pendingAttachmentFiles,
                    onAttachmentsChanged: (attachments) {
                      setState(() => _attachments = attachments);
                    },
                    onPendingFilesChanged: (files) {
                      setState(() => _pendingAttachmentFiles = files);
                    },
                  ),
                ],
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
        FilledButton(onPressed: _submit, child: const Text('保存提醒')),
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
      _ReminderFormResult(
        request: ReminderFormRequest(
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
          evidence: _encodeAttachmentEvidence(_attachments),
        ),
        attachments: _attachments,
        pendingFiles: _pendingAttachmentFiles,
      ),
    );
  }
}

class _ReminderFormResult {
  const _ReminderFormResult({
    required this.request,
    required this.attachments,
    required this.pendingFiles,
  });

  final ReminderFormRequest request;
  final List<LedgerAttachment> attachments;
  final List<PendingAttachmentFile> pendingFiles;
}

String _encodeAttachmentEvidence(List<LedgerAttachment> attachments) {
  return encodeAttachmentPaths(attachments.map((item) => item.path).toList());
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
          ? const Text('补充还款账户')
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Form(
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
                        onChanged: (value) =>
                            setState(() => _accountId = value),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _principalController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '利息',
                                border: OutlineInputBorder(),
                              ),
                              validator: _validateInterestAmount,
                            ),
                          ),
                        ],
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

  String? _validateInterestAmount(String? value) {
    final valueError = _validateOptionalAmount(value);
    if (valueError != null) {
      return valueError;
    }
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      return null;
    }
    final principal = _parseOptionalAmount(_principalController.text);
    final interest = _parseOptionalAmount(value ?? '');
    if (principal == null && interest == null) {
      return null;
    }

    final normalizedPrincipal = principal ?? amount - (interest ?? 0);
    final normalizedInterest = interest ?? amount - (principal ?? 0);
    if (normalizedPrincipal < 0 ||
        normalizedInterest < 0 ||
        (normalizedPrincipal + normalizedInterest - amount).abs() > 0.01) {
      return '本金+利息必须等于还款金额';
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

Color _parseReminderColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}

String _formatMoney(double value) {
  return formatMoney(value);
}
