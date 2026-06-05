import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../transactions/presentation/quick_transaction_page.dart';

class MainShellPage extends StatelessWidget {
  const MainShellPage({
    required this.navigationShell,
    this.quickTransactionBuilder,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final WidgetBuilder? quickTransactionBuilder;

  /// 构建移动端主框架，包含底部导航和快速记账按钮。
  @override
  Widget build(BuildContext context) {
    final isWideLayout = _shouldUseNavigationRail(MediaQuery.sizeOf(context));
    return Scaffold(
      body: Row(
        children: [
          if (isWideLayout)
            _PremiumNavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _selectTab,
            ),
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButton: _QuickTransactionFab(
        key: const ValueKey('main-shell-quick-transaction'),
        onPressed: () => _openQuickTransaction(context),
      ),
      floatingActionButtonLocation: isWideLayout
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: isWideLayout
          ? null
          : _PremiumBottomNavigation(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _selectTab,
            ),
    );
  }

  static bool _shouldUseNavigationRail(Size size) {
    return size.width >= 720 && size.shortestSide >= 600;
  }

  /// 切换底部导航标签页。
  void _selectTab(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _openQuickTransaction(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 640),
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 180),
        reverseDuration: Duration(milliseconds: 140),
      ),
      builder: (context) =>
          quickTransactionBuilder?.call(context) ??
          const QuickTransactionPage(embedded: true),
    );
  }
}

class _QuickTransactionFab extends StatelessWidget {
  const _QuickTransactionFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: null,
      elevation: 1,
      focusElevation: 1,
      hoverElevation: 1,
      highlightElevation: 2,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      shape: const CircleBorder(),
      child: const Icon(Icons.add_rounded, size: 30),
    );
  }
}

class _PremiumBottomNavigation extends StatelessWidget {
  const _PremiumBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final destinations = [
      _ShellDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: '首页',
        keyValue: 'home',
        color: financeColors.asset,
      ),
      _ShellDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        label: '明细',
        keyValue: 'transactions',
        color: financeColors.income,
      ),
      _ShellDestination(
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart_rounded,
        label: '统计',
        keyValue: 'statistics',
        color: financeColors.warning,
      ),
      _ShellDestination(
        icon: Icons.person_outline,
        selectedIcon: Icons.person_rounded,
        label: '我的',
        keyValue: 'profile',
        color: colorScheme.primary,
      ),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              colorScheme.primary.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.06
                    : 0.025,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.48),
            ),
          ),
          child: Row(
            children: [
              for (final entry in destinations.indexed) ...[
                Expanded(
                  child: _PremiumBottomNavigationItem(
                    destination: entry.$2,
                    selected: selectedIndex == entry.$1,
                    onTap: () => onDestinationSelected(entry.$1),
                  ),
                ),
                if (entry.$1 != destinations.length - 1)
                  const SizedBox(width: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumBottomNavigationItem extends StatelessWidget {
  const _PremiumBottomNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = destination.color;
    final foreground = selected ? activeColor : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('main-shell-tab-${destination.keyValue}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      activeColor.withValues(alpha: 0.075),
                      colorScheme.surface,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: foreground,
                  size: 21,
                ),
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ) ??
                      TextStyle(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.keyValue,
    required this.color,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String keyValue;
  final Color color;
}

class _PremiumNavigationRail extends StatelessWidget {
  const _PremiumNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: NavigationRail(
              key: const ValueKey('main-shell-navigation-rail'),
              minWidth: 92,
              backgroundColor: Colors.transparent,
              selectedIndex: selectedIndex,
              indicatorColor: colorScheme.primaryContainer,
              selectedIconTheme: IconThemeData(color: colorScheme.primary),
              unselectedIconTheme: IconThemeData(color: colorScheme.outline),
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 14),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: financeColors.asset.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: financeColors.asset,
                  ),
                ),
              ),
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: const Text(
                    '首页',
                    key: ValueKey('main-shell-rail-home'),
                  ),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long_rounded),
                  label: const Text(
                    '明细',
                    key: ValueKey('main-shell-rail-transactions'),
                  ),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.bar_chart_outlined),
                  selectedIcon: const Icon(Icons.bar_chart_rounded),
                  label: const Text(
                    '统计',
                    key: ValueKey('main-shell-rail-statistics'),
                  ),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person_rounded),
                  label: const Text(
                    '我的',
                    key: ValueKey('main-shell-rail-profile'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
