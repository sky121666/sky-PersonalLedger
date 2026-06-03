import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/bootstrap/presentation/bootstrap_page.dart';

void main() {
  testWidgets('BootstrapPage 初始化后进入服务器配置', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutePaths.bootstrap,
      routes: [
        GoRoute(
          path: AppRoutePaths.bootstrap,
          builder: (context, state) => const BootstrapPage(),
        ),
        GoRoute(
          path: AppRoutePaths.serverConfig,
          builder: (context, state) => const _ServerConfigMarker(),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('正在启动'), findsOneWidget);
    expect(find.text('请稍候。'), findsNothing);
    expect(
      find.byKey(const ValueKey('bootstrap-readiness-rail')),
      findsNothing,
    );
    expect(find.text('启动检查 3/3'), findsNothing);
    expect(find.text('下一步服务器'), findsNothing);
    expect(find.text('安全上下文预备'), findsNothing);
    expect(find.byType(PremiumSurface), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('server-config-content'), findsOneWidget);
  });
}

class _ServerConfigMarker extends StatelessWidget {
  const _ServerConfigMarker();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('server-config-content')));
  }
}
