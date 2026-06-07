import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/premium_surface.dart';
import '../application/category_controller.dart';
import '../data/category.dart';

const _categoryColors = [
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

const _categoryIconOptions = [
  _CategoryIconOption(
    value: 'restaurant',
    label: '餐饮图标',
    icon: Icons.restaurant_outlined,
  ),
  _CategoryIconOption(
    value: 'transport',
    label: '通勤图标',
    icon: Icons.directions_car_outlined,
  ),
  _CategoryIconOption(
    value: 'shopping',
    label: '购物图标',
    icon: Icons.shopping_bag_outlined,
  ),
  _CategoryIconOption(value: 'home', label: '居家图标', icon: Icons.home_outlined),
  _CategoryIconOption(
    value: 'medical',
    label: '健康图标',
    icon: Icons.medical_services_outlined,
  ),
  _CategoryIconOption(
    value: 'card',
    label: '卡片图标',
    icon: Icons.credit_card_outlined,
  ),
  _CategoryIconOption(
    value: 'income',
    label: '收入图标',
    icon: Icons.payments_outlined,
  ),
  _CategoryIconOption(
    value: 'investment',
    label: '投资图标',
    icon: Icons.show_chart_outlined,
  ),
];

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  /// 构建分类管理页。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(categoryListControllerProvider);
    final selectedType = state.valueOrNull?.type ?? CategoryType.expense;
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类'),
        actions: [
          IconButton(
            key: const ValueKey('category-add'),
            onPressed: () => _openCategoryForm(context, selectedType),
            tooltip: null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: AdaptivePageContainer(
        child: state.when(
          data: (data) => _CategoryLibraryView(state: data),
          loading: () => Column(
            children: [
              _CategoryHeader(
                selectedType: selectedType,
                onTypeChanged: (type) => ref
                    .read(categoryListControllerProvider.notifier)
                    .setType(type),
              ),
              const SizedBox(height: 16),
              const Expanded(child: AppLoadingView(message: '分类加载中...')),
            ],
          ),
          error: (error, _) => Column(
            children: [
              _CategoryHeader(
                selectedType: selectedType,
                onTypeChanged: (type) => ref
                    .read(categoryListControllerProvider.notifier)
                    .setType(type),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AppErrorView(
                  message: '分类加载失败',
                  onRetry: () =>
                      ref.read(categoryListControllerProvider.notifier).load(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 打开新增分类表单。
  Future<void> _openCategoryForm(
    BuildContext context,
    CategoryType type,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CategoryFormSheet(type: type),
    );
  }
}

class _CategoryLibraryView extends ConsumerWidget {
  const _CategoryLibraryView({required this.state});

  final CategoryListState state;

  /// 构建分类列表内容。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(categoryListControllerProvider.notifier).load(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _CategoryHeader(
              selectedType: state.type,
              onTypeChanged: (type) => ref
                  .read(categoryListControllerProvider.notifier)
                  .setType(type),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (state.categories.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _CategoryEmptyState(
                title: '还没有${state.type.label}分类',
                message: '右上角添加',
                icon: Icons.category_outlined,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 96),
              sliver: SliverList.separated(
                itemBuilder: (context, index) {
                  return _CategoryCard(category: state.categories[index]);
                },
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemCount: state.categories.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState({
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
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        child: PremiumSurface(
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
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.selectedType,
    required this.onTypeChanged,
  });

  final CategoryType selectedType;
  final ValueChanged<CategoryType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final accentColor = selectedType == CategoryType.expense
        ? financeColors.expense
        : financeColors.income;
    return PremiumSurface(
      accentColor: accentColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '${selectedType.label}分类',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 184,
            child: SegmentedButton<CategoryType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: CategoryType.expense,
                  label: Text('支出'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
                ButtonSegment(
                  value: CategoryType.income,
                  label: Text('收入'),
                  icon: Icon(Icons.add_circle_outline),
                ),
              ],
              selected: {selectedType},
              onSelectionChanged: (values) => onTypeChanged(values.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends ConsumerStatefulWidget {
  const _CategoryCard({required this.category});

  final Category category;

  /// 构建分类卡片。
  @override
  ConsumerState<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends ConsumerState<_CategoryCard> {
  bool _expanded = false;

  Category get category => widget.category;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _parseColor(category.color, colorScheme.primary);
    final ownershipLabel = category.isSystem ? '默认分类' : '自建分类';
    return Semantics(
      label: '${category.name}，${category.type.label}分类，$ownershipLabel',
      button: true,
      child: PremiumSurface(
        key: ValueKey('category-card-${category.id}'),
        accentColor: color,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openEdit(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SizedBox.square(
                          dimension: 34,
                          child: Icon(
                            _categoryIconData(category.icon),
                            size: 18,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${category.type.label} · $ownershipLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: ValueKey('category-toggle-details-${category.id}'),
                        tooltip: null,
                        onPressed: () => setState(() {
                          _expanded = !_expanded;
                        }),
                        icon: Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CategoryQuickAction(
                          key: ValueKey('category-action-edit-${category.id}'),
                          icon: Icons.edit_outlined,
                          label: '编辑',
                          onPressed: () =>
                              _handleAction(context, ref, _CategoryAction.edit),
                        ),
                        _CategoryQuickAction(
                          key: ValueKey(
                            'category-action-delete-${category.id}',
                          ),
                          icon: Icons.delete_outline,
                          label: '删除',
                          onPressed: () => _handleAction(
                            context,
                            ref,
                            _CategoryAction.delete,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开编辑分类表单。
  Future<void> _openEdit(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _CategoryFormSheet(type: category.type, category: category),
    );
  }

  /// 处理分类操作。
  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _CategoryAction action,
  ) async {
    switch (action) {
      case _CategoryAction.edit:
        await _openEdit(context);
      case _CategoryAction.delete:
        final confirmed = await showAppConfirmDialog(
          context: context,
          title: '删除分类',
          message: '删除「${category.name}」？',
          confirmText: '删除',
          isDanger: true,
        );
        if (!confirmed) {
          return;
        }
        try {
          await ref
              .read(categoryListControllerProvider.notifier)
              .delete(category.id);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('删除成功')));
          }
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('分类删除失败')));
          }
        }
    }
  }
}

class _CategoryFormSheet extends ConsumerStatefulWidget {
  const _CategoryFormSheet({required this.type, this.category});

  final CategoryType type;
  final Category? category;

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late String _color;
  bool _submitting = false;

  /// 初始化分类表单状态。
  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? '');
    _iconController = TextEditingController(
      text:
          category?.icon ??
          (widget.type == CategoryType.expense ? 'restaurant' : 'income'),
    );
    _color = category?.color ?? _categoryColors.first;
  }

  /// 释放输入框控制器。
  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  /// 构建分类表单。
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.category != null;
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
                isEditing ? '编辑分类' : '新增${widget.type.label}分类',
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
                key: const ValueKey('category-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '分类名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入分类名称' : null,
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                key: const ValueKey('category-visual-options'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: Text(
                  '外观',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                children: [
                  TextFormField(
                    key: const ValueKey('category-icon'),
                    controller: _iconController,
                    decoration: const InputDecoration(
                      labelText: '图标',
                      hintText: '选择或输入图标',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in _categoryIconOptions)
                        _CategoryIconChoice(
                          option: option,
                          selected:
                              _normalizeCategoryIcon(_iconController.text) ==
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
                    children: [
                      for (final color in _categoryColors)
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
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('category-save'),
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '保存中' : '保存分类'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 提交分类表单。
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final icon = _iconController.text.trim();
    setState(() => _submitting = true);
    try {
      final controller = ref.read(categoryListControllerProvider.notifier);
      final category = widget.category;
      if (category == null) {
        await controller.create(
          CreateCategoryRequest(
            name: _nameController.text.trim(),
            type: widget.type,
            icon: icon.isEmpty ? 'category' : icon,
            color: _color,
          ),
        );
      } else {
        await controller.update(
          category.id,
          UpdateCategoryRequest(
            name: _nameController.text.trim(),
            icon: icon.isEmpty ? 'category' : icon,
            color: _color,
          ),
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存成功')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分类保存失败')));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

class _CategoryQuickAction extends StatelessWidget {
  const _CategoryQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        foregroundColor: colorScheme.onSurface,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

enum _CategoryAction { edit, delete }

class _CategoryIconOption {
  const _CategoryIconOption({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

class _CategoryIconChoice extends StatelessWidget {
  const _CategoryIconChoice({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final _CategoryIconOption option;
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

IconData _categoryIconData(String value) {
  final normalized = _normalizeCategoryIcon(value);
  return switch (normalized) {
    'restaurant' => Icons.restaurant_outlined,
    'transport' => Icons.directions_car_outlined,
    'shopping' => Icons.shopping_bag_outlined,
    'home' => Icons.home_outlined,
    'game' => Icons.sports_esports_outlined,
    'medical' => Icons.medical_services_outlined,
    'phone' => Icons.phone_iphone_outlined,
    'card' => Icons.credit_card_outlined,
    'income' => Icons.payments_outlined,
    'investment' => Icons.show_chart_outlined,
    _ => Icons.category_outlined,
  };
}

String _normalizeCategoryIcon(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'food' || 'restaurant' || '🍽️' => 'restaurant',
    'transport' || 'car' || '🚗' => 'transport',
    'shopping' || 'cart' || '🛒' => 'shopping',
    'home' || 'house' || '🏠' => 'home',
    'game' || '🎮' => 'game',
    'medical' || 'health' || '💊' => 'medical',
    'phone' || '📞' => 'phone',
    'card' || 'credit-card' || '💳' => 'card',
    'salary' || 'income' || '💰' || '💵' => 'income',
    'investment' || '📈' => 'investment',
    _ => normalized,
  };
}

/// 解析十六进制颜色。
Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
