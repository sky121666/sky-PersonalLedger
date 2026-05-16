import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/auth/presentation/login_page.dart';
import 'package:personal_ledger/features/auth/presentation/setup_password_page.dart';
import 'package:personal_ledger/features/profile/presentation/profile_page.dart';

void main() {
  group('LoginPage', () {
    testWidgets('密码少于 6 位时显示本地校验错误且不发起登录', (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpAuthPage(
        tester,
        const LoginPage(),
        repository: repository,
        state: const AuthState(
          stage: AuthStage.loginRequired,
          serverUrl: 'https://ledger.example.com',
          initialized: true,
        ),
      );

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('登录'));
      await tester.pump();

      expect(find.text('密码至少需要 6 位'), findsOneWidget);
      expect(repository.loginCalls, isEmpty);
    });

    testWidgets('输入有效密码后调用登录并进入 authenticated', (tester) async {
      final repository = _FakeAuthRepository();
      final controller = await _pumpAuthPage(
        tester,
        const LoginPage(),
        repository: repository,
        state: const AuthState(
          stage: AuthStage.loginRequired,
          serverUrl: 'https://ledger.example.com',
          initialized: true,
        ),
      );

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('登录'));
      await tester.pump();

      expect(repository.loginCalls, ['123456']);
      expect(controller.debugState.stage, AuthStage.authenticated);
    });
  });

  group('SetupPasswordPage', () {
    testWidgets('两次密码不一致时显示错误且不提交初始化', (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpAuthPage(
        tester,
        const SetupPasswordPage(),
        repository: repository,
        state: const AuthState(
          stage: AuthStage.setupRequired,
          serverUrl: 'https://ledger.example.com',
          initialized: false,
        ),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), '654321');
      await tester.tap(find.text('完成设置'));
      await tester.pump();

      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(repository.initCalls, isEmpty);
    });

    testWidgets('首次设置有效密码后调用初始化并进入 authenticated', (tester) async {
      final repository = _FakeAuthRepository();
      final controller = await _pumpAuthPage(
        tester,
        const SetupPasswordPage(),
        repository: repository,
        state: const AuthState(
          stage: AuthStage.setupRequired,
          serverUrl: 'https://ledger.example.com',
          initialized: false,
        ),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '123456');
      await tester.enterText(fields.at(1), '123456');
      await tester.tap(find.text('完成设置'));
      await tester.pump();

      expect(repository.initCalls, ['123456']);
      expect(controller.debugState.stage, AuthStage.authenticated);
    });
  });

  group('ProfilePage', () {
    testWidgets('确认退出时调用 logout 并回到登录态', (tester) async {
      final repository = _FakeAuthRepository();
      final controller = await _pumpAuthPage(
        tester,
        const ProfilePage(),
        repository: repository,
        state: const AuthState(
          stage: AuthStage.authenticated,
          serverUrl: 'https://ledger.example.com',
          initialized: true,
        ),
      );

      await tester.tap(find.byTooltip('退出登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '退出'));
      await tester.pumpAndSettle();

      expect(repository.logoutCalls, 1);
      expect(controller.debugState.stage, AuthStage.loginRequired);
    });

    testWidgets('确认更换服务器时回到服务器配置态', (tester) async {
      final repository = _FakeAuthRepository();
      final controller = await _pumpAuthPage(
        tester,
        const ProfilePage(),
        repository: repository,
        state: const AuthState(
          stage: AuthStage.authenticated,
          serverUrl: 'https://ledger.example.com',
          initialized: true,
        ),
      );

      await tester.tap(find.text('更换服务器'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '更换'));
      await tester.pumpAndSettle();

      expect(controller.debugState.stage, AuthStage.serverRequired);
    });
  });
}

Future<_TestAuthController> _pumpAuthPage(
  WidgetTester tester,
  Widget child, {
  required _FakeAuthRepository repository,
  required AuthState state,
}) async {
  late _TestAuthController controller;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith((ref) {
          controller = _TestAuthController(
            ref,
            repository: repository,
            initialState: state,
          );
          return controller;
        }),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(authControllerProvider);
          return MaterialApp(home: child);
        },
      ),
    ),
  );

  return controller;
}

class _TestAuthController extends AuthController {
  _TestAuthController(
    super.ref, {
    required _FakeAuthRepository repository,
    required AuthState initialState,
  }) : _repository = repository {
    state = initialState;
  }

  final _FakeAuthRepository _repository;

  @override
  AuthState get debugState => state;

  @override
  Future<void> login(String password) async {
    state = state.copyWith(stage: AuthStage.checking, clearError: true);
    final tokenPair = await _repository.login(password);
    state = state.copyWith(
      stage: tokenPair.isValid
          ? AuthStage.authenticated
          : AuthStage.loginRequired,
      errorMessage: tokenPair.isValid ? null : '认证响应无效',
    );
  }

  @override
  Future<void> setupPassword(String password) async {
    state = state.copyWith(stage: AuthStage.checking, clearError: true);
    final tokenPair = await _repository.init(password);
    state = state.copyWith(
      stage: tokenPair.isValid
          ? AuthStage.authenticated
          : AuthStage.setupRequired,
      errorMessage: tokenPair.isValid ? null : '认证响应无效',
    );
  }

  @override
  Future<void> changeServer() async {
    state = const AuthState(stage: AuthStage.serverRequired);
  }

  @override
  Future<void> logout() async {
    await _repository.logout();
    state = state.copyWith(stage: AuthStage.loginRequired, clearError: true);
  }
}

class _FakeAuthRepository implements AuthRepository {
  final List<String> loginCalls = [];
  final List<String> initCalls = [];
  int logoutCalls = 0;

  @override
  Future<AuthStatus> getStatus() async {
    return const AuthStatus(initialized: true);
  }

  @override
  Future<AuthTokenPair> init(String password) async {
    initCalls.add(password);
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<AuthTokenPair> login(String password) async {
    loginCalls.add(password);
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
