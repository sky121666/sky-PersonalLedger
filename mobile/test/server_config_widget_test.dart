import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/auth_flow_shell.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/server_config/presentation/server_config_page.dart';

void main() {
  group('ServerConfigPage', () {
    testWidgets('空服务器地址会展示基础校验错误', (tester) async {
      final controller = await _pumpPage(tester);
      final connectButton = find.byKey(const ValueKey('server-connect-button'));

      await _scrollIntoTapArea(tester, connectButton);
      await tester.tap(connectButton);
      await tester.pumpAndSettle();

      expect(controller.connectCalls, ['']);
      expect(find.text('请输入服务器地址'), findsOneWidget);
      expect(find.text('连接服务器'), findsOneWidget);
      expect(find.text('自托管入口'), findsOneWidget);
      expect(find.byType(AuthFlowShell), findsOneWidget);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
      expect(find.text('私有服务连接'), findsOneWidget);
      expect(find.text('连接策略'), findsOneWidget);
      expect(find.text('HTTPS'), findsOneWidget);
      expect(find.text('初始化一次'), findsOneWidget);
      expect(find.text('只执行一次'), findsOneWidget);
      expect(find.text('跨端同步'), findsOneWidget);
      expect(find.text('家庭'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('备份'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-distribution-matrix')),
        findsOneWidget,
      );
      expect(find.text('跨端分发矩阵'), findsOneWidget);
      expect(find.text('等待地址'), findsOneWidget);
      expect(find.text('待绑定'), findsWidgets);
      expect(find.text('浏览器入口'), findsOneWidget);
      expect(find.text('原生客户端'), findsOneWidget);
      expect(find.text('Material 体验'), findsOneWidget);
      expect(find.text('一处部署'), findsOneWidget);
      expect(find.text('数据统一'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('server-topology-preview')),
        findsOneWidget,
      );
      expect(find.text('部署拓扑预览'), findsOneWidget);
      expect(find.text('等待输入服务地址'), findsOneWidget);
      expect(find.text('待完善'), findsOneWidget);
      expect(find.text('Web'), findsAtLeastNWidgets(1));
      expect(find.text('iOS'), findsAtLeastNWidgets(1));
      expect(find.text('Android'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('server-release-readiness-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('server-connection-evidence-rail')),
        findsOneWidget,
      );
      expect(find.text('部署就绪检查'), findsOneWidget);
      expect(find.text('待输入'), findsOneWidget);
      expect(find.text('连接证据 2/4'), findsOneWidget);
      expect(find.text('地址待确认'), findsOneWidget);
      expect(find.text('初始化只一次'), findsOneWidget);
      expect(find.text('等待跨端绑定'), findsOneWidget);
      expect(find.text('备份恢复预留'), findsOneWidget);
    });

    testWidgets('提交服务器地址时调用连接流程', (tester) async {
      final controller = await _pumpPage(tester);
      final connectButton = find.byKey(const ValueKey('server-connect-button'));

      await tester.enterText(
        find.widgetWithText(TextField, '服务器地址'),
        'ledger.example.com:8080',
      );
      await tester.pumpAndSettle();
      expect(find.text('ledger.example.com:8080'), findsWidgets);
      expect(find.text('地址就绪'), findsOneWidget);
      expect(find.text('需 HTTPS'), findsOneWidget);
      expect(find.text('公开域名'), findsOneWidget);
      expect(find.text('部署就绪检查'), findsOneWidget);
      expect(find.text('需加固'), findsOneWidget);
      expect(find.text('连接证据 3/4'), findsOneWidget);
      expect(find.text('跨端可复用'), findsOneWidget);
      expect(find.text('统一入口'), findsOneWidget);
      expect(find.text('单点服务'), findsWidgets);
      await _scrollIntoTapArea(tester, connectButton);
      await tester.tap(connectButton);
      await tester.pumpAndSettle();

      expect(controller.connectCalls, ['ledger.example.com:8080']);
      expect(controller.debugState.stage, AuthStage.loginRequired);
      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(2));
    });
  });
}

Future<_TestAuthController> _pumpPage(WidgetTester tester) async {
  late _TestAuthController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        authControllerProvider.overrideWith((ref) {
          controller = _TestAuthController(ref);
          return controller;
        }),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(authControllerProvider);
          return const MaterialApp(home: ServerConfigPage());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _scrollIntoTapArea(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  final center = tester.getCenter(finder);
  if (center.dy > 520) {
    await tester.drag(
      find.byType(Scrollable).first,
      Offset(0, -(center.dy - 440)),
    );
    await tester.pumpAndSettle();
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref) {
    state = const AuthState(stage: AuthStage.serverRequired);
  }

  final List<String> connectCalls = [];

  @override
  AuthState get debugState => state;

  @override
  Future<void> connectServer(String input) async {
    connectCalls.add(input);
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      state = const AuthState(
        stage: AuthStage.serverRequired,
        errorMessage: '请输入服务器地址',
      );
      return;
    }
    state = AuthState(
      stage: AuthStage.loginRequired,
      serverUrl: trimmed,
      initialized: true,
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthStatus> getStatus() async {
    return const AuthStatus(initialized: true);
  }

  @override
  Future<AuthTokenPair> init(String password) async {
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<AuthTokenPair> login(String password) async {
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<void> logout() async {}
}
