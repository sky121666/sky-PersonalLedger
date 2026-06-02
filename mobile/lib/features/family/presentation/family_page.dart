import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../budgets/data/budget_repository.dart';
import '../data/family_repository.dart';

class FamilyPage extends ConsumerStatefulWidget {
  const FamilyPage({super.key});

  @override
  ConsumerState<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends ConsumerState<FamilyPage> {
  var _submittingMember = false;

  void _invalidateFamilyData() {
    ref
      ..invalidate(familyMembersProvider)
      ..invalidate(familySummaryProvider)
      ..invalidate(familyStatisticsProvider)
      ..invalidate(memberBudgetsProvider);
  }

  Future<void> _showMemberSheet([FamilyMember? member]) async {
    final request = await showModalBottomSheet<FamilyMemberRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _FamilyMemberFormSheet(member: member),
    );
    if (request == null || !mounted) {
      return;
    }

    setState(() => _submittingMember = true);
    try {
      final repository = ref.read(familyRepositoryProvider);
      if (member == null) {
        await repository.createMember(request);
      } else {
        await repository.updateMember(member.id, request);
      }
      _invalidateFamilyData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(member == null ? '成员已添加' : '成员已保存')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submittingMember = false);
      }
    }
  }

  Future<void> _disableMember(FamilyMember member) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '停用成员',
      message: '停用后历史交易归属会保留。',
      confirmText: '停用',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _submittingMember = true);
    try {
      await ref.read(familyRepositoryProvider).deleteMember(member.id);
      _invalidateFamilyData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成员已停用')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submittingMember = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersState = ref.watch(familyMembersProvider);
    final summaryState = ref.watch(familySummaryProvider);
    final memberBudgetsState = ref.watch(memberBudgetsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭成员'),
        actions: [
          IconButton(
            onPressed: _invalidateFamilyData,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: '刷新家庭数据',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _submittingMember ? null : () => _showMemberSheet(),
        tooltip: '添加成员',
        child: const Icon(Icons.add),
      ),
      body: AdaptivePageContainer(
        child: membersState.when(
          loading: () => const AppLoadingView(message: '正在加载家庭成员'),
          error: (error, stackTrace) => AppErrorView(
            message: '家庭成员加载失败：$error',
            onRetry: () => ref.invalidate(familyMembersProvider),
          ),
          data: (members) {
            if (members.isEmpty) {
              return _FamilyEmptyState(
                onAdd: _submittingMember ? null : () => _showMemberSheet(),
              );
            }
            final summary = summaryState.valueOrNull;
            final statisticsState = ref.watch(familyStatisticsProvider);
            final statistics = statisticsState.valueOrNull;
            return ListView(
              children: [
                StaggeredEntrance(
                  child: _FamilySummaryHeader(
                    members: members,
                    summary: summary,
                    loadingSummary: summaryState.isLoading,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '成员',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...members.indexed.map((entry) {
                  final (index, member) = entry;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StaggeredEntrance(
                      index: index + 1,
                      child: _FamilyMemberCard(
                        member: member,
                        submitting: _submittingMember,
                        onEdit: () => _showMemberSheet(member),
                        onDisable: member.isEnabled
                            ? () => _disableMember(member)
                            : null,
                      ),
                    ),
                  );
                }),
                if (memberBudgetsState.valueOrNull?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: members.length + 2,
                    child: _FamilyBudgetSurface(
                      budgets: memberBudgetsState.valueOrNull!,
                    ),
                  ),
                ],
                if (summaryState.hasError) ...[
                  const SizedBox(height: 12),
                  PremiumSurface(
                    accentColor: Theme.of(context).colorScheme.error,
                    child: const Text('家庭汇总加载失败，成员列表仍可查看。'),
                  ),
                ],
                if (summary != null && summary.members.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: members.length + 3,
                    child: _FamilyRankingSurface(summary: summary),
                  ),
                ],
                if (statistics != null &&
                    statistics.members.any(
                      (member) => member.categories.isNotEmpty,
                    )) ...[
                  const SizedBox(height: 12),
                  StaggeredEntrance(
                    index: members.length + 4,
                    child: _FamilyCategorySurface(statistics: statistics),
                  ),
                ],
                if (statisticsState.hasError) ...[
                  const SizedBox(height: 12),
                  PremiumSurface(
                    accentColor: Theme.of(context).colorScheme.error,
                    child: const Text('家庭分类统计加载失败，其他家庭数据仍可查看。'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FamilyEmptyState extends StatelessWidget {
  const _FamilyEmptyState({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Center(
      child: PremiumSurface(
        accentColor: financeColors.asset,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.diversity_3_outlined,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有家庭成员',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_outlined),
              label: const Text('添加成员'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilySummaryHeader extends StatelessWidget {
  const _FamilySummaryHeader({
    required this.members,
    required this.summary,
    required this.loadingSummary,
  });

  final List<FamilyMember> members;
  final FamilySummary? summary;
  final bool loadingSummary;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final enabledCount = members.where((member) => member.isEnabled).length;
    final month = summary?.month.isNotEmpty == true ? summary!.month : '本月';
    return Row(
      children: [
        Expanded(
          child: PremiumSurface(
            accentColor: financeColors.income,
            child: _FamilyMetric(
              label: '启用成员',
              value: '$enabledCount',
              helper: '共 ${members.length} 位',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: PremiumSurface(
            accentColor: financeColors.warning,
            child: _FamilyMetric(
              label: '$month 家庭支出',
              value: loadingSummary
                  ? '加载中'
                  : _formatMoney(summary?.totalExpense ?? 0),
              helper: '本月',
            ),
          ),
        ),
      ],
    );
  }
}

class _FamilyBudgetSurface extends StatelessWidget {
  const _FamilyBudgetSurface({required this.budgets});

  final List<BudgetItem> budgets;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final totalAmount = budgets.fold<double>(
      0,
      (sum, budget) => sum + budget.amount,
    );
    final totalSpent = budgets.fold<double>(
      0,
      (sum, budget) => sum + budget.spent,
    );
    final remaining = totalAmount - totalSpent;
    final visibleBudgets = budgets.take(3).toList();
    return PremiumSurface(
      accentColor: financeColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '家庭预算',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${budgets.length} 项',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _FamilyMetric(
                  label: '成员预算',
                  value: _formatMoney(totalAmount),
                  helper: '已用 ${_formatMoney(totalSpent)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FamilyMetric(
                  label: '剩余额度',
                  value: _formatMoney(remaining),
                  helper: remaining >= 0 ? '仍在预算内' : '需要关注',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...visibleBudgets.map((budget) => _FamilyBudgetRow(budget: budget)),
        ],
      ),
    );
  }
}

class _FamilyBudgetRow extends StatelessWidget {
  const _FamilyBudgetRow({required this.budget});

  final BudgetItem budget;

  @override
  Widget build(BuildContext context) {
    final color = _budgetStatusColor(context, budget.percentage);
    final memberName = budget.memberName.isEmpty ? '家庭成员' : budget.memberName;
    final title = budget.categoryName.isEmpty
        ? memberName
        : '$memberName · ${budget.categoryName}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${budget.percentage.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (budget.percentage / 100).clamp(0, 1).toDouble(),
              minHeight: 7,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyMetric extends StatelessWidget {
  const _FamilyMetric({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
      ],
    );
  }
}

class _FamilyCategorySurface extends StatelessWidget {
  const _FamilyCategorySurface({required this.statistics});

  final FamilyStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final visibleMembers = statistics.members
        .where((member) => member.categories.isNotEmpty)
        .take(4)
        .toList();
    return PremiumSurface(
      accentColor: financeColors.asset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.donut_large_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '成员分类拆分',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...visibleMembers.map(
            (member) => _FamilyCategoryMemberBlock(member: member),
          ),
        ],
      ),
    );
  }
}

class _FamilyCategoryMemberBlock extends StatelessWidget {
  const _FamilyCategoryMemberBlock({required this.member});

  final FamilyStatisticsMember member;

  @override
  Widget build(BuildContext context) {
    final memberColor = _memberColor(context, member.color);
    final categories = [...member.categories]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: memberColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const SizedBox.square(dimension: 10),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  member.name.isEmpty ? '未命名成员' : member.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _formatMoney(member.expenseTotal),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...categories
              .take(3)
              .map(
                (category) => _FamilyCategoryRow(
                  category: category,
                  total: member.expenseTotal,
                ),
              ),
        ],
      ),
    );
  }
}

class _FamilyCategoryRow extends StatelessWidget {
  const _FamilyCategoryRow({required this.category, required this.total});

  final FamilyStatisticsCategory category;
  final double total;

  @override
  Widget build(BuildContext context) {
    final color = _memberColor(context, category.color);
    final ratio = total <= 0 ? 0.0 : (category.amount / total).clamp(0, 1);
    final name = category.name.isEmpty ? '未分类' : category.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 7,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatMoney(category.amount),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _FamilyRankingSurface extends StatelessWidget {
  const _FamilyRankingSurface({required this.summary});

  final FamilySummary summary;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final ranked = [...summary.members]
      ..sort((a, b) => b.expenseTotal.compareTo(a.expenseTotal));
    return PremiumSurface(
      accentColor: financeColors.asset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '成员支出排行',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...ranked.map(
            (member) =>
                _FamilyRankingRow(member: member, total: summary.totalExpense),
          ),
        ],
      ),
    );
  }
}

class _FamilyRankingRow extends StatelessWidget {
  const _FamilyRankingRow({required this.member, required this.total});

  final FamilyMemberSummary member;
  final double total;

  @override
  Widget build(BuildContext context) {
    final color = _memberColor(context, member.color);
    final ratio = total <= 0
        ? 0.0
        : (member.expenseTotal / total).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member.name.isEmpty ? '未命名成员' : member.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${_formatMoney(member.expenseTotal)} · ${member.count} 笔',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyMemberCard extends StatelessWidget {
  const _FamilyMemberCard({
    required this.member,
    required this.submitting,
    required this.onEdit,
    required this.onDisable,
  });

  final FamilyMember member;
  final bool submitting;
  final VoidCallback onEdit;
  final VoidCallback? onDisable;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final accent = _memberColor(context, member.color);
    final colorScheme = Theme.of(context).colorScheme;
    final relationship = member.relationship.isEmpty
        ? '家庭成员'
        : member.relationship;
    final initial = member.name.characters.isEmpty
        ? '?'
        : member.name.characters.first;
    return PremiumSurface(
      accentColor: accent,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Text(
                  initial,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  relationship,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  if (member.isDefault)
                    _MemberStateChip(
                      label: '默认',
                      icon: Icons.check_circle_outline,
                      color: financeColors.income,
                    ),
                  _MemberStateChip(
                    label: member.isEnabled ? '启用' : '停用',
                    icon: member.isEnabled
                        ? Icons.person_outline
                        : Icons.person_off_outlined,
                    color: member.isEnabled
                        ? financeColors.asset
                        : colorScheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: submitting ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '编辑成员 ${member.name}',
                  ),
                  IconButton(
                    onPressed: submitting ? null : onDisable,
                    icon: const Icon(Icons.person_off_outlined),
                    tooltip: '停用成员 ${member.name}',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyMemberFormSheet extends StatefulWidget {
  const _FamilyMemberFormSheet({this.member});

  final FamilyMember? member;

  @override
  State<_FamilyMemberFormSheet> createState() => _FamilyMemberFormSheetState();
}

class _FamilyMemberFormSheetState extends State<_FamilyMemberFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _relationshipController;
  late final TextEditingController _avatarController;
  late String _color;
  late bool _isDefault;
  late bool _isEnabled;

  static const _colors = [
    '#2563EB',
    '#059669',
    '#F97316',
    '#DC2626',
    '#7C3AED',
    '#0891B2',
  ];

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    _nameController = TextEditingController(text: member?.name ?? '');
    _relationshipController = TextEditingController(
      text: member?.relationship ?? '',
    );
    _avatarController = TextEditingController(text: member?.avatar ?? '');
    _color = member?.color.isNotEmpty == true ? member!.color : _colors.first;
    _isDefault = member?.isDefault ?? false;
    _isEnabled = member?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      FamilyMemberRequest(
        name: _nameController.text.trim(),
        relationship: _relationshipController.text.trim(),
        avatar: _avatarController.text.trim(),
        color: _color,
        isDefault: _isDefault,
        isEnabled: _isEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.member == null ? '添加成员' : '编辑成员',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('family-member-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '成员名称',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入成员名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('family-member-relationship'),
                controller: _relationshipController,
                decoration: const InputDecoration(
                  labelText: '关系',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('family-member-avatar'),
                controller: _avatarController,
                decoration: const InputDecoration(
                  labelText: '头像地址',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in _colors)
                    InkResponse(
                      onTap: () => setState(() => _color = color),
                      radius: 22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _memberColor(context, color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color
                                ? colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: SizedBox.square(
                          dimension: 34,
                          child: _color == color
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value),
                title: const Text('默认成员'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isEnabled,
                onChanged: (value) => setState(() => _isEnabled = value),
                title: const Text('启用'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberStateChip extends StatelessWidget {
  const _MemberStateChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _memberColor(BuildContext context, String color) {
  final normalized = color.replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    return Theme.of(context).colorScheme.primary;
  }
  return Color(0xFF000000 | parsed);
}

Color _budgetStatusColor(BuildContext context, double percentage) {
  final colorScheme = Theme.of(context).colorScheme;
  final financeColors = AppTheme.financeColors(context);
  if (percentage >= 100) {
    return colorScheme.error;
  }
  if (percentage >= 80) {
    return financeColors.warning;
  }
  return financeColors.income;
}

String _formatMoney(double value) {
  return '¥${value.toStringAsFixed(2)}';
}
