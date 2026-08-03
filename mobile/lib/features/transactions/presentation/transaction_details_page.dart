import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../core/formatters/money_formatter.dart';
import '../application/ledger_refresh.dart';
import '../application/transaction_list_controller.dart';
import '../data/transaction_models.dart';
import '../data/transaction_repository.dart';

enum _TransactionListAction { toggle, edit, delete }

class TransactionDetailsPage extends ConsumerStatefulWidget {
  const TransactionDetailsPage({super.key});

  @override
  ConsumerState<TransactionDetailsPage> createState() =>
      _TransactionDetailsPageState();
}

class _TransactionDetailsPageState
    extends ConsumerState<TransactionDetailsPage> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};

  /// 初始化列表滚动监听。
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  /// 释放列表页面资源。
  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 构建交易明细列表页。
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionListControllerProvider);
    final controller = ref.read(transactionListControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        leading: _selectedIds.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('transaction-clear-selection'),
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
                tooltip: '取消选择',
              ),
        title: Text(
          _selectedIds.isEmpty ? '明细' : '已选择 ${_selectedIds.length} 笔',
          style: _selectedIds.isEmpty
              ? Theme.of(context).textTheme.displaySmall
              : Theme.of(context).textTheme.titleLarge,
        ),
        actions: _selectedIds.isEmpty
            ? [
                IconButton(
                  key: const ValueKey('transaction-add'),
                  onPressed: () => context.push(AppRoutePaths.quickTransaction),
                  tooltip: '新增交易',
                  icon: const Icon(Icons.add),
                ),
              ]
            : [
                IconButton(
                  key: const ValueKey('transaction-select-all-current-page'),
                  onPressed: state.items.isEmpty
                      ? null
                      : () => _selectCurrentPage(state.items),
                  icon: const Icon(Icons.select_all),
                  tooltip: '全选当前页',
                ),
                IconButton(
                  key: const ValueKey('transaction-batch-delete'),
                  onPressed: _confirmBatchDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除选中交易',
                ),
              ],
      ),
      body: AdaptivePageContainer(
        child: _buildContent(state: state, controller: controller),
      ),
    );
  }

  Widget _buildContent({
    required TransactionListState state,
    required TransactionListController controller,
  }) {
    if (state.isLoading && state.items.isEmpty) {
      return const AppLoadingView(message: '加载交易中...');
    }

    if (state.errorMessage != null && state.items.isEmpty) {
      return AppErrorView(
        message: state.errorMessage!,
        onRetry: controller.refresh,
      );
    }

    if (state.items.isEmpty) {
      final rows = [
        for (final widget in _buildHeaderWidgets(state, controller))
          _TransactionDetailsRow(widget, 8),
        _TransactionDetailsRow(
          _TransactionEmptyState(
            title: state.hasActiveFilter ? '没有匹配结果' : '还没有明细',
            message: state.hasActiveFilter ? '清空筛选后查看全部' : '添加明细',
          ),
          0,
        ),
      ];
      return ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 12),
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
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          state.isLoadingMore ||
          !state.hasMore) {
        return;
      }
      if (_scrollController.position.maxScrollExtent <= 420) {
        controller.loadMore();
      }
    });

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: state.items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: _TransactionFilterWorkbench(
                state: state,
                controller: _searchController,
                onChanged: controller.updateKeyword,
                onClear: () {
                  _searchController.clear();
                  controller.clearFilters();
                },
                onFilterChanged: controller.updateFilters,
              ),
            );
          }
          if (index == state.items.length + 1) {
            return _LoadMoreIndicator(state: state);
          }
          final itemIndex = index - 1;
          final item = state.items[itemIndex];
          return _TransactionListTile(
            item: item,
            isFirst: itemIndex == 0,
            isLast: itemIndex == state.items.length - 1,
            selectionMode: _selectedIds.isNotEmpty,
            selected: _selectedIds.contains(item.id),
            onTap: () =>
                context.push(AppRoutePaths.quickTransaction, extra: item),
            onSelectionToggle: () => _toggleSelection(item.id),
            onDelete: () => _confirmDelete(item),
          );
        },
      ),
    );
  }

  List<Widget> _buildHeaderWidgets(
    TransactionListState state,
    TransactionListController controller,
  ) {
    return [
      _TransactionFilterWorkbench(
        state: state,
        controller: _searchController,
        onChanged: controller.updateKeyword,
        onClear: () {
          _searchController.clear();
          controller.clearFilters();
        },
        onFilterChanged: controller.updateFilters,
      ),
    ];
  }

  Future<void> _confirmDelete(TransactionItem item) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除交易',
      message: '删除「${item.displayTitle}」？',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await ref
          .read(transactionListControllerProvider.notifier)
          .deleteTransaction(item.id);
      ref.invalidateLedgerMutationViews();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('交易已删除')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('交易删除失败')));
      }
    }
  }

  Future<void> _confirmBatchDelete() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) {
      return;
    }

    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除选中交易',
      message: '删除 ${ids.length} 笔交易？',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    try {
      await ref
          .read(transactionListControllerProvider.notifier)
          .deleteTransactions(ids);
      ref.invalidateLedgerMutationViews();
      if (mounted) {
        setState(_selectedIds.clear);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已删 ${ids.length} 笔')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('交易删除失败')));
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _selectCurrentPage(List<TransactionItem> items) {
    setState(() {
      _selectedIds.addAll(items.map((item) => item.id));
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 420) {
      ref.read(transactionListControllerProvider.notifier).loadMore();
    }
  }
}

class _TransactionDetailsRow {
  const _TransactionDetailsRow(this.child, [this.bottomSpacing = 8]);

  final Widget child;
  final double bottomSpacing;
}

class _TransactionFilterWorkbench extends ConsumerStatefulWidget {
  const _TransactionFilterWorkbench({
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilterChanged,
  });

  final TransactionListState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Future<void> Function({
    TransactionType? type,
    String? accountId,
    String? categoryId,
    bool clearType,
    bool clearAccount,
    bool clearCategory,
  })
  onFilterChanged;

  @override
  ConsumerState<_TransactionFilterWorkbench> createState() =>
      _TransactionFilterWorkbenchState();
}

class _TransactionFilterWorkbenchState
    extends ConsumerState<_TransactionFilterWorkbench> {
  late final Future<List<LedgerAccount>> _accountsFuture;

  @override
  void initState() {
    super.initState();
    _accountsFuture = ref.read(transactionRepositoryProvider).listAccounts();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeCount = [
      widget.state.keyword.trim().isNotEmpty,
      widget.state.type != null,
      widget.state.accountId != null && widget.state.accountId!.isNotEmpty,
      widget.state.categoryId != null && widget.state.categoryId!.isNotEmpty,
    ].where((active) => active).length;
    return PremiumSurface(
      key: const ValueKey('transaction-filter-workbench'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      radius: 16,
      accentColor: colorScheme.primary,
      child: FutureBuilder<List<LedgerAccount>>(
        future: _accountsFuture,
        builder: (context, snapshot) {
          final accounts = snapshot.data ?? const <LedgerAccount>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        key: const ValueKey('transaction-search'),
                        controller: widget.controller,
                        minLines: 1,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 13,
                          ),
                          hintText: widget.state.hasActiveFilter
                              ? '$activeCount 项筛选 · ${widget.state.items.length}/${widget.state.total}'
                              : '搜索明细',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: widget.controller.text.isEmpty
                              ? widget.state.hasActiveFilter
                                    ? IconButton(
                                        key: const ValueKey(
                                          'transaction-filter-clear',
                                        ),
                                        onPressed: widget.onClear,
                                        icon: const Icon(
                                          Icons.filter_alt_off_outlined,
                                        ),
                                        tooltip: '清空筛选',
                                      )
                                    : null
                              : IconButton(
                                  key: const ValueKey(
                                    'transaction-filter-clear',
                                  ),
                                  onPressed: widget.onClear,
                                  icon: const Icon(Icons.close),
                                  tooltip: '清空搜索',
                                ),
                        ),
                        onChanged: widget.onChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TransactionFilterBadgeButton(
                    activeCount: activeCount,
                    onPressed: () => _openFilterSheet(accounts),
                  ),
                ],
              ),
              if (widget.state.hasActiveFilter) ...[
                const SizedBox(height: 4),
                _TransactionActiveFiltersSummary(
                  state: widget.state,
                  onClear: widget.onClear,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openFilterSheet(List<LedgerAccount> accounts) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _TransactionFilterControls(
            state: widget.state,
            accounts: accounts,
            onChanged: widget.onFilterChanged,
            closeOnSelect: true,
          ),
        ),
      ),
    );
  }
}

class _TransactionEmptyState extends StatelessWidget {
  const _TransactionEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      child: PremiumSurface(
        padding: EdgeInsets.zero,
        radius: 14,
        accentColor: colorScheme.primary,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
              child: IconBadge(
                icon: Icons.receipt_long_outlined,
                color: colorScheme.primary,
                size: 32,
                iconSize: 17,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
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
      ),
    );
  }
}

