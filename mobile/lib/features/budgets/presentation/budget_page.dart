import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/ledger_icon.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../categories/data/category.dart';
import '../../family/data/family_repository.dart';
import '../data/budget_repository.dart';

class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key});

  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  String? _busyAction;
  String? _errorMessage;

  bool get _isBusy => _busyAction != null;

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(budgetDashboardProvider);
    final familyMembersState = ref.watch(familyMembersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('预算'),
        actions: [
          IconButton(
            onPressed: _isBusy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新预算',
          ),
        ],
      ),
      body: dashboardState.when(
        loading: () => const AppLoadingView(message: '正在加载预算...'),
        error: (error, _) => _BudgetErrorView(
          message: '预算加载失败',
          onRetry: _refresh,
          onRefresh: () => ref.refresh(budgetDashboardProvider.future),
        ),
        data: (dashboard) => _BudgetContent(
          dashboard: dashboard,
          busyAction: _busyAction,
          errorMessage: _errorMessage,
          onRefresh: () => ref.refresh(budgetDashboardProvider.future),
          onEditTotal: () =>
              _openTotalBudgetDialog(dashboard.budgetList.totalBudget),
          onAddCategory: () => _openCategoryBudgetDialog(dashboard),
          onAddMember: () => _openMemberBudgetDialog(
            dashboard,
            familyMembersState.valueOrNull ?? const [],
          ),
          onDeleteCategory: _deleteCategoryBudget,
          onDeleteMember: _deleteMemberBudget,
          familyMembers: familyMembersState.valueOrNull ?? const [],
        ),
      ),
    );
  }

  void _refresh() {
    setState(() => _errorMessage = null);
    ref.invalidate(budgetDashboardProvider);
  }

  Future<void> _openTotalBudgetDialog(BudgetItem? totalBudget) async {
    final result = await _showBudgetFormDialog(
      context: context,
      title: totalBudget == null ? '设置总预算' : '修改总预算',
      amount: totalBudget?.amount,
      alertThreshold: totalBudget?.alertThreshold ?? 80,
    );
    if (result == null || !mounted) {
      return;
    }

    await _runAction(
      action: 'total',
      successMessage: '总预算已保存',
      request: () => ref
          .read(budgetRepositoryProvider)
          .setTotalBudget(
            amount: result.amount,
            alertThreshold: result.alertThreshold,
          ),
    );
  }

  Future<void> _openCategoryBudgetDialog(BudgetDashboard dashboard) async {
    final categories = dashboard.availableExpenseCategories;
    if (categories.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('所有支出分类都已设置预算')));
      return;
    }

    final result = await _showBudgetFormDialog(
      context: context,
      title: '添加分类预算',
      categories: categories,
      selectedCategoryId: categories.first.id,
      alertThreshold: 80,
    );
    if (result == null || result.categoryId == null || !mounted) {
      return;
    }

    await _runAction(
      action: 'category',
      successMessage: '分类预算已添加',
      request: () => ref
          .read(budgetRepositoryProvider)
          .setCategoryBudget(
            categoryId: result.categoryId!,
            amount: result.amount,
            alertThreshold: result.alertThreshold,
          ),
    );
  }

  Future<void> _openMemberBudgetDialog(
    BudgetDashboard dashboard,
    List<FamilyMember> members,
  ) async {
    final enabledMembers = members.where((member) => member.isEnabled).toList();
    if (enabledMembers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先添加启用的家庭成员')));
      return;
    }

    final result = await _showBudgetFormDialog(
      context: context,
      title: '添加成员预算',
      categories: dashboard.expenseCategories,
      members: enabledMembers,
      selectedCategoryId: '',
      selectedMemberId: enabledMembers.first.id,
      allowTotalScope: true,
      alertThreshold: 80,
    );
    if (result == null || result.memberId == null || !mounted) {
      return;
    }

    await _runAction(
      action: 'member',
      successMessage: '成员预算已添加',
      request: () {
        final categoryId = result.categoryId;
        if (categoryId == null || categoryId.isEmpty) {
          return ref
              .read(budgetRepositoryProvider)
              .setTotalBudget(
                amount: result.amount,
                alertThreshold: result.alertThreshold,
                memberId: result.memberId,
              );
        }
        return ref
            .read(budgetRepositoryProvider)
            .setCategoryBudget(
              categoryId: categoryId,
              amount: result.amount,
              alertThreshold: result.alertThreshold,
              memberId: result.memberId,
            );
      },
    );
  }

  Future<void> _deleteCategoryBudget(BudgetItem budget) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除分类预算',
      message: '删除「${_budgetTargetName(budget.categoryName)}」？',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    await _runAction(
      action: 'delete-${budget.id}',
      successMessage: '分类预算已删除',
      request: () => ref.read(budgetRepositoryProvider).deleteBudget(budget.id),
    );
  }

  Future<void> _deleteMemberBudget(BudgetItem budget) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除成员预算',
      message: '删除「${_budgetTargetName(budget.memberName)}」？',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    await _runAction(
      action: 'delete-${budget.id}',
      successMessage: '成员预算已删除',
      request: () => ref.read(budgetRepositoryProvider).deleteBudget(budget.id),
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
      ref.invalidate(budgetDashboardProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = '预算保存失败');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }
}

