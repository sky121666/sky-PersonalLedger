import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(find.text('安全入口'), findsOneWidget);
      expect(find.text('/ledger'), findsWidgets);
      expect(find.text('当前入口：/ledger'), findsOneWidget);
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
      expect(find.text('当前入口：/private'), findsOneWidget);
      expect(find.text('安全入口已保存'), findsOneWidget);
    });

    testWidgets('随机生成入口后刷新文本框和状态', (tester) async {
      final repository = _FakeSecurityRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const ValueKey('security-entry-generate')));
      await tester.pumpAndSettle();

      expect(repository.generateCalls, 1);
      expect(find.text('/generated'), findsWidgets);
      expect(find.text('已生成随机入口'), findsOneWidget);
    });

    testWidgets('修改密码成功后退出当前登录态', (tester) async {
      final repository = _FakeSecurityRepository();
      final authRepository = _FakeAuthRepository();
      final controller = await _pumpPage(
        tester,
        repository,
        authRepository: authRepository,
      );

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
      expect(authRepository.logoutCalls, 1);
      expect(controller.debugState.stage, AuthStage.loginRequired);
      expect(find.text('密码已修改，请重新登录'), findsOneWidget);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeSecurityRepository()..getEntryPathErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('安全入口加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('当前入口：/ledger'), findsOneWidget);
      expect(repository.getEntryPathCalls, 2);
    });

    testWidgets('保存入口失败时展示错误且保留输入', (tester) async {
      final repository = _FakeSecurityRepository()
        ..setEntryPathError = '保存失败';
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('security-entry-path')),
        '/private',
      );
      await tester.tap(find.byKey(const ValueKey('security-entry-save')));
      await tester.pumpAndSettle();

      expect(repository.setEntryPathCalls, ['/private']);
      expect(find.text('/private'), findsOneWidget);
      expect(find.text('当前入口：/ledger'), findsOneWidget);
      expect(find.textContaining('保存失败'), findsOneWidget);
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

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();

      expect(find.text('/server'), findsWidgets);
      expect(find.text('当前入口：/server'), findsOneWidget);
      expect(repository.getEntryPathCalls, 2);
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
      expect(find.textContaining('密码错误'), findsOneWidget);
      expect(find.text('old-password'), findsOneWidget);
    });
  });
}

Future<_TestAuthController> _pumpPage(
  WidgetTester tester,
  _FakeSecurityRepository repository, {
  _FakeAuthRepository? authRepository,
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
          return const MaterialApp(home: SecuritySettingsPage());
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
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
