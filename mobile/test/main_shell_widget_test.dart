import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/features/main/presentation/main_shell_page.dart';

void main() {
  testWidgets('MainShellPage 底部导航和快速记账入口可达', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutePaths.home,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => MainShellPage(
            navigationShell: navigationShell,
            quickTransactionBuilder: (_) => const _RouteMarker('quick-content'),
          ),
          branches: [
            _branch(AppRoutePaths.home, 'home-content'),
            _branch(AppRoutePaths.transactions, 'transactions-content'),
            _branch(AppRoutePaths.statistics, 'statistics-content'),
            _branch(AppRoutePaths.profile, 'profile-content'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme(AppThemePalette.violet),
        darkTheme: AppTheme.darkTheme(AppThemePalette.violet),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home-content'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('main-shell-tab-home')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('main-shell-tab-home')),
        matching: find.byType(Semantics),
      ),
      findsWidgets,
    );

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-transactions')));
    await tester.pumpAndSettle();
    expect(find.text('transactions-content'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-statistics')));
    await tester.pumpAndSettle();
    expect(find.text('statistics-content'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-profile')));
    await tester.pumpAndSettle();
    expect(find.text('profile-content'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
    );
    await tester.pumpAndSettle();
    expect(find.text('quick-content'), findsOneWidget);
  });

  testWidgets('MainShellPage 移动端胶囊导航跟随主题语义色', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutePaths.home,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MainShellPage(navigationShell: navigationShell),
          branches: [
            _branch(AppRoutePaths.home, 'home-content'),
            _branch(AppRoutePaths.transactions, 'transactions-content'),
            _branch(AppRoutePaths.statistics, 'statistics-content'),
            _branch(AppRoutePaths.profile, 'profile-content'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme(AppThemePalette.graphite),
        darkTheme: AppTheme.darkTheme(AppThemePalette.graphite),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    final selectedHomeIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('main-shell-tab-home')),
        matching: find.byIcon(Icons.home_rounded),
      ),
    );
    expect(selectedHomeIcon.color, AppThemePalette.graphite.assetColor);

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-statistics')));
    await tester.pumpAndSettle();

    final selectedStatsIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('main-shell-tab-statistics')),
        matching: find.byIcon(Icons.bar_chart_rounded),
      ),
    );
    expect(selectedStatsIcon.color, AppThemePalette.graphite.warningColor);
  });

  testWidgets('MainShellPage 宽屏侧栏跟随主题色模板', (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutePaths.home,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              MainShellPage(navigationShell: navigationShell),
          branches: [
            _branch(AppRoutePaths.home, 'home-content'),
            _branch(AppRoutePaths.transactions, 'transactions-content'),
            _branch(AppRoutePaths.statistics, 'statistics-content'),
            _branch(AppRoutePaths.profile, 'profile-content'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme(AppThemePalette.graphite),
        darkTheme: AppTheme.darkTheme(AppThemePalette.graphite),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main-shell-navigation-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('main-shell-rail-statistics')),
      findsOneWidget,
    );
    final brandIcon = tester.widget<Icon>(
      find.byIcon(Icons.account_balance_wallet_outlined).first,
    );
    expect(brandIcon.color, AppThemePalette.graphite.assetColor);

    await tester.tap(find.byKey(const ValueKey('main-shell-rail-statistics')));
    await tester.pumpAndSettle();
    expect(find.text('statistics-content'), findsOneWidget);
  });
}

StatefulShellBranch _branch(String path, String label) {
  return StatefulShellBranch(
    routes: [
      GoRoute(path: path, builder: (context, state) => _RouteMarker(label)),
    ],
  );
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}
