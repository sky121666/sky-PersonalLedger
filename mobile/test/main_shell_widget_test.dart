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
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('main-shell-tab-home')))
          .dy,
      greaterThan(800),
    );
    expect(tester.getCenter(find.text('home-content')).dy, greaterThan(100));
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('快速记一笔'), findsNothing);
    final quickActionSize = tester.getSize(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
    );
    expect(quickActionSize.width, greaterThanOrEqualTo(44));
    expect(quickActionSize.height, greaterThanOrEqualTo(44));
    expect(find.byKey(const ValueKey('main-shell-tab-home')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('main-shell-tab-home')),
        matching: find.byType(Semantics),
      ),
      findsWidgets,
    );
    await tester.tap(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
    );
    await tester.pumpAndSettle();
    expect(find.text('quick-content'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-transactions')));
    await tester.pumpAndSettle();
    expect(find.text('transactions-content'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-statistics')));
    await tester.pumpAndSettle();
    expect(find.text('statistics-content'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-profile')));
    await tester.pumpAndSettle();
    expect(find.text('profile-content'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
      findsOneWidget,
    );
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
    expect(selectedHomeIcon.color, AppTheme.seedColor);

    await tester.tap(find.byKey(const ValueKey('main-shell-tab-statistics')));
    await tester.pumpAndSettle();

    final selectedStatsIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('main-shell-tab-statistics')),
        matching: find.byIcon(Icons.bar_chart_rounded),
      ),
    );
    expect(selectedStatsIcon.color, AppTheme.seedColor);
  });

  testWidgets('MainShellPage 底部导航语义不重复朗读标签', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

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
        theme: AppTheme.lightTheme(AppThemePalette.teal),
        darkTheme: AppTheme.darkTheme(AppThemePalette.teal),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('首页'), findsOneWidget);
    expect(find.bySemanticsLabel('明细'), findsOneWidget);
    expect(find.bySemanticsLabel('统计'), findsOneWidget);
    expect(find.bySemanticsLabel('功能'), findsOneWidget);
    expect(find.bySemanticsLabel('记一笔'), findsOneWidget);
    expect(find.bySemanticsLabel('首页\n首页'), findsNothing);
    expect(find.bySemanticsLabel('明细\n明细'), findsNothing);
    expect(find.bySemanticsLabel('统计\n统计'), findsNothing);
    expect(find.bySemanticsLabel('功能\n功能'), findsNothing);
    semantics.dispose();
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
    expect(brandIcon.color, AppTheme.seedColor);
    expect(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('main-shell-rail-statistics')));
    await tester.pumpAndSettle();
    expect(find.text('statistics-content'), findsOneWidget);
  });

  testWidgets('MainShellPage 横屏手机仍使用底部导航而不是侧栏', (tester) async {
    tester.view.physicalSize = const Size(932, 430);
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
        theme: AppTheme.lightTheme(AppThemePalette.teal),
        darkTheme: AppTheme.darkTheme(AppThemePalette.teal),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.byKey(const ValueKey('main-shell-navigation-rail')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('main-shell-tab-home')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      find.byKey(const ValueKey('main-shell-quick-transaction')),
      findsOneWidget,
    );
  });

  testWidgets('MainShellPage 支持 200% 动态字体且保持导航可达', (tester) async {
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
        theme: AppTheme.lightTheme(AppThemePalette.teal),
        routerConfig: router,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final key in const ['home', 'transactions', 'statistics', 'profile']) {
      final finder = find.byKey(ValueKey('main-shell-tab-$key'));
      expect(finder, findsOneWidget);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
    }
    expect(
      tester
          .getSize(find.byKey(const ValueKey('main-shell-quick-transaction')))
          .height,
      greaterThanOrEqualTo(44),
    );
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
