import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/bootstrap/presentation/bootstrap_page.dart';

void main() {
  testWidgets('BootstrapPage 展示启动中状态且不自行跳转', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BootstrapPage()));
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

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('正在启动'), findsOneWidget);
  });
}
