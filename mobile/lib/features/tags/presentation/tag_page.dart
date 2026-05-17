import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
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
  'label',
  'credit-card',
  'banknote',
  'repeat',
  'wallet',
  'receipt',
  'calendar',
  'star',
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
            tooltip: '刷新',
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
      return AppEmptyView(
        title: '暂无标签',
        message: '添加标签后，记账时可以快速标记交易来源或用途。',
        icon: Icons.label_outline,
        action: FilledButton.icon(
          onPressed: _submitting ? null : () => _openTagForm(),
          icon: const Icon(Icons.add),
          label: const Text('新增标签'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTags,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _tags.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final tag = _tags[index];
          return _TagCard(
            tag: tag,
            busy: _submitting,
            onEdit: () => _openTagForm(tag),
            onDelete: () => _deleteTag(tag),
          );
        },
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
    final color = _parseColor(tag.color, Theme.of(context).colorScheme.primary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _TagIconBadge(icon: tag.icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('${tag.sourceLabel} · 使用 ${tag.usedCount} 次'),
                ],
              ),
            ),
            IconButton(
              onPressed: busy ? null : onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑标签',
            ),
            IconButton(
              onPressed: busy || tag.isSystem ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: tag.isSystem ? '系统标签不能删除' : '删除标签',
            ),
          ],
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
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('tag-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(),
                ),
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
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final icon in _tagIconOptions)
                    ChoiceChip(
                      label: Text(_tagIconLabel(icon)),
                      selected: _iconController.text == icon,
                      onSelected: (_) {
                        setState(() => _iconController.text = icon);
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
                      backgroundColor: _parseColor(color, Colors.blue),
                      selectedColor: _parseColor(color, Colors.blue),
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

class _TagIconBadge extends StatelessWidget {
  const _TagIconBadge({required this.icon, required this.color});

  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.14),
      foregroundColor: color,
      child: Icon(_tagIconData(icon), size: 22),
    );
  }
}

IconData _tagIconData(String icon) {
  return switch (icon) {
    'credit-card' => Icons.credit_card,
    'banknote' => Icons.payments_outlined,
    'repeat' => Icons.repeat,
    'wallet' => Icons.account_balance_wallet_outlined,
    'receipt' => Icons.receipt_long_outlined,
    'calendar' => Icons.calendar_month_outlined,
    'star' => Icons.star_outline,
    _ => Icons.label_outline,
  };
}

String _tagIconLabel(String icon) {
  return switch (icon) {
    'credit-card' => '卡',
    'banknote' => '现金',
    'repeat' => '周期',
    'wallet' => '钱包',
    'receipt' => '票据',
    'calendar' => '日期',
    'star' => '星标',
    _ => '标签',
  };
}

Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
