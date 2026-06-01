import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('借贷往来'),
        actions: [
          IconButton(
            onPressed: _isBusy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新借贷记录',
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
                StaggeredEntrance(
                  index: 0,
                  child: _SummarySection(summary: dashboard.summary),
                ),
                const SizedBox(height: 12),
                StaggeredEntrance(
                  index: 1,
                  child: _QuickActions(
                    busy: _isBusy,
                    onCreate: (type) =>
                        _openCreateForm(type, dashboard.accounts),
                  ),
                ),
                const SizedBox(height: 10),
                StaggeredEntrance(
                  index: 2,
                  child: SegmentedButton<_LendingTab>(
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
                ),
                const SizedBox(height: 12),
                _LendingList(
                  lendings: _itemsForTab(dashboard),
                  tab: _tab,
                  startIndex: 6,
                  busyAction: _busyAction,
                  onEdit: (item) => _openEditForm(item, dashboard.accounts),
                  onDelete: _deleteLending,
                  onRepay: (item) =>
                      _openRepaymentDialog(item, dashboard.activeAccounts),
                  onRecords: _openRecordsDialog,
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
          throw const FormatException('借贷创建响应为空，无法上传附件');
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
      message: '删除后该笔借贷和还款记录将无法恢复，已生成的账本交易会保留。',
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
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final netColor = summary.netLending >= 0
        ? financeColors.income
        : colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PremiumSurface(
          accentColor: netColor,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: Icons.handshake_outlined,
                    color: netColor,
                    size: 44,
                    iconSize: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '往来金额',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatSignedMoney(summary.netLending),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: netColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  MetricPill(
                    label: '借出中',
                    value: '${summary.activeLendOut} 笔',
                    icon: Icons.north_east,
                    color: financeColors.income,
                  ),
                  MetricPill(
                    label: '借入中',
                    value: '${summary.activeBorrowIn} 笔',
                    icon: Icons.south_west,
                    color: financeColors.asset,
                  ),
                  MetricPill(
                    label: '应收',
                    value: _formatMoney(summary.totalReceivable),
                    icon: Icons.account_balance_wallet_outlined,
                    color: netColor,
                  ),
                  MetricPill(
                    label: '应付',
                    value: _formatMoney(summary.totalPayable),
                    icon: Icons.credit_card_outlined,
                    color: colorScheme.error,
                  ),
                  MetricPill(
                    label: '已结清',
                    value:
                        '${summary.settledLendOut + summary.settledBorrowIn} 笔',
                    icon: Icons.check_circle_outline,
                    color: colorScheme.outline,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
    required this.startIndex,
    required this.busyAction,
    required this.onEdit,
    required this.onDelete,
    required this.onRepay,
    required this.onRecords,
  });

  final List<LendingItem> lendings;
  final _LendingTab tab;
  final int startIndex;
  final String? busyAction;
  final ValueChanged<LendingItem> onEdit;
  final ValueChanged<LendingItem> onDelete;
  final ValueChanged<LendingItem> onRepay;
  final ValueChanged<LendingItem> onRecords;

  @override
  Widget build(BuildContext context) {
    if (lendings.isEmpty) {
      return StaggeredEntrance(
        index: startIndex,
        child: PremiumSurface(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
          child: AppEmptyView(
            title: switch (tab) {
              _LendingTab.lendOut => '暂无借出记录',
              _LendingTab.borrowIn => '暂无借入记录',
              _LendingTab.settled => '暂无已结清记录',
            },
            icon: Icons.handshake_outlined,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final entry in lendings.indexed) ...[
          StaggeredEntrance(
            index: startIndex + entry.$1,
            child: _LendingCard(
              item: entry.$2,
              busy: busyAction?.endsWith(entry.$2.id) ?? false,
              onEdit: () => onEdit(entry.$2),
              onDelete: () => onDelete(entry.$2),
              onRepay: () => onRepay(entry.$2),
              onRecords: () => onRecords(entry.$2),
            ),
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
    required this.onRecords,
  });

  final LendingItem item;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRepay;
  final VoidCallback onRecords;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final accent = item.type == LendingType.lendOut
        ? financeColors.income
        : financeColors.asset;
    final hasEvidence = item.evidence.trim().isNotEmpty;
    final dueLabel = item.dueDate == null ? '未设到期' : _formatDate(item.dueDate!);
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
    return Semantics(
      label:
          '${item.contactName}，${item.typeLabel}，本金${_formatMoney(item.principal)}，剩余${_formatMoney(item.currentBalance)}，$statusLabel',
      button: false,
      child: PremiumSurface(
        key: ValueKey('lending-card-${item.id}'),
        accentColor: accent,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ContactBadge(
                  name: item.contactName,
                  color: accent,
                  type: item.type,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.contactName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _LendingMetaPill(
                            icon: item.type == LendingType.lendOut
                                ? Icons.north_east_rounded
                                : Icons.south_west_rounded,
                            label: item.typeLabel,
                            color: accent,
                          ),
                          _LendingMetaPill(
                            icon: item.isOverdue
                                ? Icons.warning_amber_outlined
                                : Icons.event_available_outlined,
                            label: dueLabel,
                            color: item.isOverdue
                                ? financeColors.expense
                                : colorScheme.primary,
                          ),
                          _LendingMetaPill(
                            icon: hasEvidence
                                ? Icons.verified_user_outlined
                                : Icons.attach_file_outlined,
                            label: hasEvidence ? '凭证已留存' : '待补凭证',
                            color: hasEvidence
                                ? financeColors.income
                                : colorScheme.tertiary,
                          ),
                        ],
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
                  Wrap(
                    spacing: 2,
                    children: [
                      if (!item.isSettled)
                        IconButton.filledTonal(
                          onPressed: onRepay,
                          icon: const Icon(Icons.payments_outlined),
                          tooltip: '记录还款 ${item.contactName}',
                        ),
                      IconButton.filledTonal(
                        onPressed: onRecords,
                        icon: const Icon(Icons.receipt_long_outlined),
                        tooltip: '查看还款记录 ${item.contactName}',
                      ),
                      IconButton.filledTonal(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑借贷记录 ${item.contactName}',
                      ),
                      IconButton.filledTonal(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除借贷记录 ${item.contactName}',
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LendingMetaPill(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '本金 ${_formatMoney(item.principal)}',
                  color: accent,
                ),
                _LendingMetaPill(
                  icon: Icons.payments_outlined,
                  label: '剩余 ${_formatMoney(item.currentBalance)}',
                  color: statusColor,
                ),
                _LendingMetaPill(
                  icon: Icons.done_all_outlined,
                  label: '已还 ${_formatMoney(item.totalRepaid)}',
                  color: colorScheme.tertiary,
                ),
                _LendingMetaPill(
                  icon: Icons.stacked_line_chart_outlined,
                  label: '进度 ${item.progress.toStringAsFixed(0)}%',
                  color: accent,
                ),
                if (item.accountName != null && item.accountName!.isNotEmpty)
                  _LendingMetaPill(
                    icon: Icons.account_balance_wallet_outlined,
                    label: item.accountName!,
                    color: colorScheme.primary,
                  ),
                _LendingMetaPill(
                  icon: Icons.calendar_today_outlined,
                  label: _formatDate(item.lendDate),
                  color: colorScheme.outline,
                ),
              ],
            ),
            if (item.remark.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    colorScheme.secondary.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.16
                          : 0.07,
                    ),
                    colorScheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colorScheme.secondary.withValues(alpha: 0.14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notes_outlined,
                          size: 16,
                          color: colorScheme.secondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '备注',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.remark,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContactBadge extends StatelessWidget {
  const _ContactBadge({
    required this.name,
    required this.color,
    required this.type,
  });

  final String name;
  final Color color;
  final LendingType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            _avatarText(name),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Icon(
              type == LendingType.lendOut
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded,
              size: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LendingMetaPill extends StatelessWidget {
  const _LendingMetaPill({
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
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.17
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LendingRecordsDialog extends ConsumerWidget {
  const _LendingRecordsDialog({required this.item});

  final LendingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('还款记录'),
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
              return _ErrorBanner(message: error.toString());
            }
            final records = snapshot.data ?? const <LendingRecordItem>[];
            if (records.isEmpty) {
              return const AppEmptyView(
                title: '暂无还款记录',
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
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _LendingRecordTile extends StatelessWidget {
  const _LendingRecordTile({required this.record});

  final LendingRecordItem record;

  @override
  Widget build(BuildContext context) {
    final accountName = record.accountName;
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_formatDate(record.recordDate)),
          if (accountName != null && accountName.isNotEmpty) Text(accountName),
          if (record.remark.isNotEmpty) Text(record.remark),
        ],
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