class _TransactionFilterControls extends StatelessWidget {
  const _TransactionFilterControls({
    required this.state,
    required this.accounts,
    required this.onChanged,
    this.closeOnSelect = false,
  });

  final TransactionListState state;
  final List<LedgerAccount> accounts;
  final Future<void> Function({
    TransactionType? type,
    String? accountId,
    String? categoryId,
    bool clearType,
    bool clearAccount,
    bool clearCategory,
  })
  onChanged;
  final bool closeOnSelect;

  /// 构建交易筛选栏。
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              avatar: const Icon(Icons.all_inclusive_rounded, size: 18),
              selected: state.type == null,
              label: const Text('全部'),
              onSelected: (_) {
                onChanged(clearType: true);
                if (closeOnSelect) {
                  Navigator.of(context).pop();
                }
              },
            ),
            for (final type in TransactionType.values)
              FilterChip(
                avatar: Icon(_typeIcon(type), size: 18),
                selected: state.type == type,
                label: Text(type.label),
                onSelected: (_) {
                  onChanged(type: type);
                  if (closeOnSelect) {
                    Navigator.of(context).pop();
                  }
                },
              ),
          ],
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return DropdownMenu<String>(
                width: constraints.maxWidth,
                initialSelection: state.accountId ?? '',
                leadingIcon: const Icon(Icons.account_balance_wallet_outlined),
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: '', label: '全部'),
                  ...accounts.map(
                    (account) => DropdownMenuEntry(
                      value: account.id,
                      label: account.name,
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == null || value.isEmpty) {
                    onChanged(clearAccount: true);
                  } else {
                    onChanged(accountId: value);
                  }
                  if (closeOnSelect) {
                    Navigator.of(context).pop();
                  }
                },
              );
            },
          ),
        ],
      ],
    );
  }
}

