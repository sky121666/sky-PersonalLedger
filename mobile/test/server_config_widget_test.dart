import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/auth_flow_shell.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/core/config/local_http_transport_policy.dart';
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
      expect(find.text('请输入账本地址'), findsOneWidget);
      expect(find.text('连接账本'), findsOneWidget);
      expect(find.text('连接服务器'), findsNothing);
      expect(find.text('连接你的账本服务。'), findsNothing);
      expect(find.text('自托管入口'), findsNothing);
      expect(find.byType(AuthFlowShell), findsOneWidget);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
      expect(find.text('私有服务连接'), findsNothing);
      expect(find.text('连接策略'), findsNothing);
      expect(find.text('HTTPS'), findsNothing);
      expect(find.text('初始化一次'), findsNothing);
      expect(find.text('跨端同步'), findsNothing);
      expect(
        find.byKey(const ValueKey('server-distribution-matrix')),
        findsNothing,
      );
      expect(find.text('跨端分发矩阵'), findsNothing);
      expect(
        find.byKey(const ValueKey('server-topology-preview')),
        findsNothing,
      );
      expect(find.text('部署拓扑预览'), findsNothing);
      expect(
        find.byKey(const ValueKey('server-release-readiness-panel')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('server-connection-evidence-rail')),
        findsNothing,
      );
      expect(find.text('部署就绪检查'), findsNothing);
      expect(find.text('连接证据 2/4'), findsNothing);
    });

    testWidgets('提交服务器地址时调用连接流程', (tester) async {
      final controller = await _pumpPage(tester);
      final connectButton = find.byKey(const ValueKey('server-connect-button'));

      await tester.enterText(
        find.widgetWithText(TextField, '账本地址'),
        'ledger.example.com:8080',
      );
      await tester.pumpAndSettle();
      expect(find.text('ledger.example.com:8080'), findsWidgets);
      expect(find.text('地址就绪'), findsNothing);
      expect(find.text('需 HTTPS'), findsNothing);
      expect(find.text('公开域名'), findsNothing);
      expect(find.text('部署就绪检查'), findsNothing);
      expect(find.text('连接证据 3/4'), findsNothing);
      await _scrollIntoTapArea(tester, connectButton);
      await tester.tap(connectButton);
      await tester.pumpAndSettle();

      expect(controller.connectCalls, ['ledger.example.com:8080']);
      expect(controller.insecureAcknowledgementCalls, [false]);
      expect(controller.debugState.stage, AuthStage.loginRequired);
      expect(find.byType(AuthFlowShell), findsOneWidget);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
      expect(
        find.byKey(const ValueKey('server-connect-button')),
        findsOneWidget,
      );
    });

    testWidgets('私网 HTTP 必须确认风险后才进入连接流程', (tester) async {
      final controller = await _pumpPage(tester);
      final connectButton = find.byKey(const ValueKey('server-connect-button'));

      await tester.enterText(
        find.widgetWithText(TextField, '账本地址'),
        'http://192.168.1.20:8080',
      );
      await _scrollIntoTapArea(tester, connectButton);
      await tester.tap(connectButton);
      await tester.pumpAndSettle();

      expect(find.text('局域网 HTTP 风险'), findsOneWidget);
      expect(find.textContaining('未加密的 HTTP'), findsOneWidget);
      expect(controller.connectCalls, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, '继续连接'));
      await tester.pumpAndSettle();

      expect(controller.connectCalls, ['http://192.168.1.20:8080']);
      expect(controller.insecureAcknowledgementCalls, [true]);
      expect(controller.debugState.stage, AuthStage.loginRequired);
    });

    testWidgets('Android 构建未启用明文传输时拒绝私网 HTTP', (tester) async {
      final controller = await _pumpPage(tester, localHttpPermitted: false);
      final connectButton = find.byKey(const ValueKey('server-connect-button'));

      await tester.enterText(
        find.widgetWithText(TextField, '账本地址'),
        'http://192.168.1.20:8080',
      );
      await _scrollIntoTapArea(tester, connectButton);
      await tester.tap(connectButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('当前 Android 构建未启用明文 HTTP'), findsOneWidget);
      expect(find.text('局域网 HTTP 风险'), findsNothing);
      expect(controller.connectCalls, isEmpty);
    });
  });
}

Future<_TestAuthController> _pumpPage(
  WidgetTester tester, {
  bool localHttpPermitted = true,
}) async {
  late _TestAuthController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        localHttpTransportPolicyProvider.overrideWithValue(
          _FakeLocalHttpTransportPolicy(localHttpPermitted),
        ),
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

class _FakeLocalHttpTransportPolicy extends LocalHttpTransportPolicy {
  const _FakeLocalHttpTransportPolicy(this.permitted);

  final bool permitted;

  @override
  Future<bool> isCleartextTrafficPermitted() async => permitted;
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
  final List<bool> insecureAcknowledgementCalls = [];

  @override
  AuthState get debugState => state;

  @override
  Future<void> connectServer(
    String input, {
    bool acknowledgeInsecureLocalHttp = false,
  }) async {
    connectCalls.add(input);
    insecureAcknowledgementCalls.add(acknowledgeInsecureLocalHttp);
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      state = const AuthState(
        stage: AuthStage.serverRequired,
        errorMessage: '请输入账本地址',
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
  Future<bool> validateSession() async => true;

  @override
  Future<void> logout() async {}
}
