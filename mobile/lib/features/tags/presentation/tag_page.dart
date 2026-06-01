import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../data/tag_repository.dart';

const _tagColors = [
  '#EF4444',
  '#F97316',
  '#F59E0B',
  '#84CC16',
  '#10B981',
  '#06B6D4',
  '#3B82F6',
  '#6366F1',
  '#8B5CF6',
  '#EC4899',
  '#64748B',
  '#71717A',
];

const _tagIconOptions = [
  _TagIconOption(value: 'label', label: '标签图标', icon: Icons.label_outline),
  _TagIconOption(
    value: 'credit-card',
    label: '卡片图标',
    icon: Icons.credit_card_outlined,
  ),
  _TagIconOption(
    value: 'banknote',
    label: '现金图标',
    icon: Icons.payments_outlined,
  ),
  _TagIconOption(value: 'repeat', label: '周期图标', icon: Icons.repeat_outlined),
  _TagIconOption(
    value: 'wallet',
    label: '钱包图标',
    icon: Icons.account_balance_wallet_outlined,
  ),
  _TagIconOption(
    value: 'receipt',
    label: '票据图标',
    icon: Icons.receipt_long_outlined,
  ),
  _TagIconOption(
    value: 'calendar',
    label: '日期图标',
    icon: Icons.calendar_month_outlined,
  ),
  _TagIconOption(value: 'star', label: '星标图标', icon: Icons.star_outline),
];

class TagPage extends ConsumerStatefulWidget {
  const TagPage({super.key});

  @override
  ConsumerState<TagPage> createState() => _TagPageState();
}

class _TagPageState extends ConsumerState<TagPage> {
  var _tags = <TagItem>[];
  var _loading = true;
  var _submitting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadTags);
  }

  Future<void> _loadTags() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tags = await ref.read(tagRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() => _tags = tags);
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

  Future<void> _openTagForm([TagItem? tag]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _TagFormSheet(
        tag: tag,
        onSubmit: (request) => _saveTag(request, tag),
      ),
    );
  }

  Future<void> _saveTag(TagRequest request, TagItem? tag) async {
    setState(() => _submitting = true);
    try {
      final repository = ref.read(tagRepositoryProvider);
      if (tag == null) {
        await repository.create(request);
      } else {
        await repository.update(tag.id, request);
      }
      final tags = await repository.list();
      if (!mounted) {
        return;
      }
      setState(() => _tags = tags);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('标签已保存')));
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

  Future<void> _deleteTag(TagItem tag) async {
    if (tag.isSystem) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('系统标签不能删除')));
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除标签',
      message: '删除后不会删除已有交易，但该标签将不能继续选择。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final repository = ref.read(tagRepositoryProvider);
      await repository.delete(tag.id);
      final tags = await repository.list();
      if (!mounted) {
        return;
      }
      setState(() => _tags = tags);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('标签已删除')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
        actions: [
          IconButton(
            onPressed: _submitting ? null : _loadTags,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新标签列表',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitting ? null : () => _openTagForm(),
        icon: const Icon(Icons.add),
        label: const Text('新增标签'),
      ),
      body: AdaptivePageContainer(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingView(message: '标签加载中...');
    }
    final error = _error;
    if (error != null) {
      return AppErrorView(message: error.toString(), onRetry: _loadTags);
    }
    if (_tags.isEmpty) {
      return StaggeredEntrance(
        index: 0,
        child: AppEmptyView(
          title: '暂无标签',
          icon: Icons.label_outline,
          action: FilledButton.icon(
            onPressed: _submitting ? null : () => _openTagForm(),
            icon: const Icon(Icons.add),
            label: const Text('新增标签'),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTags,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final entry in _tags.indexed) ...[
            StaggeredEntrance(
              index: entry.$1,
              child: _TagCard(
                tag: entry.$2,
                busy: _submitting,
                onEdit: () => _openTagForm(entry.$2),
                onDelete: () => _deleteTag(entry.$2),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  const _TagCard({
    required this.tag,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final TagItem tag;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _parseColor(tag.color, colorScheme.primary);
    return Semantics(
      label: '${tag.name}，${tag.sourceLabel}，使用 ${tag.usedCount} 次',
      button: true,
      child: PremiumSurface(
        key: ValueKey('tag-card-${tag.id}'),
        accentColor: color,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(icon: _tagIconData(tag.icon), color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${tag.sourceLabel} · 使用 ${tag.usedCount} 次',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑标签 ${tag.name}',
              ),
              IconButton(
                onPressed: busy || tag.isSystem ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: tag.isSystem ? '系统标签不能删除' : '删除标签 ${tag.name}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagFormSheet extends ConsumerStatefulWidget {
  const _TagFormSheet({required this.onSubmit, this.tag});

  final TagItem? tag;
  final Future<void> Function(TagRequest request) onSubmit;

  @override
  ConsumerState<_TagFormSheet> createState() => _TagFormSheetState();
}

class _TagFormSheetState extends ConsumerState<_TagFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late String _color;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    final tag = widget.tag;
    _nameController = TextEditingController(text: tag?.name ?? '');
    _iconController = TextEditingController(text: tag?.icon ?? 'label');
    _color = tag?.color ?? _tagColors[7];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.tag != null;
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
              Text(
                isEditing ? '编辑标签' : '新增标签',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              Text(
                '基础信息',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('tag-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入标签名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('tag-icon'),
                controller: _iconController,
                decoration: const InputDecoration(
                  labelText: '图标标识',
                  hintText: 'label / wallet / repeat',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _tagIconOptions)
                    _TagIconChoice(
                      option: option,
                      selected:
                          _iconController.text.trim().toLowerCase() ==
                          option.value,
                      onSelected: () {
                        setState(() => _iconController.text = option.value);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _tagColors)
                    ChoiceChip(
                      label: const SizedBox(width: 16, height: 16),
                      selected: _color == color,
                      backgroundColor: _parseColor(
                        color,
                        AppTheme.financeColors(context).asset,
                      ),
                      selectedColor: _parseColor(
                        color,
                        AppTheme.financeColors(context).asset,
                      ),
                      onSelected: (_) => setState(() => _color = color),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('tag-save'),
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
        TagRequest(
          name: _nameController.text.trim(),
          color: _color,
          icon: _iconController.text.trim().isEmpty
              ? 'label'
              : _iconController.text.trim(),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      // Parent page has already shown the concrete error.
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _TagIconOption {
  const _TagIconOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

class _TagIconChoice extends StatelessWidget {
  const _TagIconChoice({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final _TagIconOption option;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = selected ? colorScheme.primary : colorScheme.outline;
    return ChoiceChip(
      avatar: Icon(option.icon, size: 18, color: accentColor),
      label: Text(option.label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

IconData _tagIconData(String icon) {
  return switch (icon.trim().toLowerCase()) {
    'credit-card' => Icons.credit_card_outlined,
    'banknote' => Icons.payments_outlined,
    'repeat' => Icons.repeat_outlined,
    'wallet' => Icons.account_balance_wallet_outlined,
    'receipt' => Icons.receipt_long_outlined,
    'calendar' => Icons.calendar_month_outlined,
    'star' => Icons.star_outline,
    _ => Icons.label_outline,
  };
}

Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
