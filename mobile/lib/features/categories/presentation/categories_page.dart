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
                categories: state.valueOrNull?.categories ?? const [],
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
    required this.categories,
    required this.onTypeChanged,
  });

  final CategoryType selectedType;
  final List<Category> categories;
  final ValueChanged<CategoryType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = selectedType == CategoryType.expense
        ? financeColors.expense
        : financeColors.income;
    final systemCount = categories
        .where((category) => category.isSystem)
        .length;
    final customCount = categories.length - systemCount;
    final palettePreview = categories.take(8).toList();
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
                      '${categories.length} 个分类用于快速归集交易',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CategorySpectrumPanel(
            selectedType: selectedType,
            categories: categories,
            systemCount: systemCount,
            customCount: customCount,
            palettePreview: palettePreview,
            accentColor: accentColor,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CategorySignalTile(
                  icon: Icons.dashboard_customize_outlined,
                  label: '分类总数',
                  value: '${categories.length}',
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CategorySignalTile(
                  icon: Icons.verified_outlined,
                  label: '系统',
                  value: '$systemCount',
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CategorySignalTile(
                  icon: Icons.tune_outlined,
                  label: '自定义',
                  value: '$customCount',
                  color: financeColors.asset,
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

class _CategorySpectrumPanel extends StatelessWidget {
  const _CategorySpectrumPanel({
    required this.selectedType,
    required this.categories,
    required this.systemCount,
    required this.customCount,
    required this.palettePreview,
    required this.accentColor,
  });

  final CategoryType selectedType;
  final List<Category> categories;
  final int systemCount;
  final int customCount;
  final List<Category> palettePreview;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = categories.isEmpty ? 1 : categories.length;
    final customRatio = (customCount / total).clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('category-spectrum-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '分类颜色系统',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '自定义占比 ${(customRatio * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final entry in palettePreview.indexed) ...[
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: _parseColor(entry.$2.color, accentColor),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (entry.$1 != palettePreview.length - 1)
                  const SizedBox(width: 4),
              ],
              if (palettePreview.isEmpty)
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CategoryMetaChip(
                label: '${selectedType.label}模式',
                color: accentColor,
              ),
              _CategoryMetaChip(
                label: '系统 $systemCount',
                color: colorScheme.primary,
              ),
              _CategoryMetaChip(
                label: '自定义 $customCount',
                color: colorScheme.tertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategorySignalTile extends StatelessWidget {
  const _CategorySignalTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryMetaChip extends StatelessWidget {
  const _CategoryMetaChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
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
    final previewColor = _parseColor(
      _color,
      AppTheme.financeColors(context).asset,
    );
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
              _CategoryFormPreview(
                title: isEditing ? '编辑分类' : '新增${widget.type.label}分类',
                name: _nameController.text.trim().isEmpty
                    ? '未命名分类'
                    : _nameController.text.trim(),
                icon: _categoryIconData(_iconController.text),
                color: previewColor,
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
              TextFormField(
                key: const ValueKey('category-icon'),
                controller: _iconController,
                decoration: const InputDecoration(
                  labelText: '图标标识',
                  hintText: 'restaurant / income / shopping',
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

class _CategoryFormPreview extends StatelessWidget {
  const _CategoryFormPreview({
    required this.title,
    required this.name,
    required this.icon,
    required this.color,
  });

  final String title;
  final String name;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: color,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 46, iconSize: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前名称：$name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
