import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/app_state_views.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';

void main() {
  testWidgets('AppLoadingView 使用高级加载面板', (tester) async {
    await _pump(tester, const AppLoadingView(message: '正在加载数据...'));

    expect(find.text('正在加载数据...'), findsOneWidget);
    expect(find.byType(PremiumSurface), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('AppEmptyView 展示语义图标和操作按钮', (tester) async {
    await _pump(
      tester,
      AppEmptyView(
        title: '暂无数据',
        message: '稍后再来查看。',
        icon: Icons.inbox_outlined,
        action: FilledButton(onPressed: () {}, child: const Text('创建')),
      ),
    );

    expect(find.text('暂无数据'), findsOneWidget);
    expect(find.text('稍后再来查看。'), findsOneWidget);
    expect(find.text('创建'), findsOneWidget);
    expect(find.byType(IconBadge), findsOneWidget);
    expect(find.byType(PremiumSurface), findsOneWidget);
  });

  testWidgets('AppErrorView 展示错误面板并可重试', (tester) async {
    var retryCount = 0;
    await _pump(
      tester,
      AppErrorView(
        message: '加载失败',
        onRetry: () {
          retryCount += 1;
        },
      ),
    );

    expect(find.text('出错了'), findsOneWidget);
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(retryCount, 1);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(AppThemePalette.graphite),
      darkTheme: AppTheme.darkTheme(AppThemePalette.graphite),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
