import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final dashboard = dashboardState.asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('借贷往来'),
        actions: dashboard == null
            ? null
            : [
                IconButton(
                  key: const ValueKey('lending-add'),
                  onPressed: _isBusy
                      ? null
                      : () => _openCreateChoice(dashboard.accounts),
                  tooltip: null,
                  icon: const Icon(Icons.add),
                ),
              ],
      ),
      body: dashboardState.when(
        loading: () => const _LendingLoadingView(),
        error: (error, _) =>
            AppErrorView(message: '借贷记录加载失败', onRetry: _refresh),
        data: (dashboard) => AdaptivePageContainer(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: _LendingBody(
              dashboard: dashboard,
              tab: _tab,
              busyAction: _busyAction,
              errorMessage: _errorMessage,
              onTabChanged: _isBusy
                  ? null
                  : (tab) => setState(() => _tab = tab),
              onEdit: (item) => _openEditForm(item, dashboard.accounts),
              onDelete: _deleteLending,
              onRepay: (item) =>
                  _openRepaymentDialog(item, dashboard.activeAccounts),
              onRecords: _openRecordsDialog,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateChoice(List<Account> accounts) async {
    final type = await showModalBottomSheet<LendingType>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('lending-add-lend-out'),
                leading: const Icon(Icons.north_east),
                title: const Text('借出'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(LendingType.lendOut),
              ),
              ListTile(
                key: const ValueKey('lending-add-borrow-in'),
                leading: const Icon(Icons.south_west),
                title: const Text('借入'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(LendingType.borrowIn),
              ),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) {
      return;
    }
    await _openCreateForm(type, accounts);
  }

  void _refresh() {
    setState(() => _errorMessage = null);
    ref.invalidate(lendingDashboardProvider);
  }

  Future<void> _openCreateForm(LendingType type, List<Account> accounts) async {
    final result = await showDialog<_LendingFormResult<CreateLendingRequest>>(
      context: context,
      builder: (context) => _LendingFormDialog(type: type, accounts: accounts),
    );
    if (result == null || !mounted) {
      return;
    }
    final request = result.request;

    await _runAction(
      action: 'create',
      successMessage: request.type == LendingType.lendOut
          ? '借出记录已创建'
          : '借入记录已创建',
      request: () async {
        final repository = ref.read(lendingRepositoryProvider);
        final saved = await repository.create(request);
        if (result.pendingFiles.isEmpty) {
          return;
        }
        if (saved == null || saved.id.isEmpty) {
          throw const FormatException('借贷记录已创建，但附件暂时无法添加');
        }
        final uploadedAttachments = await _uploadPendingAttachments(
          result.pendingFiles,
          saved.id,
        );
        await repository.update(
          saved.id,
          _updateRequestFromCreate(
            request,
            evidence: _encodeAttachmentEvidence([
              ...result.attachments,
              ...uploadedAttachments,
            ]),
          ),
        );
      },
    );
  }

  Future<void> _openEditForm(LendingItem item, List<Account> accounts) async {
    final result = await showDialog<_LendingFormResult<UpdateLendingRequest>>(
      context: context,
      builder: (context) => _LendingFormDialog(
        type: item.type,
        accounts: accounts,
        editingItem: item,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final request = result.request;

    await _runAction(
      action: 'edit-${item.id}',
      successMessage: '借贷记录已更新',
      request: () async {
        final repository = ref.read(lendingRepositoryProvider);
        final saved = await repository.update(item.id, request);
        var retainedAttachments = result.attachments;
        if (result.pendingFiles.isEmpty) {
          await _deleteRemovedAttachments(
            originalPaths: decodeAttachmentPaths(item.evidence),
            retainedAttachments: retainedAttachments,
          );
          return;
        }
        final refId = saved?.id.isNotEmpty == true ? saved!.id : item.id;
        final uploadedAttachments = await _uploadPendingAttachments(
          result.pendingFiles,
          refId,
        );
        retainedAttachments = [...result.attachments, ...uploadedAttachments];
        await repository.update(
          refId,
          _copyUpdateRequest(
            request,
            evidence: _encodeAttachmentEvidence(retainedAttachments),
          ),
        );
        await _deleteRemovedAttachments(
          originalPaths: decodeAttachmentPaths(item.evidence),
          retainedAttachments: retainedAttachments,
        );
      },
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

  Future<void> _openRecordsDialog(LendingItem item) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _LendingRecordsDialog(item: item),
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
        await repository.upload(file: file, category: 'lendings', refId: refId),
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

  Future<void> _deleteLending(LendingItem item) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除借贷记录',
      message: '删除「${item.contactName}」？',
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
      ref.invalidateLedgerMutationViews();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = '借贷记录保存失败');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }
}

class _LendingLoadingView extends StatelessWidget {
  const _LendingLoadingView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AdaptivePageContainer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LendingTab { lendOut, borrowIn, settled }

enum _LendingMenuAction { repay, records, edit, delete }

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary});

  final LendingSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final netColor = summary.netLending >= 0
        ? financeColors.income
        : colorScheme.error;
    return PremiumSurface(
      accentColor: netColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '往来金额',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _formatMoney(summary.netLending.abs()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: netColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SummaryInlineMetric(
                  label: '应收',
                  value: _formatMoney(summary.totalReceivable),
                  color: financeColors.income,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryInlineMetric(
                  label: '应付',
                  value: _formatMoney(summary.totalPayable),
                  color: colorScheme.error,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryInlineMetric extends StatelessWidget {
  const _SummaryInlineMetric({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
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
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CompactSwitchRow extends StatelessWidget {
  const _CompactSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
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
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LendingBody extends StatelessWidget {
  const _LendingBody({
    required this.dashboard,
    required this.tab,
    required this.busyAction,
    required this.errorMessage,
    required this.onTabChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onRepay,
    required this.onRecords,
  });

  final LendingDashboard dashboard;
  final _LendingTab tab;
  final String? busyAction;
  final String? errorMessage;
  final ValueChanged<_LendingTab>? onTabChanged;
  final ValueChanged<LendingItem> onEdit;
  final ValueChanged<LendingItem> onDelete;
  final ValueChanged<LendingItem> onRepay;
  final ValueChanged<LendingItem> onRecords;

  List<LendingItem> get _lendings {
    return switch (tab) {
      _LendingTab.lendOut => dashboard.activeLendOut,
      _LendingTab.borrowIn => dashboard.activeBorrowIn,
      _LendingTab.settled => dashboard.settled,
    };
  }

  @override
  Widget build(BuildContext context) {
    final lendings = _lendings;
    final rows = _buildRows(lendings);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row.kind) {
          _LendingRowKind.error => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ErrorBanner(message: errorMessage!),
          ),
          _LendingRowKind.summary => _SummarySection(
            summary: dashboard.summary,
          ),
          _LendingRowKind.segment => Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: SegmentedButton<_LendingTab>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
              selected: {tab},
              onSelectionChanged: onTabChanged == null
                  ? null
                  : (value) => onTabChanged!(value.single),
            ),
          ),
          _LendingRowKind.empty => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _LendingEmptyState(
              title: switch (tab) {
                _LendingTab.lendOut => '还没有借出记录',
                _LendingTab.borrowIn => '还没有借入记录',
                _LendingTab.settled => '还没有结清记录',
              },
              message: '右上角添加',
              icon: Icons.handshake_outlined,
            ),
          ),
          _LendingRowKind.item => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LendingCard(
              item: row.item!,
              busy: busyAction?.endsWith(row.item!.id) ?? false,
              onEdit: () => onEdit(row.item!),
              onDelete: () => onDelete(row.item!),
              onRepay: () => onRepay(row.item!),
              onRecords: () => onRecords(row.item!),
            ),
          ),
        };
      },
    );
  }

  List<_LendingRow> _buildRows(List<LendingItem> lendings) {
    return [
      if (errorMessage != null) const _LendingRow(_LendingRowKind.error),
      const _LendingRow(_LendingRowKind.summary),
      const _LendingRow(_LendingRowKind.segment),
      if (lendings.isEmpty)
        const _LendingRow(_LendingRowKind.empty)
      else
        for (final item in lendings) _LendingRow(_LendingRowKind.item, item),
    ];
  }
}

class _LendingRow {
  const _LendingRow(this.kind, [this.item]);

  final _LendingRowKind kind;
  final LendingItem? item;
}

enum _LendingRowKind { error, summary, segment, empty, item }

class _LendingEmptyState extends StatelessWidget {
  const _LendingEmptyState({
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

class _LendingCard extends ConsumerStatefulWidget {
  const _LendingCard({
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onRepay,
    required this.onRecords,
  });

  final LendingItem item;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRepay;
  final VoidCallback onRecords;

  @override
  ConsumerState<_LendingCard> createState() => _LendingCardState();
}

class _LendingCardState extends ConsumerState<_LendingCard> {
  bool _expanded = false;

  Widget _menuItem({
    required _LendingMenuAction action,
    required String keySuffix,
    required String title,
    required IconData icon,
    bool enabled = true,
  }) {
    return ListTile(
      key: ValueKey('lending-action-$keySuffix-${widget.item.id}'),
      enabled: enabled,
      leading: Icon(icon, size: 18),
      title: Text(title),
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 0,
      dense: true,
      onTap: enabled
          ? () {
              Navigator.of(context).pop(action);
            }
          : null,
    );
  }

  void _onMenuSelected(_LendingMenuAction action) {
    switch (action) {
      case _LendingMenuAction.repay:
        widget.onRepay();
        return;
      case _LendingMenuAction.records:
        widget.onRecords();
        return;
      case _LendingMenuAction.edit:
        widget.onEdit();
        return;
      case _LendingMenuAction.delete:
        widget.onDelete();
        return;
    }
  }

  Future<void> _openActionSheet() async {
    final action = await showModalBottomSheet<_LendingMenuAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.item.isSettled)
                _menuItem(
                  action: _LendingMenuAction.repay,
                  keySuffix: 'repay',
                  title: '记录还款',
                  icon: Icons.payments_outlined,
                ),
              _menuItem(
                action: _LendingMenuAction.records,
                keySuffix: 'records',
                title: '还款记录',
                icon: Icons.receipt_long_outlined,
              ),
              _menuItem(
                action: _LendingMenuAction.edit,
                keySuffix: 'edit',
                title: '编辑',
                icon: Icons.edit_outlined,
              ),
              _menuItem(
                action: _LendingMenuAction.delete,
                keySuffix: 'delete',
                title: '删除',
                icon: Icons.delete_outline,
              ),
            ],
          ),
        ),
      ),
    );
    if (action != null && mounted) {
      _onMenuSelected(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final accent = item.type == LendingType.lendOut
        ? financeColors.income
        : financeColors.asset;
    final statusLabel = item.isSettled
        ? '已结清'
        : item.isOverdue
        ? '已逾期'
        : '进行中';
    final statusColor = item.isSettled
        ? financeColors.income
        : item.isOverdue
        ? financeColors.expense
        : accent;
    final repaidLabel = item.type == LendingType.lendOut ? '已收' : '已还';
    final detailLabel = item.totalRepaid > 0
        ? _formatMoney(item.totalRepaid)
        : null;
    final shouldShowDetail = item.totalRepaid > 0;
    return Semantics(
      container: true,
      label:
          '${item.contactName}，${item.typeLabel}，本金${_formatMoney(item.principal)}，剩余${_formatMoney(item.currentBalance)}，$statusLabel',
      button: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: item.isOverdue
                ? statusColor.withValues(alpha: 0.34)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          key: ValueKey('lending-card-${item.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: InkWell(
                key: ValueKey('lending-detail-toggle-${item.id}'),
                onTap: () {
                  setState(() => _expanded = !_expanded);
                },
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.contactName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.1,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatMoney(item.currentBalance),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w900,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                              if (!_expanded) ...[
                                const SizedBox(height: 2),
                                _LendingMetaPill(
                                  label: statusLabel,
                                  color: statusColor,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_expanded && item.progress > 0) ...[
                      const SizedBox(height: 6),
                      if (!item.isSettled)
                        _LendingProgressLine(
                          progress: item.progress,
                          color: accent,
                        ),
                    ],
                    if (_expanded) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          item.typeLabel,
                          _buildTimingLabel(item),
                          if (detailLabel != null) '$repaidLabel $detailLabel',
                        ].join('  ·  '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else
                      const SizedBox(height: 2),
                    const SizedBox(height: 1),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.busy)
                          const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else ...[
                          const Spacer(),
                          IconButton(
                            key: ValueKey(
                              'lending-more-menu-${widget.item.id}',
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            tooltip: '借贷操作',
                            onPressed: _openActionSheet,
                            icon: const Icon(
                              Icons.more_horiz,
                              size: 18,
                              semanticLabel: '借贷操作',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && (shouldShowDetail || item.isOverdue)) ...[
              const SizedBox(height: 4),
              Text(
                item.isOverdue
                    ? shouldShowDetail
                          ? '$repaidLabel ${detailLabel ?? _formatMoney(0)}（逾期）'
                          : '已逾期'
                    : '$repaidLabel ${detailLabel ?? _formatMoney(0)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (_expanded && item.remark.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.remark,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LendingMetaPill extends StatelessWidget {
  const _LendingMetaPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

String _buildTimingLabel(LendingItem item) {
  if (item.isSettled) {
    return '已结清';
  }
  final dueDate = item.dueDate;
  if (dueDate != null) {
    return '${item.isOverdue ? '逾期' : '到期'} ${_formatMonthDay(dueDate)}';
  }
  return '进行中';
}

class _LendingProgressLine extends StatelessWidget {
  const _LendingProgressLine({required this.progress, required this.color});

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
      ],
    );
  }
}

class _LendingRecordsDialog extends ConsumerWidget {
  const _LendingRecordsDialog({required this.item});

  final LendingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('还款明细'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<LendingRecordItem>?>(
          future: ref.read(lendingRepositoryProvider).records(item.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final error = snapshot.error;
            if (error != null) {
              return _ErrorBanner(message: '还款记录加载失败');
            }
            final records = snapshot.data ?? const <LendingRecordItem>[];
            if (records.isEmpty) {
              return const _LendingDialogEmptyState(
                title: '还没有还款记录',
                message: '记录还款后显示',
                icon: Icons.receipt_long_outlined,
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemBuilder: (context, index) =>
                    _LendingRecordTile(record: records[index]),
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemCount: records.length,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('返回'),
        ),
      ],
    );
  }
}

class _LendingDialogEmptyState extends StatelessWidget {
  const _LendingDialogEmptyState({
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
    return PremiumSurface(
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
              child: Icon(icon, size: 20, color: colorScheme.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
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
    );
  }
}

class _LendingRecordTile extends StatelessWidget {
  const _LendingRecordTile({required this.record});

  final LendingRecordItem record;

  @override
  Widget build(BuildContext context) {
    final accountName = record.accountName;
    final meta = [
      _formatDate(record.recordDate),
      if (accountName != null && accountName.isNotEmpty) accountName,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(record.type.label),
      trailing: Text(
        _formatMoney(record.amount),
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        record.remark.isEmpty ? meta : '$meta · ${record.remark}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
  bool _showMoreDetails = false;
  late List<LedgerAttachment> _attachments;
  List<PendingAttachmentFile> _pendingAttachmentFiles = const [];

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
    _attachments = decodeAttachmentPaths(
      item?.evidence ?? '',
    ).map(LedgerAttachment.fromPath).toList();
    _showMoreDetails = false;
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
                          tooltip: null,
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
                      const DropdownMenuItem(value: null, child: Text('不关联账户')),
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
                  _CompactSwitchRow(
                    label: '同时调整账户余额',
                    value: _accountId != null && _createTransaction,
                    onChanged: _accountId == null
                        ? null
                        : (value) => setState(() => _createTransaction = value),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    key: const ValueKey('lending-more-details'),
                    onPressed: () {
                      setState(() => _showMoreDetails = !_showMoreDetails);
                    },
                    icon: Icon(
                      _showMoreDetails
                          ? Icons.remove_rounded
                          : Icons.add_rounded,
                    ),
                    tooltip: null,
                  ),
                ),
                if (_showMoreDetails) ...[
                  const SizedBox(height: 8),
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
                  TextFormField(
                    controller: _remarkController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '备注',
                      prefixIcon: Icon(Icons.notes_outlined),
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
        FilledButton(onPressed: _submit, child: const Text('保存记录')),
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
    final evidence = _encodeAttachmentEvidence(_attachments);

    if (_isEditing) {
      Navigator.of(context).pop(
        _LendingFormResult(
          request: UpdateLendingRequest(
            contactName: contactName,
            contactPhone: _phoneController.text.trim(),
            interestRate: interestRate,
            dueDate: dueDate,
            remark: _remarkController.text.trim(),
            evidence: evidence,
          ),
          attachments: _attachments,
          pendingFiles: _pendingAttachmentFiles,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _LendingFormResult(
        request: CreateLendingRequest(
          type: widget.type,
          contactName: contactName,
          contactPhone: _phoneController.text.trim(),
          principal: _parseAmount(_principalController.text),
          interestRate: interestRate,
          lendDate: _formatRequestDateTime(_lendDate),
          dueDate: dueDate,
          accountId: _accountId,
          remark: _remarkController.text.trim(),
          evidence: evidence,
          createTransaction: _accountId != null && _createTransaction,
        ),
        attachments: _attachments,
        pendingFiles: _pendingAttachmentFiles,
      ),
    );
  }
}

class _LendingFormResult<T> {
  const _LendingFormResult({
    required this.request,
    required this.attachments,
    required this.pendingFiles,
  });

  final T request;
  final List<LedgerAttachment> attachments;
  final List<PendingAttachmentFile> pendingFiles;
}

String _encodeAttachmentEvidence(List<LedgerAttachment> attachments) {
  return encodeAttachmentPaths(attachments.map((item) => item.path).toList());
}

UpdateLendingRequest _copyUpdateRequest(
  UpdateLendingRequest request, {
  required String evidence,
}) {
  return UpdateLendingRequest(
    contactName: request.contactName,
    contactPhone: request.contactPhone,
    contactRemark: request.contactRemark,
    interestRate: request.interestRate,
    dueDate: request.dueDate,
    remark: request.remark,
    evidence: evidence,
  );
}

UpdateLendingRequest _updateRequestFromCreate(
  CreateLendingRequest request, {
  required String evidence,
}) {
  return UpdateLendingRequest(
    contactName: request.contactName,
    contactPhone: request.contactPhone,
    contactRemark: request.contactRemark,
    interestRate: request.interestRate,
    dueDate: request.dueDate,
    remark: request.remark,
    evidence: evidence,
  );
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
                      const DropdownMenuItem(value: null, child: Text('不关联账户')),
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
                  _CompactSwitchRow(
                    label: '同时调整账户余额',
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

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}/${two(value.month)}/${two(value.day)}';
}

String _formatMonthDay(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.month)}/${two(value.day)}';
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