String _budgetTargetName(String value) {
  final name = value.trim();
  return name.isEmpty ? '预算' : name;
}

class _BudgetContent extends StatelessWidget {
  const _BudgetContent({
    required this.dashboard,
    required this.busyAction,
    required this.errorMessage,
    required this.onRefresh,
    required this.onEditTotal,
    required this.onAddCategory,
    required this.onAddMember,
    required this.onDeleteCategory,
    required this.onDeleteMember,
    required this.familyMembers,
  });

  final BudgetDashboard dashboard;
  final String? busyAction;
  final String? errorMessage;
  final Future<void> Function() onRefresh;
  final VoidCallback onEditTotal;
  final VoidCallback onAddCategory;
  final VoidCallback onAddMember;
  final ValueChanged<BudgetItem> onDeleteCategory;
  final ValueChanged<BudgetItem> onDeleteMember;
  final List<FamilyMember> familyMembers;

  @override
  Widget build(BuildContext context) {
    final budgetList = dashboard.budgetList;
    final enabledMemberCount = familyMembers
        .where((member) => member.isEnabled)
        .length;
    final rows = _buildBudgetRows(
      errorMessage: errorMessage,
      budgetList: budgetList,
      availableCategoryCount: dashboard.availableExpenseCategories.length,
      enabledMemberCount: enabledMemberCount,
    );
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return _BudgetRowTile(
              row: row,
              busyAction: busyAction,
              onEditTotal: onEditTotal,
              onAddCategory: onAddCategory,
              onAddMember: onAddMember,
              onDeleteCategory: onDeleteCategory,
              onDeleteMember: onDeleteMember,
            );
          },
        ),
      ),
    );
  }
}

List<_BudgetRow> _buildBudgetRows({
  required String? errorMessage,
  required BudgetListResponse budgetList,
  required int availableCategoryCount,
  required int enabledMemberCount,
}) {
  return [
    if (errorMessage != null) ...[
      _BudgetRow.message(errorMessage),
      const _BudgetRow.gap(12),
    ],
    _BudgetRow.summary(budgetList.totalBudget),
    const _BudgetRow.gap(16),
    _BudgetRow.categoryHeader(
      count: budgetList.categoryBudgets.length,
      availableCount: availableCategoryCount,
    ),
    const _BudgetRow.gap(8),
    if (budgetList.categoryBudgets.isEmpty)
      const _BudgetRow.emptyCategory()
    else
      for (final budget in budgetList.categoryBudgets) ...[
        _BudgetRow.category(budget),
        const _BudgetRow.gap(8),
      ],
    const _BudgetRow.gap(16),
    _BudgetRow.memberPanel(
      budgets: budgetList.memberBudgets,
      count: budgetList.memberBudgets.length,
      availableCount: enabledMemberCount,
    ),
  ];
}

class _BudgetRowTile extends StatelessWidget {
  const _BudgetRowTile({
    required this.row,
    required this.busyAction,
    required this.onEditTotal,
    required this.onAddCategory,
    required this.onAddMember,
    required this.onDeleteCategory,
    required this.onDeleteMember,
  });

  final _BudgetRow row;
  final String? busyAction;
  final VoidCallback onEditTotal;
  final VoidCallback onAddCategory;
  final VoidCallback onAddMember;
  final ValueChanged<BudgetItem> onDeleteCategory;
  final ValueChanged<BudgetItem> onDeleteMember;