class _TransactionFilterBadgeButton extends StatelessWidget {
  const _TransactionFilterBadgeButton({
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox.square(
          dimension: 48,
          child: IconButton(
            key: const ValueKey('transaction-filter-toggle'),
            onPressed: onPressed,
            tooltip: '筛选明细',
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: Icon(
              activeCount == 0 ? Icons.filter_alt_outlined : Icons.filter_alt,
            ),
            color: activeCount == 0
                ? colorScheme.onSurfaceVariant
                : colorScheme.primary,
          ),
        ),
        if (activeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.error,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$activeCount',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onError,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TransactionActiveFiltersSummary extends StatelessWidget {
  const _TransactionActiveFiltersSummary({
    required this.state,
    required this.onClear,
  });

  final TransactionListState state;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tags = <String>[];

    if (state.keyword.trim().isNotEmpty) {
      tags.add('关键字');
    }
    if (state.type != null) {
      tags.add(state.type!.label);
    }
    if (state.accountId != null && state.accountId!.isNotEmpty) {
      tags.add('账户');
    }
    if (state.categoryId != null && state.categoryId!.isNotEmpty) {
      tags.add('分类');
    }

    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final tag in tags) _TransactionActiveFilterChip(label: tag),
        SizedBox.square(
          key: const ValueKey('transaction-filter-summary-clear'),
          dimension: 36,
          child: IconButton(
            onPressed: onClear,
            padding: EdgeInsets.zero,
            iconSize: 18,
            tooltip: '清空筛选',
            icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _TransactionActiveFilterChip extends StatelessWidget {
  const _TransactionActiveFilterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

IconData _typeIcon(TransactionType type) {
  return switch (type) {
    TransactionType.income => Icons.south_west,
    TransactionType.expense => Icons.north_east,
    TransactionType.transfer => Icons.swap_horiz,
  };
}

class _TransactionListTile extends ConsumerStatefulWidget {
  const _TransactionListTile({
    required this.item,
    required this.isFirst,
    required this.isLast,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onSelectionToggle,
    required this.onDelete,
  });

  final TransactionItem item;
  final bool isFirst;
  final bool isLast;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSelectionToggle;
  final VoidCallback onDelete;

  @override
  ConsumerState<_TransactionListTile> createState() =>
      _TransactionListTileState();
}

class _TransactionListTileState extends ConsumerState<_TransactionListTile> {
  bool _expanded = false;

  PopupMenuItem<_TransactionListAction> _menuItem({
    required _TransactionListAction action,
    required String keySuffix,
    required String title,
    required IconData icon,
    bool enabled = true,
  }) {
    return PopupMenuItem<_TransactionListAction>(
      value: action,
      enabled: enabled,
      key: ValueKey('transaction-action-$keySuffix-${widget.item.id}'),
      child: ListTile(
        leading: Icon(icon, size: 18),
        title: Text(title),
        contentPadding: EdgeInsets.zero,
        minLeadingWidth: 0,
        dense: true,
      ),
    );
  }

  void _onMenuSelected(_TransactionListAction action) {
    switch (action) {
      case _TransactionListAction.toggle:
        _toggleExpanded();
        return;
      case _TransactionListAction.edit:
        if (!widget.item.isManagedTransaction) {
          widget.onTap();
        }
        return;
      case _TransactionListAction.delete:
        widget.onDelete();
        return;
    }
  }

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  void _handlePrimaryTap() {
    if (widget.item.isManagedTransaction) {
      _toggleExpanded();
      return;
    }
    widget.onTap();
  }

  /// 构建单条交易列表项。
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selectionMode = widget.selectionMode;
    final selected = widget.selected;
    final onSelectionToggle = widget.onSelectionToggle;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final isLending = item.isLendingLinked;
    final amountColor = isLending
        ? colorScheme.tertiary
        : switch (item.type) {
            TransactionType.income => financeColors.income,
            TransactionType.expense => colorScheme.error,
            TransactionType.transfer => colorScheme.primary,
          };
    final prefix = switch (item.type) {
      TransactionType.income => '+',
      TransactionType.expense => '-',
      TransactionType.transfer => '',
    };
    final accountLabel = item.type == TransactionType.transfer
        ? '${item.account?.name ?? '转出账户'} → ${item.toAccount?.name ?? '转入账户'}'
        : item.account?.name ?? '账户';
    final title = isLending ? '借贷往来' : item.displayTitle;
    final subtitle = item.type == TransactionType.transfer
        ? accountLabel
        : '$accountLabel · ${_formatDateTime(item.transactionDate)}';
    final remark = cleanTransactionDisplayRemark(item.remark);
    final semanticTitle = isLending
        ? (remark.isNotEmpty ? remark : accountLabel)
        : title;
    final groupedRadius = Radius.circular(AppTheme.surfaceRadius);
    final groupedBorderRadius = BorderRadius.vertical(
      top: widget.isFirst ? groupedRadius : Radius.zero,
      bottom: widget.isLast ? groupedRadius : Radius.zero,
    );

    return Semantics(
      label:
          '${isLending ? '借贷往来' : item.typeLabel}，$semanticTitle，金额$prefix${formatMoney(item.amount)}，$subtitle',
      selected: selected,
      child: Padding(
        key: ValueKey('transaction-item-${item.id}'),
        padding: EdgeInsets.zero,
        child: ClipRRect(
          key: ValueKey('transaction-group-clip-${item.id}'),
          borderRadius: groupedBorderRadius,
          child: PremiumSurface(
            accentColor: selected ? colorScheme.primary : amountColor,
            padding: EdgeInsets.zero,
            radius: 0,
            child: Column(
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: groupedBorderRadius,
                    onTap: selectionMode
                        ? onSelectionToggle
                        : _handlePrimaryTap,
                    onLongPress: onSelectionToggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(11, 8, 4, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (selectionMode)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Semantics(
                                key: ValueKey(
                                  'transaction-select-semantics-${item.id}',
                                ),
                                label: '选择交易 $title',
                                checked: selected,
                                enabled: true,
                                child: Checkbox(
                                  key: ValueKey(
                                    'transaction-select-${item.id}',
                                  ),
                                  value: selected,
                                  onChanged: (_) => onSelectionToggle(),
                                ),
                              ),
                            )
                          else
                            IconBadge(
                              icon: isLending
                                  ? Icons.handshake_outlined
                                  : _typeIcon(item.type),
                              color: amountColor,
                              size: 32,
                              iconSize: 17,
                            ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: ExcludeSemantics(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '$prefix${formatMoney(item.amount)}',
                                        key: ValueKey(
                                          'transaction-amount-${item.id}',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: amountColor,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  if (_expanded && remark.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      remark,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                  if (_expanded && item.tags.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: item.tags
                                          .map(
                                            (tag) => _TransactionTagChip(
                                              label: tag,
                                              color: amountColor,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (!selectionMode)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<_TransactionListAction>(
                                  key: ValueKey(
                                    'transaction-more-menu-${item.id}',
                                  ),
                                  icon: const Icon(
                                    Icons.more_horiz,
                                    size: 20,
                                    semanticLabel: '交易操作',
                                  ),
                                  tooltip: '交易操作',
                                  onSelected: _onMenuSelected,
                                  itemBuilder: (context) => [
                                    _menuItem(
                                      action: _TransactionListAction.toggle,
                                      keySuffix: 'toggle',
                                      title: _expanded ? '收起' : '详情',
                                      icon: _expanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                    ),
                                    if (!item.isManagedTransaction)
                                      _menuItem(
                                        action: _TransactionListAction.edit,
                                        keySuffix: 'edit',
                                        title: '编辑',
                                        icon: Icons.edit_outlined,
                                      ),
                                    _menuItem(
                                      action: _TransactionListAction.delete,
                                      keySuffix: 'delete',
                                      title: '删除',
                                      icon: Icons.delete_outline,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!widget.isLast)
                  const Divider(height: 1, indent: 52, endIndent: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(TransactionType type) {
    return switch (type) {
      TransactionType.income => Icons.south_west,
      TransactionType.expense => Icons.north_east,
      TransactionType.transfer => Icons.swap_horiz,
    };
  }
}

class _TransactionTagChip extends StatelessWidget {
  const _TransactionTagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator({required this.state});

  final TransactionListState state;

  /// 构建分页加载状态提示。
  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!state.hasMore) {
      return const SizedBox(height: 8);
    }
    return const SizedBox(height: 56);
  }
}

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}
