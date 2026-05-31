import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
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

const _categoryEmojis = [
  '🍽️',
  '🚗',
  '🛒',
  '🏠',
  '🎮',
  '💊',
  '📞',
  '💳',
  '💰',
  '📈',
  '💵',
  '📝',
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
            onPressed: () =>
                ref.read(categoryListControllerProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCategoryForm(context, selectedType),
        icon: const Icon(Icons.add),
        label: const Text('新增分类'),
      ),
      body: AdaptivePageContainer(
        child: Column(
          children: [
            StaggeredEntrance(
              index: 0,
              child: _CategoryHeader(
                selectedType: selectedType,
                count: state.valueOrNull?.categories.length ?? 0,
                onTypeChanged: (type) => ref
                    .read(categoryListControllerProvider.notifier)
                    .setType(type),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: state.when(
                data: (data) => _CategoryContent(state: data),
                loading: () => const AppLoadingView(message: '分类加载中...'),
                error: (error, _) => AppErrorView(
                  message: error.toString(),
                  onRetry: () =>
                      ref.read(categoryListControllerProvider.notifier).load(),
                ),
              ),
            ),
          ],
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

class _CategoryContent extends ConsumerWidget {
  const _CategoryContent({required this.state});

  final CategoryListState state;

  /// 构建分类列表内容。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.categories.isEmpty) {
      return StaggeredEntrance(
        index: 1,
        child: AppEmptyView(
          title: '暂无${state.type.label}分类',
          message: '添加分类后，记账时可以快速归类。',
          icon: Icons.category_outlined,
          action: FilledButton.icon(
            onPressed: () => _openCategoryForm(context, state.type),
            icon: const Icon(Icons.add),
            label: const Text('新增分类'),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(categoryListControllerProvider.notifier).load(),
      child: GridView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: state.categories.length,
        itemBuilder: (context, index) {
          return StaggeredEntrance(
            index: index + 1,
            child: _CategoryCard(category: state.categories[index]),
          );
        },
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

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.selectedType,
    required this.count,
    required this.onTypeChanged,
  });

  final CategoryType selectedType;
  final int count;
  final ValueChanged<CategoryType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final accentColor = selectedType == CategoryType.expense
        ? financeColors.expense
        : financeColors.income;
    return PremiumSurface(
      accentColor: accentColor,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: selectedType == CategoryType.expense
                    ? Icons.south_east
                    : Icons.north_west,
                color: accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selectedType.label}分类库',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count 个分类用于快速归集交易',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<CategoryType>(
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
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({required this.category});

  final Category category;

  /// 构建分类卡片。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _parseColor(
      category.color,
      Theme.of(context).colorScheme.primary,
    );
    return PremiumSurface(
      accentColor: color,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openEdit(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(
                      icon: _categoryIconData(category.icon),
                      color: color,
                      size: 42,
                      iconSize: 22,
                    ),
                    const Spacer(),
                    PopupMenuButton<_CategoryAction>(
                      onSelected: (action) =>
                          _handleAction(context, ref, action),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _CategoryAction.edit,
                          child: Text('编辑'),
                        ),
                        PopupMenuItem(
                          value: _CategoryAction.delete,
                          child: Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    category.isSystem ? '系统分类' : '自定义分类',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
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
          title: '确认删除',
          message: '删除后该分类下的交易记录将变为未分类状态。',
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
            ).showSnackBar(SnackBar(content: Text(error.toString())));
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
  late String _icon;
  late String _color;
  bool _submitting = false;

  /// 初始化分类表单状态。
  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? '');
    _icon =
        category?.icon ?? (widget.type == CategoryType.expense ? '🍽️' : '💰');
    _color = category?.color ?? _categoryColors.first;
  }

  /// 释放输入框控制器。
  @override
  void dispose() {
    _nameController.dispose();
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
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('category-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '分类名称',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入分类名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('category-icon'),
                initialValue: _icon,
                decoration: const InputDecoration(
                  labelText: '图标',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _icon = value.trim(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final emoji in _categoryEmojis)
                    ChoiceChip(
                      label: Text(emoji),
                      selected: _icon == emoji,
                      onSelected: (_) => setState(() => _icon = emoji),
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
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('category-save'),
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '保存中...' : '保存'),
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
    setState(() => _submitting = true);
    try {
      final controller = ref.read(categoryListControllerProvider.notifier);
      final category = widget.category;
      if (category == null) {
        await controller.create(
          CreateCategoryRequest(
            name: _nameController.text.trim(),
            type: widget.type,
            icon: _icon.isEmpty ? '📝' : _icon,
            color: _color,
          ),
        );
      } else {
        await controller.update(
          category.id,
          UpdateCategoryRequest(
            name: _nameController.text.trim(),
            icon: _icon.isEmpty ? '📝' : _icon,
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
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

enum _CategoryAction { edit, delete }

IconData _categoryIconData(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'food' || 'restaurant' || '🍽️' => Icons.restaurant_outlined,
    'transport' || 'car' || '🚗' => Icons.directions_car_outlined,
    'shopping' || 'cart' || '🛒' => Icons.shopping_bag_outlined,
    'home' || 'house' || '🏠' => Icons.home_outlined,
    'game' || '🎮' => Icons.sports_esports_outlined,
    'medical' || 'health' || '💊' => Icons.medical_services_outlined,
    'phone' || '📞' => Icons.phone_iphone_outlined,
    'card' || 'credit-card' || '💳' => Icons.credit_card_outlined,
    'salary' || 'income' || '💰' || '💵' => Icons.payments_outlined,
    'investment' || '📈' => Icons.show_chart_outlined,
    _ => Icons.category_outlined,
  };
}

/// 解析十六进制颜色。
Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