  @override
  Widget build(BuildContext context) {
    final child = switch (row.kind) {
      _BudgetRowKind.gap => SizedBox(height: row.height),
      _BudgetRowKind.message => _MessagePanel(
        message: row.message,
        isError: true,
      ),
      _BudgetRowKind.summary => _BudgetSummaryCard(
        budget: row.budget,
        busy: busyAction == 'total',
        onEdit: onEditTotal,
      ),
      _BudgetRowKind.categoryHeader => _CategoryBudgetHeader(
        count: row.count,
        availableCount: row.availableCount,
        onAdd: busyAction == null ? onAddCategory : null,
      ),
      _BudgetRowKind.emptyCategory => const _EmptyCategoryBudgetCard(),
      _BudgetRowKind.category => _CategoryBudgetCard(
        budget: row.budget!,
        busy: busyAction == 'delete-${row.budget!.id}',
        onDelete: () => onDeleteCategory(row.budget!),
      ),
      _BudgetRowKind.memberPanel => _MemberBudgetPanel(
        budgets: row.budgets,
        count: row.count,
        availableMemberCount: row.availableCount,
        busyAction: busyAction,
        onAdd: busyAction == null ? onAddMember : null,
        onDelete: onDeleteMember,
      ),
    };

    return child;
  }
}

enum _BudgetRowKind {
  gap,
  message,
  summary,
  categoryHeader,
  emptyCategory,
  category,
  memberPanel,
}

class _BudgetRow {
  const _BudgetRow.gap(this.height)
    : kind = _BudgetRowKind.gap,
      message = '',
      budget = null,
      budgets = const [],
      count = 0,
      availableCount = 0;

  const _BudgetRow.message(this.message)
    : kind = _BudgetRowKind.message,
      height = 0,
      budget = null,
      budgets = const [],
      count = 0,
      availableCount = 0;

  const _BudgetRow.summary(this.budget)
    : kind = _BudgetRowKind.summary,
      height = 0,
      message = '',
      budgets = const [],
      count = 0,
      availableCount = 0;

  const _BudgetRow.categoryHeader({
    required this.count,
    required this.availableCount,
  }) : kind = _BudgetRowKind.categoryHeader,
       height = 0,
       message = '',
       budget = null,
       budgets = const [];

  const _BudgetRow.emptyCategory()
    : kind = _BudgetRowKind.emptyCategory,
      height = 0,
      message = '',
      budget = null,
      budgets = const [],
      count = 0,
      availableCount = 0;

  const _BudgetRow.category(this.budget)
    : kind = _BudgetRowKind.category,
      height = 0,
      message = '',
      budgets = const [],
      count = 0,
      availableCount = 0;

  const _BudgetRow.memberPanel({
    required this.budgets,
    required this.count,
    required this.availableCount,
  }) : kind = _BudgetRowKind.memberPanel,
       height = 0,
       message = '',
       budget = null;

  final _BudgetRowKind kind;
  final double height;
  final String message;
  final BudgetItem? budget;
  final List<BudgetItem> budgets;
  final int count;
  final int availableCount;
}

class _BudgetErrorView extends StatelessWidget {
  const _BudgetErrorView({
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
      const _BudgetErrorRow(SizedBox(height: 48)),
      _BudgetErrorRow(AppErrorView(message: message, onRetry: onRetry), 0),
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

class _BudgetErrorRow {
  const _BudgetErrorRow(this.child, [this.bottomSpacing = 0]);

  final Widget child;
  final double bottomSpacing;
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError
            ? colorScheme.errorContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError
                  ? colorScheme.onErrorContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? colorScheme.onErrorContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({
    required this.budget,
    required this.busy,
    required this.onEdit,
  });

  final BudgetItem? budget;
  final bool busy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final totalBudget = budget;
    final used = totalBudget?.spent ?? 0;
    final amount = totalBudget?.amount ?? 0;
    final remaining = totalBudget?.remaining ?? 0;
    final percentage = totalBudget?.percentage ?? 0;
    final statusColor = totalBudget == null
        ? Theme.of(context).colorScheme.primary
        : _budgetStatusColor(context, percentage);

    return PremiumSurface(
      accentColor: statusColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                      '本月预算',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      totalBudget == null
                          ? '本月还没有总预算'
                          : _budgetStatusText(totalBudget),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (totalBudget != null)
                ProgressRing(
                  value: percentage / 100,
                  color: statusColor,
                  size: 64,
                  center: Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: busy ? null : onEdit,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(totalBudget == null ? Icons.add : Icons.edit),
                tooltip: totalBudget == null ? '设置总预算' : '修改总预算',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (totalBudget == null)
            Text(
              '本月还没有总预算',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            )
          else ...[
            Text(
              _formatMoney(remaining),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: remaining >= 0
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.error,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '已用 ${_formatMoney(used)} / ${_formatMoney(amount)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryBudgetHeader extends StatelessWidget {
  const _CategoryBudgetHeader({
    required this.count,
    required this.availableCount,
    required this.onAdd,
  });

  final int count;
  final int availableCount;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SectionTitle(
            icon: Icons.pie_chart_outline,
            title: '分类',
            subtitle: '$count / ${count + availableCount}',
          ),
        ),
        IconButton.filled(
          onPressed: availableCount == 0 ? null : onAdd,
          icon: const Icon(Icons.add),
          tooltip: '添加分类预算',
        ),
      ],
    );
  }
}

class _EmptyCategoryBudgetCard extends StatelessWidget {
  const _EmptyCategoryBudgetCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: AppEmptyView(title: '还没有分类预算', icon: Icons.track_changes_outlined),
    );
  }
}

class _CategoryBudgetCard extends StatelessWidget {
  const _CategoryBudgetCard({
    required this.budget,
    required this.busy,
    required this.onDelete,
  });

