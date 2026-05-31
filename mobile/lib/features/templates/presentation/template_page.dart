import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../transactions/application/ledger_refresh.dart';
import '../../transactions/data/transaction_models.dart';
import '../data/template_repository.dart';

class TemplatePage extends ConsumerStatefulWidget {
  const TemplatePage({super.key});

  @override
  ConsumerState<TemplatePage> createState() => _TemplatePageState();
}

class _TemplatePageState extends ConsumerState<TemplatePage> {
  var _templates = <QuickTemplateItem>[];
  var _accounts = <LedgerAccount>[];
  var _categories = <LedgerCategory>[];
  var _loading = true;
  var _submitting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadData);
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(templateRepositoryProvider);
      final results = await Future.wait([
        repository.list(),
        repository.listAccounts(),
        repository.listCategories(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = results[0] as List<QuickTemplateItem>;
        _accounts = results[1] as List<LedgerAccount>;
        _categories = results[2] as List<LedgerCategory>;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openTemplateForm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _TemplateFormSheet(
        accounts: _accounts,
        categories: _categories,
        onSubmit: _createTemplate,
      ),
    );
  }

  Future<void> _createTemplate(QuickTemplateRequest request) async {
    setState(() => _submitting = true);
    try {
      final repository = ref.read(templateRepositoryProvider);
      await repository.create(request);
      final templates = await repository.list();
      if (!mounted) {
        return;
      }
      setState(() => _templates = templates);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('模板已保存')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _applyTemplate(QuickTemplateItem template) async {
    setState(() => _submitting = true);
    try {
      final repository = ref.read(templateRepositoryProvider);
      await repository.apply(
        template.id,
        ApplyTemplateRequest(transactionDate: DateTime.now()),
      );
      final templates = await repository.list();
      ref.invalidateLedgerMutationViews();
      if (!mounted) {
        return;
      }
      setState(() => _templates = templates);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已按模板记账')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _deleteTemplate(QuickTemplateItem template) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除模板',
      message: '删除后不会影响已经创建的交易记录。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final repository = ref.read(templateRepositoryProvider);
      await repository.delete(template.id);
      final templates = await repository.list();
      if (!mounted) {
        return;
      }
      setState(() => _templates = templates);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('模板已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _accountName(String id) {
    return _accounts
            .where((account) => account.id == id)
            .map((account) => account.name)
            .firstOrNull ??
        '未知账户';
  }

  String _categoryName(String? id) {
    if (id == null || id.isEmpty) {
      return '未分类';
    }
    return _categories
            .where((category) => category.id == id)
            .map((category) => category.name)
            .firstOrNull ??
        '未知分类';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷模板'),
        actions: [
          IconButton(
            onPressed: _submitting ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitting || _accounts.isEmpty || _categories.isEmpty
            ? null
            : _openTemplateForm,
        icon: const Icon(Icons.add),
        label: const Text('新增模板'),
      ),
      body: AdaptivePageContainer(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingView(message: '模板加载中...');
    }
    final error = _error;
    if (error != null) {
      return AppErrorView(message: error.toString(), onRetry: _loadData);
    }
    if (_templates.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          StaggeredEntrance(
            index: 0,
            child: _TemplateHero(
              templateCount: 0,
              totalUsedCount: 0,
              accountCount: _accounts.length,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 1,
            child: PremiumSurface(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
              child: AppEmptyView(
                title: '暂无快捷模板',
                message: '保存常用收支后，可以一键按模板记账。',
                icon: Icons.bolt_outlined,
                action: FilledButton.icon(
                  onPressed:
                      _submitting || _accounts.isEmpty || _categories.isEmpty
                      ? null
                      : _openTemplateForm,
                  icon: const Icon(Icons.add),
                  label: const Text('新增模板'),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final totalUsedCount = _templates.fold<int>(
      0,
      (total, template) => total + template.usedCount,
    );

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _templates.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return StaggeredEntrance(
              index: 0,
              child: _TemplateHero(
                templateCount: _templates.length,
                totalUsedCount: totalUsedCount,
                accountCount: _accounts.length,
              ),
            );
          }
          final template = _templates[index - 1];
          return StaggeredEntrance(
            index: index,
            child: _TemplateCard(
              template: template,
              accountName: _accountName(template.accountId),
              categoryName: _categoryName(template.categoryId),
              busy: _submitting,
              onApply: () => _applyTemplate(template),
              onDelete: () => _deleteTemplate(template),
            ),
          );
        },
      ),
    );
  }
}

class _TemplateHero extends StatelessWidget {
  const _TemplateHero({
    required this.templateCount,
    required this.totalUsedCount,
    required this.accountCount,
  });

  final int templateCount;
  final int totalUsedCount;
  final int accountCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.tertiary,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.bolt_outlined,
                color: colorScheme.tertiary,
                size: 48,
                iconSize: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '快捷模板库',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '把高频收支做成可复用模板，减少重复录入。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MetricPill(
                label: '模板数',
                value: '$templateCount 个',
                icon: Icons.dashboard_customize_outlined,
                color: colorScheme.tertiary,
              ),
              MetricPill(
                label: '累计使用',
                value: '$totalUsedCount 次',
                icon: Icons.play_circle_outline,
                color: colorScheme.primary,
              ),
              MetricPill(
                label: '可用账户',
                value: '$accountCount 个',
                icon: Icons.account_balance_wallet_outlined,
                color: colorScheme.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateMetaPill extends StatelessWidget {
  const _TemplateMetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.accountName,
    required this.categoryName,
    required this.busy,
    required this.onApply,
    required this.onDelete,
  });

  final QuickTemplateItem template;
  final String accountName;
  final String categoryName;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final isIncome = template.type == TransactionType.income;
    final amountColor = isIncome ? financeColors.income : colorScheme.error;
    return PremiumSurface(
      accentColor: amountColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: isIncome
                    ? Icons.trending_up_outlined
                    : Icons.trending_down_outlined,
                color: amountColor,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${template.typeLabel} · $accountName · $categoryName',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${isIncome ? '+' : '-'}¥${template.amount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (template.remark.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              template.remark,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _TemplateMetaPill(
                icon: Icons.repeat_outlined,
                label: '已用 ${template.usedCount} 次',
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: busy ? null : onApply,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('套用'),
              ),
              IconButton.filledTonal(
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除模板',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateFormSheet extends ConsumerStatefulWidget {
  const _TemplateFormSheet({
    required this.accounts,
    required this.categories,
    required this.onSubmit,
  });

  final List<LedgerAccount> accounts;
  final List<LedgerCategory> categories;
  final Future<void> Function(QuickTemplateRequest request) onSubmit;

  @override
  ConsumerState<_TemplateFormSheet> createState() => _TemplateFormSheetState();
}

class _TemplateFormSheetState extends ConsumerState<_TemplateFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();

  var _type = TransactionType.expense;
  String? _accountId;
  String? _categoryId;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.isNotEmpty ? widget.accounts.first.id : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  List<LedgerCategory> get _selectableCategories {
    return widget.categories
        .where((category) => category.type == _type.value)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final selectableCategories = _selectableCategories;
    if (!selectableCategories.any((category) => category.id == _categoryId)) {
      _categoryId = null;
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('新增快捷模板', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('支出'),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('收入'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (values) {
                  setState(() {
                    _type = values.first;
                    _categoryId = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('template-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '模板名称',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入模板名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('template-amount'),
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: '金额',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  return amount == null || amount <= 0 ? '请输入有效金额' : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('template-account'),
                initialValue: _accountId,
                decoration: const InputDecoration(
                  labelText: '账户',
                  border: OutlineInputBorder(),
                ),
                items: widget.accounts
                    .map(
                      (account) => DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    )
                    .toList(),
                validator: (value) =>
                    value == null || value.isEmpty ? '请选择账户' : null,
                onChanged: (value) => setState(() => _accountId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('template-category'),
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: '分类',
                  border: OutlineInputBorder(),
                ),
                items: selectableCategories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    )
                    .toList(),
                validator: (value) =>
                    value == null || value.isEmpty ? '请选择分类' : null,
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('template-remark'),
                controller: _remarkController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('template-save'),
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '保存中...' : '保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        QuickTemplateRequest(
          name: _nameController.text.trim(),
          type: _type,
          amount: double.parse(_amountController.text),
          accountId: _accountId!,
          categoryId: _categoryId!,
          remark: _remarkController.text.trim(),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      // Parent page has already surfaced the concrete error.
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
