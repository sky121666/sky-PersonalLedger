import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/security/data/security_repository.dart';
import 'package:personal_ledger/features/security/presentation/security_settings_page.dart';

void main() {
  group('SecuritySettingsPage', () {
    testWidgets('展示当前安全入口状态', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository);

      expect(find.text('账号安全'), findsOneWidget);
      expect(find.text('安全控制台'), findsNothing);
      expect(find.text('Protected'), findsNothing);
      expect(find.text('安全态势'), findsNothing);
      expect(find.text('修改密码'), findsNothing);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('登录保护'), findsOneWidget);
      expect(find.text('登录入口'), findsOneWidget);
      expect(find.text('入口地址'), findsNothing);
      expect(find.text('/ledger'), findsWidgets);
      final entrySwitchSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('security-entry-enabled-semantics')),
      );
      expect(entrySwitchSemantics.properties.label, '启用登录保护');
      expect(find.text('验证旧密码'), findsNothing);
      expect(find.text('自动退出'), findsNothing);
      expect(
        find.byKey(const ValueKey('security-password-evidence-rail')),
        findsNothing,
      );
      expect(find.text('改密证据 0/3'), findsNothing);
      expect(
        find.byKey(const ValueKey('security-entry-guardrail-panel')),
        findsNothing,
      );
      expect(find.text('入口守护策略'), findsNothing);
      expect(find.byKey(const ValueKey('security-old-password')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('security-open-password-sheet')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('security-old-password')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('security-new-password')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('security-confirm-password')),
        findsOneWidget,
      );
    });

    testWidgets('保存入口路径时提交当前输入', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('security-entry-path')),
        '/private',
      );
      await tester.tap(find.byKey(const ValueKey('security-entry-save')));
      await tester.pumpAndSettle();

      expect(repository.setEntryPathCalls, ['/private']);
      expect(find.text('/private'), findsWidgets);
      expect(find.text('登录保护已保存'), findsOneWidget);
    });

    testWidgets('随机生成入口后刷新文本框和状态', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const ValueKey('security-entry-generate')));
      await tester.pumpAndSettle();

      expect(repository.generateCalls, 1);
      expect(find.text('/generated'), findsWidgets);
      expect(find.text('登录入口已生成'), findsOneWidget);
    });

    testWidgets('修改密码成功后退出当前登录态', (tester) async {
      final repository = _FakeSecurityRepository();
      final authRepository = _FakeAuthRepository();
      final controller = await _pumpPage(
        tester,
        repository,
        authRepository: authRepository,
      );

      await tester.tap(
        find.byKey(const ValueKey('security-open-password-sheet')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('security-old-password')),
        'old-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('security-new-password')),
        'new-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('security-confirm-password')),
        'new-password',
      );
      await tester.pumpAndSettle();
      expect(find.text('改密证据 3/3'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('security-change-password-submit')),
      );
      await tester.pumpAndSettle();

      expect(repository.changePasswordCalls, [
        const _ChangePasswordCall('old-password', 'new-password'),
      ]);
      expect(authRepository.logoutCalls, 1);
      expect(controller.debugState.stage, AuthStage.loginRequired);
      expect(find.text('密码已修改，请重新登录'), findsOneWidget);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeSecurityRepository()..getEntryPathErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.text('安全设置加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('/ledger'), findsWidgets);
      expect(repository.getEntryPathCalls, 2);
    });

    testWidgets('保存入口失败时展示错误且保留输入', (tester) async {
      final repository = _FakeSecurityRepository()..setEntryPathError = '保存失败';
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('security-entry-path')),
        '/private',
      );
      await tester.tap(find.byKey(const ValueKey('security-entry-save')));
      await tester.pumpAndSettle();

      expect(repository.setEntryPathCalls, ['/private']);
      expect(find.text('/private'), findsOneWidget);
      expect(find.text('登录保护保存失败'), findsOneWidget);
    });

    testWidgets('刷新入口会恢复服务端最新路径', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('security-entry-path')),
        '/local-draft',
      );
      repository.entryPath = const SecurityEntryPath(
        entryPath: '/server',
        enabled: true,
      );

      await tester.tap(find.byKey(const ValueKey('security-entry-refresh')));
      await tester.pumpAndSettle();

      expect(find.text('/server'), findsWidgets);
      expect(find.text('/server'), findsWidgets);
      expect(repository.getEntryPathCalls, 2);
    });

    testWidgets('关闭登录保护前展示精简确认', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const ValueKey('security-entry-disable')));
      await tester.pumpAndSettle();

      expect(find.text('关闭登录保护？'), findsOneWidget);
      expect(find.text('登录页将直接显示。'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '禁用'));
      await tester.pumpAndSettle();

      expect(repository.disableCalls, 1);
    });

    testWidgets('修改密码失败时展示错误且保留登录态', (tester) async {
      final repository = _FakeSecurityRepository()
        ..changePasswordError = '密码错误';
      final authRepository = _FakeAuthRepository();
      final controller = await _pumpPage(
        tester,
        repository,
        authRepository: authRepository,
      );

      await tester.tap(
        find.byKey(const ValueKey('security-open-password-sheet')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('security-old-password')),
        'old-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('security-new-password')),
        'new-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('security-confirm-password')),
        'new-password',
      );
      await tester.tap(
        find.byKey(const ValueKey('security-change-password-submit')),
      );
      await tester.pumpAndSettle();

      expect(repository.changePasswordCalls, [
        const _ChangePasswordCall('old-password', 'new-password'),
      ]);
      expect(authRepository.logoutCalls, 0);
      expect(controller.debugState.stage, AuthStage.authenticated);
      expect(find.text('密码修改失败'), findsOneWidget);
      expect(find.text('old-password'), findsOneWidget);
    });

    testWidgets('账号安全页跟随主题色模板', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final surfaces = tester.widgetList<PremiumSurface>(
        find.byType(PremiumSurface),
      );
      expect(
        surfaces.any(
          (surface) =>
              surface.accentColor == AppThemePalette.graphite.assetColor,
        ),
        isTrue,
      );
    });

    testWidgets('账号安全页使用高级表面和清晰操作层级', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('登录保护'), findsOneWidget);
      expect(find.byKey(const ValueKey('security-entry-save')), findsOneWidget);
    });
  });
}

