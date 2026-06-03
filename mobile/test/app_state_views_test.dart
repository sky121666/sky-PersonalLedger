import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/app_state_views.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';

void main() {
  testWidgets('AppLoadingView 只展示加载信息', (tester) async {
    await _pump(tester, const AppLoadingView(message: '正在加载数据...'));

    expect(find.text('数据加载中'), findsOneWidget);
    expect(find.text('正在加载数据...'), findsNothing);
    expect(find.text('本地缓存'), findsNothing);
    expect(find.text('接口连通'), findsNothing);
    expect(find.text('主题渲染'), findsNothing);
    expect(
      find.byKey(const ValueKey('state-loading-evidence-rail')),
      findsNothing,
    );
    expect(find.byType(PremiumSurface), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('AppEmptyView 展示语义图标和操作按钮', (tester) async {
    await _pump(
      tester,
      AppEmptyView(
        title: '还没有内容',
        message: '稍后再来查看。',
        icon: Icons.inbox_outlined,
        action: FilledButton(onPressed: () {}, child: const Text('创建')),
      ),
    );

    expect(find.text('还没有内容'), findsOneWidget);
    expect(find.text('稍后再来查看。'), findsOneWidget);
    expect(find.text('内容状态'), findsNothing);
    expect(find.text('下一步'), findsNothing);
    expect(find.text('创建'), findsWidgets);
    expect(find.textContaining('暂无内容'), findsNothing);
    expect(find.text('操作 · 可创建'), findsNothing);
    expect(
      find.byKey(const ValueKey('state-empty-evidence-rail')),
      findsNothing,
    );
    expect(find.byType(IconBadge), findsWidgets);
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
    expect(find.text('异常状态'), findsNothing);
    expect(find.text('恢复动作'), findsNothing);
    expect(find.text('已捕获'), findsNothing);
    expect(
      find.byKey(const ValueKey('state-error-evidence-rail')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('state-error-retry-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('state-error-retry-button')));
    await tester.pump();

    expect(retryCount, 1);
  });

  testWidgets('AppConfirmDialog 展示风险信号并返回确认结果', (tester) async {
    bool? lastConfirmed;
    await _pump(
      tester,
      Builder(
        builder: (context) {
          return FilledButton(
            onPressed: () async {
              final confirmed = await showAppConfirmDialog(
                context: context,
                title: '删除交易',
                message: '删除后账户余额会自动调整。',
                confirmText: '删除',
                isDanger: true,
              );
              lastConfirmed = confirmed;
            },
            child: const Text('打开确认'),
          );
        },
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();

    expect(find.text('删除交易'), findsOneWidget);
    expect(find.text('删除后账户余额会自动调整。'), findsOneWidget);
    expect(find.textContaining('同步回滚'), findsNothing);
    expect(find.textContaining('高风险'), findsNothing);
    expect(find.textContaining('需手动确认'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label != null &&
            widget.properties.label!.contains('删除交易') &&
            widget.properties.label!.contains('需手动确认'),
      ),
      findsAtLeastNWidgets(1),
    );
    expect(find.byType(PremiumSurface), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();

    expect(lastConfirmed, isFalse);

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(lastConfirmed, isTrue);
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
