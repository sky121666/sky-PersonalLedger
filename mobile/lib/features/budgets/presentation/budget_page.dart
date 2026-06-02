import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/ledger_icon.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
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
            tooltip: '刷新预算数据',
          ),
        ],
      ),
      body: dashboardState.when(
        loading: () => const AppLoadingView(message: '正在加载预算...'),
        error: (error, _) => _BudgetErrorView(
          message: error.toString(),
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
      message: '删除后将不再监控“${budget.categoryName}”的本月支出预算。',
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
    final memberName = budget.memberName.isEmpty ? '家庭成员' : budget.memberName;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除成员预算',
      message: '删除后将不再监控“$memberName”的该项预算。',
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
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }
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
    final categoryCount = budgetList.categoryBudgets.length;
    final memberHeaderIndex = categoryCount + 5;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AdaptivePageContainer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (errorMessage != null) ...[
              _MessagePanel(message: errorMessage!, isError: true),
              const SizedBox(height: 12),
            ],
            StaggeredEntrance(
              index: 0,
              child: _BudgetSummaryCard(budget: budgetList.totalBudget),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 1,
              child: _TotalBudgetCard(
                budget: budgetList.totalBudget,
                busy: busyAction == 'total',
                onEdit: onEditTotal,
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 2,
              child: _CategoryBudgetHeader(
                count: budgetList.categoryBudgets.length,
                availableCount: dashboard.availableExpenseCategories.length,
                onAdd: busyAction == null ? onAddCategory : null,
              ),
            ),
            const SizedBox(height: 8),
            if (budgetList.categoryBudgets.isEmpty)
              const StaggeredEntrance(
                index: 3,
                child: _EmptyCategoryBudgetCard(),
              )
            else
              for (final entry in budgetList.categoryBudgets.indexed) ...[
                StaggeredEntrance(
                  index: entry.$1 + 3,
                  child: _CategoryBudgetCard(
                    budget: entry.$2,
                    busy: busyAction == 'delete-${entry.$2.id}',
                    onDelete: () => onDeleteCategory(entry.$2),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            if (budgetList.memberBudgets.isNotEmpty) ...[
              const SizedBox(height: 16),
              StaggeredEntrance(
                index: memberHeaderIndex,
                child: _MemberBudgetHeader(
                  count: budgetList.memberBudgets.length,
                  availableMemberCount: familyMembers
                      .where((member) => member.isEnabled)
                      .length,
                  onAdd: busyAction == null ? onAddMember : null,
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              const SizedBox(height: 16),
              StaggeredEntrance(
                index: memberHeaderIndex,
                child: _MemberBudgetHeader(
                  count: 0,
                  availableMemberCount: familyMembers
                      .where((member) => member.isEnabled)
                      .length,
                  onAdd: busyAction == null ? onAddMember : null,
                ),
              ),
              const SizedBox(height: 8),
              StaggeredEntrance(
                index: memberHeaderIndex + 1,
                child: const _EmptyMemberBudgetCard(),
              ),
            ],
            for (final entry in budgetList.memberBudgets.indexed) ...[
              StaggeredEntrance(
                index: memberHeaderIndex + entry.$1 + 1,
                child: _MemberBudgetCard(
                  budget: entry.$2,
                  busy: busyAction == 'delete-${entry.$2.id}',
                  onDelete: () => onDeleteMember(entry.$2),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
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
  const _BudgetSummaryCard({required this.budget});

  final BudgetItem? budget;

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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                      '本月预算总览',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      totalBudget == null
                          ? '还未设置'
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
                  size: 78,
                  center: Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (totalBudget == null)
            Text(
              '未设置总预算',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            )
          else ...[
            Text(
              _formatMoney(remaining),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: remaining >= 0
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.error,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
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

class _TotalBudgetCard extends StatelessWidget {
  const _TotalBudgetCard({
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
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.asset,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _SectionTitle(
                    icon: Icons.account_balance_wallet_outlined,
                    title: '月度总预算',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onEdit,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined),
                  label: Text(totalBudget == null ? '设置' : '修改'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (totalBudget == null)
              const SizedBox.shrink()
            else
              _BudgetProgressBar(percentage: totalBudget.percentage),
          ],
        ),
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
        FilledButton.icon(
          onPressed: availableCount == 0 ? null : onAdd,
          icon: const Icon(Icons.add),
          label: const Text('添加'),
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
      child: AppEmptyView(title: '未设置分类预算', icon: Icons.track_changes_outlined),
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
                tooltip: '删除预算 ${budget.categoryName}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _BudgetProgressBar(percentage: budget.percentage),
          const SizedBox(height: 6),
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

class _MemberBudgetHeader extends StatelessWidget {
  const _MemberBudgetHeader({
    required this.count,
    required this.availableMemberCount,
    required this.onAdd,
  });

  final int count;
  final int availableMemberCount;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SectionTitle(
            icon: Icons.family_restroom_outlined,
            title: '成员',
            subtitle: '$count / ${count + availableMemberCount}',
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: availableMemberCount == 0 ? null : onAdd,
          icon: const Icon(Icons.add),
          label: const Text('添加'),
        ),
      ],
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
        title: '未设置成员预算',
        icon: Icons.family_restroom_outlined,
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
                tooltip: '删除成员预算 ${budget.memberName}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _BudgetProgressBar(percentage: budget.percentage),
          const SizedBox(height: 6),
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
      content: Form(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
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
