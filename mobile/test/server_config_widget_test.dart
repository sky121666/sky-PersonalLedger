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

      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();

      expect(controller.connectCalls, ['']);
      expect(find.text('请输入服务器地址'), findsOneWidget);
      expect(find.text('连接服务器'), findsOneWidget);
      expect(find.text('自托管入口'), findsOneWidget);
      expect(find.byType(AuthFlowShell), findsOneWidget);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
    });

    testWidgets('提交服务器地址时调用连接流程', (tester) async {
      final controller = await _pumpPage(tester);

      await tester.enterText(
        find.widgetWithText(TextField, '服务器地址'),
        'ledger.example.com:8080',
      );
      await tester.tap(find.text('连接'));
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
