import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/profile/presentation/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ProfilePage 展示主要设置入口并可进入目标页面', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final authRepository = _FakeAuthRepository();
    final router = GoRouter(
      initialLocation: AppRoutePaths.profile,
      routes: [
        GoRoute(
          path: AppRoutePaths.profile,
          builder: (context, state) => const ProfilePage(),
        ),
        for (final path in _targetPaths)
          GoRoute(path: path, builder: (context, state) => _TargetPage(path)),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          authControllerProvider.overrideWith((ref) {
            return _TestAuthController(ref);
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-command-center')), findsNothing);
    expect(find.text('功能中心'), findsNothing);
    expect(find.byKey(const ValueKey('profile-logout')), findsOneWidget);
    expect(find.text('账本管理、计划提醒、智能数据和安全设置'), findsNothing);
    expect(find.text('账本管理'), findsOneWidget);
    expect(find.text('计划提醒'), findsOneWidget);
    expect(find.text('智能与数据'), findsOneWidget);
    expect(find.text('安全设置'), findsOneWidget);
    expect(find.text('资产配置'), findsNothing);
    expect(find.text('常用功能'), findsNothing);
    expect(find.text('个人控制中枢 · 绿色'), findsNothing);
    expect(find.text('主题模板'), findsNothing);
    expect(find.text('能力入口'), findsNothing);
    expect(find.text('AI 周报'), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-route-governance-rail')),
      findsNothing,
    );
    expect(find.text('路由入口 16'), findsNothing);
    expect(find.text('本机操作 1'), findsNothing);
    expect(find.text('主题模板 16'), findsNothing);
    expect(find.text('入口治理'), findsNothing);
    expect(find.text('系统设置'), findsNothing);
    expect(find.text('访问令牌'), findsNothing);
    expect(find.text('预算'), findsOneWidget);
    expect(find.text('负债提醒'), findsOneWidget);
    expect(find.text('AI 分析'), findsOneWidget);
    expect(find.text('数据备份'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-entry-家庭成员')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-entry-家庭成员')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('profile-entry-家庭成员')),
        matching: find.byType(Semantics),
      ),
      findsWidgets,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-section-安全设置')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('设备授权'), findsOneWidget);
    expect(find.text('更换账本'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-entry-个人资料')),
      -220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-entry-个人资料')));
    await tester.pumpAndSettle();

    expect(find.text(AppRoutePaths.profileSettings), findsOneWidget);
  });

  testWidgets('ProfilePage 可切换外观模式和主题色模板', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final authRepository = _FakeAuthRepository();
    final router = GoRouter(
      initialLocation: AppRoutePaths.profile,
      routes: [
        GoRoute(
          path: AppRoutePaths.profile,
          builder: (context, state) => const ProfilePage(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          authControllerProvider.overrideWith((ref) {
            return _TestAuthController(ref);
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('深色'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('主题'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('绿色').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('青色').last);
    await tester.pumpAndSettle();
    expect(find.text('青色'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_theme_mode'), AppThemeMode.dark.name);
    expect(preferences.getString('app_theme_palette'), 'cyan');
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('个人控制中枢 · 青色'), findsNothing);
    expect(find.text('前卫清透'), findsNothing);
    expect(find.text('当前已应用：青色'), findsNothing);
    expect(find.text('模板矩阵'), findsNothing);
    expect(find.text('16 套'), findsNothing);
    expect(find.text('体验定位'), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-theme-constellation')),
      findsNothing,
    );
    expect(find.text('主题星图'), findsNothing);
    expect(find.text('模式控制'), findsNothing);
    expect(find.text('财务语义'), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-theme-curation-rail')),
      findsNothing,
    );
    expect(find.text('推荐主题策展'), findsNothing);
    expect(find.text('快速切换'), findsNothing);
    expect(find.text('旗舰夜间使用'), findsNothing);
    expect(find.text('前卫数据流'), findsNothing);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('profile-featured-theme-aurora')),
        matching: find.byType(Semantics),
      ),
      findsNothing,
    );
    expect(find.text('动效先锋界面'), findsNothing);
    expect(find.text('跨端体验预览'), findsNothing);
    expect(find.text('iOS 原生感'), findsNothing);
    expect(find.text('Android 动效'), findsNothing);
    expect(find.text('预算洞察输入框'), findsNothing);
  });

  testWidgets('ProfilePage 设置入口跟随主题色模板', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = AppTheme.lightTheme(AppThemePalette.graphite);
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          authControllerProvider.overrideWith((ref) {
            return _TestAuthController(ref);
          }),
        ],
        child: MaterialApp(
          theme: theme,
          darkTheme: AppTheme.darkTheme(AppThemePalette.graphite),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badgeColors = tester
        .widgetList<IconBadge>(find.byType(IconBadge))
        .map((badge) => badge.color)
        .toList();
    expect(badgeColors, contains(AppThemePalette.graphite.incomeColor));
    expect(badgeColors, contains(AppThemePalette.graphite.expenseColor));
    expect(badgeColors, contains(AppThemePalette.graphite.warningColor));
  });

  testWidgets('ProfilePage 设置分区和主题模板保持清晰层级', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          authControllerProvider.overrideWith((ref) {
            return _TestAuthController(ref);
          }),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PremiumSurface), findsAtLeastNWidgets(3));
    expect(find.byKey(const ValueKey('profile-command-center')), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-appearance-panel')),
      findsOneWidget,
    );
  });
}

const _targetPaths = [
  AppRoutePaths.profileSettings,
  AppRoutePaths.accounts,
  AppRoutePaths.accountLogs,
  AppRoutePaths.categories,
  AppRoutePaths.tags,
  AppRoutePaths.templates,
  AppRoutePaths.budgets,
  AppRoutePaths.reminders,
  AppRoutePaths.lendings,
  AppRoutePaths.notifications,
  AppRoutePaths.securitySettings,
  AppRoutePaths.apiTokens,
  AppRoutePaths.dataManagement,
  AppRoutePaths.family,
  AppRoutePaths.aiReports,
  AppRoutePaths.yearlyReport,
];

class _TargetPage extends StatelessWidget {
  const _TargetPage(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(path)));
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref) {
    state = const AuthState(
      stage: AuthStage.authenticated,
      serverUrl: 'https://ledger.example.com',
      initialized: true,
    );
  }

  @override
  AuthState get debugState => state;
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