  final BudgetItem budget;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _budgetStatusColor(context, budget.percentage);
    final riskText = _budgetRiskText(budget);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                      budget.categoryName.isEmpty
                          ? '未命名分类'
                          : budget.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '已用 ${_formatMoney(budget.spent)} / ${_formatMoney(budget.amount)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${budget.percentage.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: busy ? null : onDelete,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                color: colorScheme.error,
                tooltip: '删除',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _BudgetProgressBar(percentage: budget.percentage),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  riskText ?? '剩余 ${_formatMoney(budget.remaining)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: riskText == null ? colorScheme.outline : statusColor,
                    fontWeight: riskText == null ? null : FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                '提醒 ${budget.alertThreshold}%',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyMemberBudgetCard extends StatelessWidget {
  const _EmptyMemberBudgetCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: AppEmptyView(
        title: '还没有成员预算',
        icon: Icons.family_restroom_outlined,
      ),
    );
  }
}

class _MemberBudgetPanel extends StatelessWidget {
  const _MemberBudgetPanel({
    required this.budgets,
    required this.count,
    required this.availableMemberCount,
    required this.busyAction,
    required this.onAdd,
    required this.onDelete,
  });

  final List<BudgetItem> budgets;
  final int count;
  final int availableMemberCount;
  final String? busyAction;
  final VoidCallback? onAdd;
  final ValueChanged<BudgetItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      key: const ValueKey('budget-member-panel'),
      accentColor: financeColors.asset,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: const ValueKey('budget-member-panel-toggle'),
        tilePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: Icon(
          Icons.family_restroom_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          '成员',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('$count / ${count + availableMemberCount}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              onPressed: availableMemberCount == 0 ? null : onAdd,
              icon: const Icon(Icons.add),
              tooltip: '添加成员预算',
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          if (budgets.isEmpty)
            const _EmptyMemberBudgetCard()
          else
            for (final budget in budgets)
              _MemberBudgetCard(
                budget: budget,
                busy: busyAction == 'delete-${budget.id}',
                onDelete: () => onDelete(budget),
              ),
        ],
      ),
    );
  }
}

class _MemberBudgetCard extends StatelessWidget {
  const _MemberBudgetCard({
    required this.budget,
    required this.busy,
    required this.onDelete,
  });

  final BudgetItem budget;
  final bool busy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final memberName = budget.memberName.isEmpty ? '家庭成员' : budget.memberName;
    final title = budget.categoryName.isEmpty
        ? memberName
        : '$memberName · ${budget.categoryName}';
    final statusColor = _budgetStatusColor(context, budget.percentage);
    final riskText = _budgetRiskText(budget);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '已用 ${_formatMoney(budget.spent)} / ${_formatMoney(budget.amount)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${budget.percentage.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: busy ? null : onDelete,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                color: colorScheme.error,
                tooltip: '删除',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _BudgetProgressBar(percentage: budget.percentage),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  riskText ?? '剩余 ${_formatMoney(budget.remaining)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: riskText == null ? colorScheme.outline : statusColor,
                    fontWeight: riskText == null ? null : FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                '提醒 ${budget.alertThreshold}%',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BudgetProgressBar extends StatelessWidget {
  const _BudgetProgressBar({required this.percentage});

  final double percentage;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        minHeight: 10,
        value: math.min(percentage, 100) / 100,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        color: _budgetStatusColor(context, percentage),
      ),
    );
  }
}

