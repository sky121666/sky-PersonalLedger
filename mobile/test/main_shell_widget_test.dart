import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
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

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('home-content'), findsOneWidget);

    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    expect(find.text('transactions-content'), findsOneWidget);

    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    expect(find.text('statistics-content'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('profile-content'), findsOneWidget);

    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();
    expect(find.text('quick-content'), findsOneWidget);
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