Future<_TestAuthController> _pumpPage(
  WidgetTester tester,
  _FakeSecurityRepository repository, {
  _FakeAuthRepository? authRepository,
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuthRepository = authRepository ?? _FakeAuthRepository();
  late _TestAuthController controller;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        securityRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(fakeAuthRepository),
        authControllerProvider.overrideWith((ref) {
          controller = _TestAuthController(ref, repository: fakeAuthRepository);
          return controller;
        }),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(authControllerProvider);
          return MaterialApp(
            theme: AppTheme.lightTheme(palette),
            darkTheme: AppTheme.darkTheme(palette),
            home: const SecuritySettingsPage(),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _FakeSecurityRepository implements SecurityRepository {
  var entryPath = const SecurityEntryPath(entryPath: '/ledger', enabled: true);
  var getEntryPathCalls = 0;
  var getEntryPathErrors = 0;
  String? setEntryPathError;
  String? changePasswordError;

  final List<String> setEntryPathCalls = [];
  final List<_ChangePasswordCall> changePasswordCalls = [];
  int generateCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    changePasswordCalls.add(_ChangePasswordCall(oldPassword, newPassword));
    final error = changePasswordError;
    if (error != null) {
      throw StateError(error);
    }
  }

  @override
  Future<SecurityEntryPath> disableEntryPath() async {
    disableCalls += 1;
    entryPath = const SecurityEntryPath.disabled();
    return entryPath;
  }

  @override
  Future<SecurityEntryPath> generateEntryPath() async {
    generateCalls += 1;
    entryPath = const SecurityEntryPath(entryPath: '/generated', enabled: true);
    return entryPath;
  }

  @override
  Future<SecurityEntryPath> getEntryPath() async {
    getEntryPathCalls += 1;
    if (getEntryPathErrors > 0) {
      getEntryPathErrors -= 1;
      throw StateError('安全入口加载失败');
    }
    return entryPath;
  }

  @override
  Future<SecurityEntryPath> setEntryPath(String value) async {
    setEntryPathCalls.add(value);
    final error = setEntryPathError;
    if (error != null) {
      throw StateError(error);
    }
    entryPath = SecurityEntryPath(entryPath: value, enabled: true);
    return entryPath;
  }
}

class _ChangePasswordCall {
  const _ChangePasswordCall(this.oldPassword, this.newPassword);

  final String oldPassword;
  final String newPassword;

  @override
  bool operator ==(Object other) {
    return other is _ChangePasswordCall &&
        other.oldPassword == oldPassword &&
        other.newPassword == newPassword;
  }

  @override
  int get hashCode => Object.hash(oldPassword, newPassword);
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref, {required _FakeAuthRepository repository})
    : _repository = repository {
    state = const AuthState(
      stage: AuthStage.authenticated,
      serverUrl: 'https://ledger.example.com',
      initialized: true,
    );
  }

  final _FakeAuthRepository _repository;

  @override
  AuthState get debugState => state;

  @override
  Future<void> logout() async {
    await _repository.logout();
    state = state.copyWith(stage: AuthStage.loginRequired, clearError: true);
  }
}

class _FakeAuthRepository implements AuthRepository {
  int logoutCalls = 0;

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
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
