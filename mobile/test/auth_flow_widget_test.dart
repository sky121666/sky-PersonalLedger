import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/auth_flow_shell.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/auth/presentation/login_page.dart';
import 'package:personal_ledger/features/auth/presentation/setup_password_page.dart';
import 'package:personal_ledger/features/profile/presentation/profile_page.dart';

void main() {
  group('LoginPage', () {
    testWidgets('密码为空时显示本地校验错误且不发起登录', (tester) async {
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

      await tester.tap(find.text('登录').last);
      await tester.pump();

      expect(find.text('请输入密码'), findsOneWidget);
      expect(repository.loginCalls, isEmpty);
      expect(find.byType(AuthFlowShell), findsOneWidget);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
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
      await tester.tap(find.text('登录').last);
      await tester.pump();

      expect(repository.loginCalls, ['123456']);
      expect(controller.debugState.stage, AuthStage.authenticated);
      expect(find.text('账本解锁'), findsOneWidget);
      expect(find.text('登录'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('auth-login-password-visibility-toggle')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('auth-login-password-visibility-toggle')),
      );
      await tester.pump();
      final passwordVisibilityButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('auth-login-password-visibility-toggle')),
      );
      expect(
        (passwordVisibilityButton.icon as Icon).icon,
        Icons.visibility_off,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '账本解锁，登录',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == '登录 表单',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('login-session-evidence-rail')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('login-access-matrix')), findsNothing);
      expect(find.text('访问控制矩阵'), findsNothing);
      expect(find.text('会话解锁信号'), findsNothing);
      expect(find.text('密码闸门'), findsNothing);
      expect(find.byKey(const ValueKey('auth-experience-deck')), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  '跨端安全控制台，私有服务，iOS 动效，Android 状态层，主题色联动',
        ),
        findsNothing,
      );
      expect(find.text('跨端安全控制台'), findsNothing);
      expect(find.text('iOS 动效'), findsNothing);
      expect(find.text('Android 状态层'), findsNothing);
      expect(find.text('主题色联动'), findsNothing);
    });

    testWidgets('登录页在手机布局下保持首屏靠上', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpAuthPage(
        tester,
        const LoginPage(),
        repository: _FakeAuthRepository(),
        state: const AuthState(
          stage: AuthStage.loginRequired,
          serverUrl: 'https://ledger.example.com',
          initialized: true,
        ),
      );

      final titleTop = tester.getTopLeft(find.text('账本解锁')).dy;
      expect(titleTop, lessThan(220));
    });
  });

  group('SetupPasswordPage', () {
    testWidgets('未初始化账本引导浏览器设置，不展示无法提交令牌的密码表单', (tester) async {
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

      expect(find.text('先在浏览器初始化'), findsOneWidget);
      expect(find.textContaining('初始化令牌'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey('auth-setup-copy-address')),
        findsOneWidget,
      );
      expect(repository.initCalls, isEmpty);
    });

    testWidgets('浏览器完成初始化后重新检查进入登录，不尝试再次初始化', (tester) async {
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
      final button = find.byKey(const ValueKey('auth-setup-recheck-button'));
      await _scrollIntoTapArea(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(controller.debugState.stage, AuthStage.loginRequired);
      expect(repository.initCalls, isEmpty);
      expect(repository.loginCalls, isEmpty);
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

      await tester.tap(find.byKey(const ValueKey('profile-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '退出'));
      await tester.pumpAndSettle();

      expect(repository.logoutCalls, 1);
      expect(controller.debugState.stage, AuthStage.loginRequired);
    });

    testWidgets('确认更换账本时回到连接配置态', (tester) async {
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

      await tester.pumpAndSettle();
      final changeServerEntry = find.byKey(
        const ValueKey('profile-entry-更换账本'),
      );
      await _scrollIntoTapArea(tester, changeServerEntry);
      await tester.tap(changeServerEntry);
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
  Future<void> bootstrap() async {
    final status = await _repository.getStatus();
    state = state.copyWith(
      stage: status.initialized
          ? AuthStage.loginRequired
          : AuthStage.setupRequired,
      initialized: status.initialized,
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
  Future<bool> validateSession() async => true;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
