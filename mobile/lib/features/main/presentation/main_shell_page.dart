import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 构建移动端主框架，包含底部导航和快速记账入口。
  @override
  Widget build(BuildContext context) {
    final isWideLayout = MediaQuery.sizeOf(context).width >= 720;
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
      floatingActionButton: Semantics(
        button: true,
        label: '快速记一笔',
        child: _QuickTransactionFab(
          key: const ValueKey('main-shell-quick-transaction'),
          onPressed: () => _openQuickTransaction(context),
        ),
      ),
      floatingActionButtonLocation: isWideLayout
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: isWideLayout
          ? null
          : _PremiumBottomNavigation(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _selectTab,
            ),
    );
  }

  /// 切换底部导航标签页。
  void _selectTab(int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _openQuickTransaction(BuildContext context) {
    HapticFeedback.lightImpact();
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 640),
      elevation: 0,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Flexible(
              child:
                  quickTransactionBuilder?.call(context) ??
                  const QuickTransactionPage(embedded: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTransactionFab extends StatelessWidget {
  const _QuickTransactionFab({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPressed,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary,
                Color.alphaBlend(
                  financeColors.asset.withValues(alpha: isDark ? 0.42 : 0.30),
                  colorScheme.primary,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colorScheme.onPrimary.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(
                  alpha: isDark ? 0.34 : 0.24,
                ),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.onPrimary.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: colorScheme.onPrimary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 9),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '记一笔',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '快速入口',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimary.withValues(alpha: 0.74),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 74),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              colorScheme.primary.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.08
                    : 0.04,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.28
                      : 0.10,
                ),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShellRouteEvidenceRail(
                destinations: destinations,
                selectedIndex: selectedIndex,
              ),
              const SizedBox(height: 6),
              Row(
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
                      const SizedBox(width: 6),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellRouteEvidenceRail extends StatelessWidget {
  const _ShellRouteEvidenceRail({
    required this.destinations,
    required this.selectedIndex,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = destinations[selectedIndex];
    return Wrap(
      key: const ValueKey('main-shell-route-evidence-rail'),
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        _ShellEvidencePill(
          icon: Icons.route_outlined,
          label: '入口 ${destinations.length}',
          color: colorScheme.primary,
        ),
        _ShellEvidencePill(
          icon: selected.selectedIcon,
          label: '当前 ${selected.label}',
          color: selected.color,
        ),
        _ShellEvidencePill(
          icon: Icons.add_circle_outline,
          label: '快速记账就绪',
          color: colorScheme.tertiary,
        ),
      ],
    );
  }
}

class _ShellEvidencePill extends StatelessWidget {
  const _ShellEvidencePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
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
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      activeColor.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.22
                            : 0.14,
                      ),
                      colorScheme.surface,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? activeColor.withValues(alpha: 0.26)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: selected ? 22 : 5,
                  height: 4,
                  decoration: BoxDecoration(
                    color: selected
                        ? activeColor
                        : colorScheme.outlineVariant.withValues(alpha: 0.0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  scale: selected ? 1.08 : 1,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: foreground,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  style:
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ) ??
                      TextStyle(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ),
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                child: Column(
                  key: const ValueKey('main-shell-wide-route-evidence'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
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
                    const SizedBox(height: 6),
                    Text(
                      '4入口',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
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
