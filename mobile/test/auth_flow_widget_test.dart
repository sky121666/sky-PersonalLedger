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
      await tester.tap(find.text('登录').last);
      await tester.pump();

      expect(find.text('密码至少需要 6 位'), findsOneWidget);
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
    testWidgets('首次设置密码少于 8 位时显示本地校验错误且不提交初始化', (tester) async {
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
      await tester.enterText(fields.at(0), '1234567');
      await tester.enterText(fields.at(1), '1234567');
      await _scrollIntoTapArea(tester, find.text('完成设置'));
      await tester.tap(find.text('完成设置'));
      await tester.pump();

      expect(find.text('密码至少需要 8 位'), findsOneWidget);
      expect(repository.initCalls, isEmpty);
      expect(find.byType(AuthFlowShell), findsOneWidget);
    });

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
      await tester.enterText(fields.at(0), '12345678');
      await tester.enterText(fields.at(1), '87654321');
      await _scrollIntoTapArea(tester, find.text('完成设置'));
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
      await tester.enterText(fields.at(0), '12345678');
      await tester.enterText(fields.at(1), '12345678');
      await _scrollIntoTapArea(tester, find.text('完成设置'));
      await tester.tap(find.text('完成设置'));
      await tester.pump();

      expect(repository.initCalls, ['12345678']);
      expect(controller.debugState.stage, AuthStage.authenticated);
      expect(find.text('设置密码'), findsOneWidget);
      expect(find.text('账本保护'), findsAtLeastNWidgets(1));
      expect(find.text('初始化密钥策略'), findsNothing);
      expect(
        find.byKey(const ValueKey('auth-setup-password-visibility-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('auth-setup-confirm-password-visibility-toggle'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('auth-setup-password-visibility-toggle')),
      );
      await tester.tap(
        find.byKey(
          const ValueKey('auth-setup-confirm-password-visibility-toggle'),
        ),
      );
      await tester.pump();
      final setupPasswordVisibilityButtonSecond = tester.widget<IconButton>(
        find.byKey(const ValueKey('auth-setup-password-visibility-toggle')),
      );
      final setupPasswordConfirmVisibilityButtonSecond = tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey('auth-setup-confirm-password-visibility-toggle'),
            ),
          );
      expect(
        (setupPasswordVisibilityButtonSecond.icon as Icon).icon,
        Icons.visibility_off,
      );
      expect(
        (setupPasswordConfirmVisibilityButtonSecond.icon as Icon).icon,
        Icons.visibility_off,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '设置密码，账本保护',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '账本保护 表单',
        ),
        findsOneWidget,
      );
      final setupPasswordVisibilityButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('auth-setup-password-visibility-toggle')),
      );
      final setupPasswordConfirmVisibilityButton = tester.widget<IconButton>(
        find.byKey(
          const ValueKey('auth-setup-confirm-password-visibility-toggle'),
        ),
      );
      expect(
        (setupPasswordVisibilityButton.icon as Icon).icon,
        Icons.visibility_off,
      );
      expect(
        (setupPasswordConfirmVisibilityButton.icon as Icon).icon,
        Icons.visibility_off,
      );
      expect(
        find.byKey(const ValueKey('setup-submission-evidence-rail')),
        findsNothing,
      );
      expect(find.text('提交证据'), findsNothing);
      expect(find.text('长度证据'), findsNothing);
      expect(
        find.byKey(const ValueKey('setup-initialization-matrix')),
        findsNothing,
      );
      expect(find.text('初始化控制矩阵'), findsNothing);
      expect(find.byType(AuthFlowShell), findsOneWidget);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
      expect(find.byKey(const ValueKey('auth-experience-deck')), findsNothing);
      expect(find.text('跨端安全控制台'), findsNothing);
      expect(find.text('iOS 动效'), findsNothing);
      expect(find.text('Android 状态层'), findsNothing);
      expect(find.text('主题色联动'), findsNothing);
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
  Future<bool> validateSession() async => true;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
