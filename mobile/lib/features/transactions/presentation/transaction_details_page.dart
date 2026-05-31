import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../application/ledger_refresh.dart';
import '../application/transaction_list_controller.dart';
import '../data/transaction_models.dart';
import '../data/transaction_repository.dart';

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
        leading: _selectedIds.isEmpty
            ? null
            : IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close),
                tooltip: '退出选择',
              ),
        title: Text(
          _selectedIds.isEmpty ? '明细' : '已选择 ${_selectedIds.length} 笔',
        ),
        actions: _selectedIds.isEmpty
            ? [
                IconButton(
                  onPressed: () => context.push(AppRoutePaths.quickTransaction),
                  icon: const Icon(Icons.add),
                  tooltip: '记一笔',
                ),
              ]
            : [
                IconButton(
                  onPressed: state.items.isEmpty
                      ? null
                      : () => _selectCurrentPage(state.items),
                  icon: const Icon(Icons.select_all),
                  tooltip: '全选当前页',
                ),
                IconButton(
                  onPressed: _confirmBatchDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除选中交易',
                ),
              ],
      ),
      body: AdaptivePageContainer(
        child: Column(
          children: [
            _TransactionSearchBar(
              controller: _searchController,
              onChanged: controller.updateKeyword,
              onClear: () {
                _searchController.clear();
                controller.updateKeyword('');
              },
            ),
            const SizedBox(height: 10),
            _TransactionFilterBar(
              state: state,
              onChanged: controller.updateFilters,
              onClear: () {
                _searchController.clear();
                controller.clearFilters();
              },
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody(state, controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    TransactionListState state,
    TransactionListController controller,
  ) {
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
      return AppEmptyView(
        title: state.hasActiveFilter ? '没有匹配的交易' : '暂无交易明细',
        message: state.hasActiveFilter ? '调整筛选条件后再试。' : '点击“记一笔”添加第一条收支记录。',
        icon: Icons.receipt_long_outlined,
        action: FilledButton.tonal(
          onPressed: () => context.push(AppRoutePaths.quickTransaction),
          child: const Text('去记一笔'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: state.items.length + 1,
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return _LoadMoreIndicator(state: state);
          }
          final item = state.items[index];
          return _TransactionListTile(
            item: item,
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

  Future<void> _confirmDelete(TransactionItem item) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除交易',
      message: '确定删除「${item.displayTitle}」这笔交易吗？删除后账户余额会同步回滚。',
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
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
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
      message: '确定删除选中的 ${ids.length} 笔交易吗？删除后账户余额会同步回滚。',
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
        ).showSnackBar(SnackBar(content: Text('已删除 ${ids.length} 笔交易')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('批量删除失败：$error')));
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

class _TransactionSearchBar extends StatelessWidget {
  const _TransactionSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// 构建交易搜索输入框。
  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      accentColor: Theme.of(context).colorScheme.primary,
      child: TextField(
        key: const ValueKey('transaction-search'),
        controller: controller,
        decoration: InputDecoration(
          hintText: '搜索备注',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  tooltip: '清空搜索',
                ),
          border: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _TransactionFilterBar extends ConsumerWidget {
  const _TransactionFilterBar({
    required this.state,
    required this.onChanged,
    required this.onClear,
  });

  final TransactionListState state;
  final Future<void> Function({
    TransactionType? type,
    String? accountId,
    String? categoryId,
    bool clearType,
    bool clearAccount,
    bool clearCategory,
  })
  onChanged;
  final VoidCallback onClear;

  /// 构建交易筛选栏。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<LedgerAccount>>(
      future: ref.read(transactionRepositoryProvider).listAccounts(),
      builder: (context, snapshot) {
        final accounts = snapshot.data ?? const <LedgerAccount>[];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                selected: state.type == null,
                label: const Text('全部类型'),
                onSelected: (_) => onChanged(clearType: true),
              ),
              const SizedBox(width: 8),
              for (final type in TransactionType.values) ...[
                FilterChip(
                  selected: state.type == type,
                  label: Text(type.label),
                  onSelected: (_) => onChanged(type: type),
                ),
                const SizedBox(width: 8),
              ],
              if (accounts.isNotEmpty)
                DropdownMenu<String>(
                  width: 150,
                  initialSelection: state.accountId ?? '',
                  dropdownMenuEntries: [
                    const DropdownMenuEntry(value: '', label: '全部账户'),
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
                  },
                ),
              if (state.hasActiveFilter) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('清空'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TransactionListTile extends StatelessWidget {
  const _TransactionListTile({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onSelectionToggle,
    required this.onDelete,
  });

  final TransactionItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSelectionToggle;
  final VoidCallback onDelete;

  /// 构建单条交易列表项。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final amountColor = switch (item.type) {
      TransactionType.income => financeColors.income,
      TransactionType.expense => colorScheme.error,
      TransactionType.transfer => colorScheme.primary,
    };
    final prefix = switch (item.type) {
      TransactionType.income => '+',
      TransactionType.expense => '-',
      TransactionType.transfer => '',
    };

    return Padding(
      key: ValueKey('transaction-item-${item.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumSurface(
        accentColor: selected ? colorScheme.primary : amountColor,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.surfaceRadius),
            onTap: selectionMode ? onSelectionToggle : onTap,
            onLongPress: onSelectionToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Checkbox(
                        key: ValueKey('transaction-select-${item.id}'),
                        value: selected,
                        onChanged: (_) => onSelectionToggle(),
                      ),
                    )
                  else
                    IconBadge(
                      icon: _typeIcon(item.type),
                      color: amountColor,
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
                            Expanded(
                              child: Text(
                                item.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$prefix¥${item.amount.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: amountColor,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _formatDateTime(item.transactionDate),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.outline),
                        ),
                        if (item.remark.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.remark,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (item.tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
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
                  if (!selectionMode)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          onTap();
                        } else if (value == 'delete') {
                          onDelete();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                ],
              ),
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
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text('没有更多了', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
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
