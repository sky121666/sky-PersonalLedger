import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
      body: isWideLayout
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PremiumNavigationRail(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _selectTab,
                  onQuickTransaction: () => _openQuickTransaction(context),
                ),
                Expanded(child: SizedBox.expand(child: navigationShell)),
              ],
            )
          : navigationShell,
      bottomNavigationBar: isWideLayout
          ? null
          : _PremiumBottomNavigation(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _selectTab,
              onQuickTransaction: () => _openQuickTransaction(context),
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
      showDragHandle: false,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 160),
        reverseDuration: Duration(milliseconds: 120),
      ),
      builder: (context) =>
          quickTransactionBuilder?.call(context) ??
          const QuickTransactionPage(embedded: true),
    );
  }
}

class _PremiumBottomNavigation extends StatelessWidget {
  const _PremiumBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onQuickTransaction,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onQuickTransaction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(12);
    final dynamicTypeExtra = scaledLabelHeight > 12
        ? (scaledLabelHeight - 12) * 1.25
        : 0.0;
    final destinations = [
      _ShellDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: '首页',
        keyValue: 'home',
      ),
      _ShellDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        label: '明细',
        keyValue: 'transactions',
      ),
      _ShellDestination(
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart_rounded,
        label: '统计',
        keyValue: 'statistics',
      ),
      _ShellDestination(
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view_rounded,
        label: '功能',
        keyValue: 'profile',
      ),
    ];
    return SizedBox(
      height: 72 + dynamicTypeExtra + bottomInset,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.68),
                width: 0.6,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
            child: Row(
              children: [
                for (final entry in destinations.take(2).indexed)
                  Expanded(
                    child: _PremiumBottomNavigationItem(
                      destination: entry.$2,
                      selected: selectedIndex == entry.$1,
                      onTap: () => onDestinationSelected(entry.$1),
                    ),
                  ),
                Expanded(
                  child: _QuickTransactionNavigationItem(
                    onTap: onQuickTransaction,
                  ),
                ),
                for (final entry in destinations.skip(2).indexed)
                  Expanded(
                    child: _PremiumBottomNavigationItem(
                      destination: entry.$2,
                      selected: selectedIndex == entry.$1 + 2,
                      onTap: () => onDestinationSelected(entry.$1 + 2),
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
    final foreground = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('main-shell-tab-${destination.keyValue}'),
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
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
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ) ??
                        TextStyle(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickTransactionNavigationItem extends StatelessWidget {
  const _QuickTransactionNavigationItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '记一笔',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('main-shell-quick-transaction'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: colorScheme.onPrimary,
                    size: 27,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '记一笔',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
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
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String keyValue;
}

class _PremiumNavigationRail extends StatelessWidget {
  const _PremiumNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onQuickTransaction,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onQuickTransaction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      right: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            right: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.68),
              width: 0.6,
            ),
          ),
        ),
        child: NavigationRail(
          key: const ValueKey('main-shell-navigation-rail'),
          minWidth: 92,
          backgroundColor: Colors.transparent,
          selectedIndex: selectedIndex,
          indicatorColor: colorScheme.surfaceContainerHigh,
          selectedIconTheme: IconThemeData(color: colorScheme.primary),
          unselectedIconTheme: IconThemeData(
            color: colorScheme.onSurfaceVariant,
          ),
          onDestinationSelected: onDestinationSelected,
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 18),
            child: Column(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: '记一笔',
                  child: IconButton.filled(
                    key: const ValueKey('main-shell-quick-transaction'),
                    onPressed: onQuickTransaction,
                    tooltip: '记一笔',
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
              ],
            ),
          ),
          destinations: [
            NavigationRailDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: const Text('首页', key: ValueKey('main-shell-rail-home')),
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
              icon: const Icon(Icons.grid_view_outlined),
              selectedIcon: const Icon(Icons.grid_view_rounded),
              label: const Text('功能', key: ValueKey('main-shell-rail-profile')),
            ),
          ],
        ),
      ),
    );
  }
}