Future<_BudgetFormResult?> _showBudgetFormDialog({
  required BuildContext context,
  required String title,
  double? amount,
  int alertThreshold = 80,
  List<Category> categories = const [],
  String? selectedCategoryId,
  List<FamilyMember> members = const [],
  String? selectedMemberId,
  bool allowTotalScope = false,
}) {
  return showDialog<_BudgetFormResult>(
    context: context,
    builder: (context) => _BudgetFormDialog(
      title: title,
      amount: amount,
      alertThreshold: alertThreshold,
      categories: categories,
      selectedCategoryId: selectedCategoryId,
      members: members,
      selectedMemberId: selectedMemberId,
      allowTotalScope: allowTotalScope,
    ),
  );
}

class _BudgetFormDialog extends StatefulWidget {
  const _BudgetFormDialog({
    required this.title,
    required this.alertThreshold,
    required this.categories,
    required this.members,
    required this.allowTotalScope,
    this.amount,
    this.selectedCategoryId,
    this.selectedMemberId,
  });

  final String title;
  final double? amount;
  final int alertThreshold;
  final List<Category> categories;
  final List<FamilyMember> members;
  final bool allowTotalScope;
  final String? selectedCategoryId;
  final String? selectedMemberId;

  @override
  State<_BudgetFormDialog> createState() => _BudgetFormDialogState();
}

class _BudgetFormDialogState extends State<_BudgetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late int _selectedThreshold;
  String? _selectedCategory;
  String? _selectedMember;

  @override
  void initState() {
    super.initState();
    final amount = widget.amount;
    _amountController = TextEditingController(
      text: amount == null || amount == 0 ? '' : amount.toStringAsFixed(2),
    );
    _selectedThreshold = widget.alertThreshold;
    _selectedCategory = widget.selectedCategoryId;
    _selectedMember = widget.selectedMemberId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.members.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMember,
                    decoration: const InputDecoration(
                      labelText: '家庭成员',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final member in widget.members)
                        DropdownMenuItem(
                          value: member.id,
                          child: Text(member.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedMember = value);
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请选择家庭成员';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.categories.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: '支出分类',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      if (widget.allowTotalScope)
                        const DropdownMenuItem(value: '', child: Text('成员总预算')),
                      for (final category in widget.categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: LedgerIconLabel(
                            icon: category.icon,
                            label: category.name,
                            fallback: Icons.category_outlined,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedCategory = value);
                    },
                    validator: (value) {
                      if (widget.allowTotalScope && value == '') {
                        return null;
                      }
                      if (value == null || value.isEmpty) {
                        return '请选择支出分类';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '预算金额',
                    prefixText: '¥ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    if (amount == null || amount <= 0) {
                      return '请输入大于 0 的金额';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _selectedThreshold,
                  decoration: const InputDecoration(
                    labelText: '提醒阈值',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 50, child: Text('50%')),
                    DropdownMenuItem(value: 70, child: Text('70%')),
                    DropdownMenuItem(value: 80, child: Text('80%')),
                    DropdownMenuItem(value: 90, child: Text('90%')),
                    DropdownMenuItem(value: 100, child: Text('100%')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedThreshold = value);
                    }
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
        FilledButton(onPressed: _submit, child: const Text('保存预算')),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(
      _BudgetFormResult(
        amount: double.parse(_amountController.text.trim()),
        alertThreshold: _selectedThreshold,
        categoryId: _selectedCategory,
        memberId: _selectedMember,
      ),
    );
  }
}

class _BudgetFormResult {
  const _BudgetFormResult({
    required this.amount,
    required this.alertThreshold,
    this.categoryId,
    this.memberId,
  });

  final double amount;
  final int alertThreshold;
  final String? categoryId;
  final String? memberId;
}

String _formatMoney(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign¥${value.abs().toStringAsFixed(2)}';
}

Color _budgetStatusColor(BuildContext context, double percentage) {
  final financeColors = AppTheme.financeColors(context);
  if (percentage >= 100) {
    return Theme.of(context).colorScheme.error;
  }
  if (percentage >= 80) {
    return financeColors.warning;
  }
  return financeColors.income;
}

String _budgetStatusText(BudgetItem budget) {
  if (budget.isOverBudget) {
    return '已超出预算';
  }
  if (budget.isNearLimit) {
    return '接近预算上限';
  }
  return '控制良好';
}

String? _budgetRiskText(BudgetItem budget) {
  if (budget.isOverBudget) {
    return '已超出预算';
  }
  if (budget.isNearLimit) {
    return '接近预算上限';
  }
  return null;
}
