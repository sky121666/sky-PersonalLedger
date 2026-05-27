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

  /// 构建移动端主框架，包含底部导航和快速记账入口。
  @override
  Widget build(BuildContext context) {
    final isWideLayout = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      body: Row(
        children: [
          if (isWideLayout)
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _selectTab,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: Text('首页'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('明细'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: Text('统计'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('我的'),
                ),
              ],
            ),
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openQuickTransaction(context),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
      floatingActionButtonLocation: isWideLayout
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: isWideLayout
          ? null
          : NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: '明细',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: '统计',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的',
                ),
              ],
            ),
    );
  }

  /// 切换底部导航标签页。
  void _selectTab(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _openQuickTransaction(BuildContext context) {
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
        ),
        child:
            quickTransactionBuilder?.call(context) ??
            const QuickTransactionPage(embedded: true),
      ),
    );
  }
}
