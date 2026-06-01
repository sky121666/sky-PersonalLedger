import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/profile/presentation/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ProfilePage 展示主要设置入口并可进入目标页面', (tester) async {
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

    expect(
      find.byKey(const ValueKey('profile-command-center')),
      findsOneWidget,
    );
    expect(find.text('个人控制中枢 · 静谧墨绿'), findsOneWidget);
    expect(find.text('主题模板'), findsAtLeastNWidgets(1));
    expect(find.text('默认稳健'), findsAtLeastNWidgets(1));
    expect(find.text('显示模式'), findsOneWidget);
    expect(find.text('能力入口'), findsOneWidget);
    expect(find.text('家庭账本'), findsOneWidget);
    expect(find.text('AI 周报'), findsOneWidget);
    expect(find.text('安全中心'), findsOneWidget);
    expect(find.text('数据资产'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-route-governance-rail')),
      findsOneWidget,
    );
    expect(find.text('路由入口 16'), findsOneWidget);
    expect(find.text('本机操作 1'), findsOneWidget);
    expect(find.text('主题模板 16'), findsOneWidget);
    expect(find.text('入口治理'), findsOneWidget);

    for (final label in _entryLabels) {
      final labelFinder = find.text(label);
      if (labelFinder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          labelFinder,
          160,
          scrollable: find.byType(Scrollable).first,
        );
      }
      expect(labelFinder, findsAtLeastNWidgets(1));
      if (label == '家庭成员') {
        expect(
          find.byKey(const ValueKey('profile-entry-家庭成员')),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('profile-entry-家庭成员')),
            matching: find.byType(Semantics),
          ),
          findsWidgets,
        );
      }
    }

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
      find.text('深色模式'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('深色模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-featured-theme-aurora')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-featured-theme-aurora')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('profile-featured-theme-aurora')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-featured-selected-aurora')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-theme-selected-aurora')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-theme-selected-roles-aurora')),
      findsOneWidget,
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_theme_mode'), AppThemeMode.dark.name);
    expect(preferences.getString('app_theme_palette'), 'aurora');
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('个人控制中枢 · 极光青'), findsOneWidget);
    expect(find.text('前卫清透'), findsAtLeastNWidgets(1));
    expect(find.text('当前已应用：极光青'), findsOneWidget);
    expect(find.text('模板矩阵'), findsOneWidget);
    expect(find.text('16 套'), findsOneWidget);
    expect(find.text('当前模板'), findsOneWidget);
    expect(find.text('体验定位'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-theme-constellation')),
      findsOneWidget,
    );
    expect(find.text('主题星图'), findsOneWidget);
    expect(find.text('16 套模板'), findsOneWidget);
    expect(find.text('收入 / 资产 / 支出'), findsOneWidget);
    expect(find.text('模式控制'), findsOneWidget);
    expect(find.text('财务语义'), findsOneWidget);
    expect(find.text('4 色'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-theme-curation-rail')),
      findsOneWidget,
    );
    expect(find.text('推荐主题策展'), findsOneWidget);
    expect(find.text('快速切换'), findsOneWidget);
    expect(find.text('旗舰夜间使用'), findsOneWidget);
    expect(find.text('前卫数据流'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('profile-featured-theme-aurora')),
        matching: find.byType(Semantics),
      ),
      findsWidgets,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-theme-option-aurora')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('profile-theme-option-aurora')),
        matching: find.byType(Semantics),
      ),
      findsWidgets,
    );
    expect(find.text('动效先锋界面'), findsOneWidget);
    expect(find.text('跨端体验预览'), findsOneWidget);
    expect(find.text('iOS 原生感'), findsAtLeastNWidgets(1));
    expect(find.text('Android 动效'), findsAtLeastNWidgets(1));
    expect(find.text('数据看板'), findsAtLeastNWidgets(1));
    expect(find.text('AI 报告'), findsAtLeastNWidgets(1));
    expect(find.text('收入色'), findsOneWidget);
    expect(find.text('资产色'), findsOneWidget);
    expect(find.text('支出色'), findsOneWidget);
    expect(find.text('警示色'), findsOneWidget);
    expect(find.text('预算洞察输入框'), findsOneWidget);
    expect(find.text('分析'), findsOneWidget);
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
    expect(badgeColors, contains(AppThemePalette.graphite.assetColor));
    expect(badgeColors, contains(AppThemePalette.graphite.incomeColor));
    expect(badgeColors, contains(AppThemePalette.graphite.expenseColor));
    expect(badgeColors, contains(theme.colorScheme.primary));
    expect(badgeColors, contains(theme.colorScheme.tertiary));
  });

  testWidgets('ProfilePage 设置分区和主题模板使用分段入场动效', (tester) async {
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

    expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(5));
  });
}

const _entryLabels = [
  '个人资料',
  '账户管理',
  '账户流水',
  '分类管理',
  '标签管理',
  '快捷模板',
  '预算管理',
  '负债管理',
  '借贷往来',
  '通知设置',
  '账号安全',
  'API Token',
  '数据管理',
  '家庭成员',
  'AI 财务报告',
  '年度报告',
  '更换服务器',
  '外观模式',
  '主题色模板',
  '模板矩阵',
  '模式控制',
  '财务语义',
  '预算洞察输入框',
  '静谧墨绿',
  '石墨蓝',
  '冰川青',
  '星云紫',
  '曜石玫瑰',
  '钛金灰',
  '极光青',
  '黑曜蓝',
  '电浆蓝',
  '前卫清透',
  '旗舰暗色',
  '动效先锋',
];

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
  Future<void> logout() async {}
}
