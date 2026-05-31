import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/profile/data/profile_repository.dart';
import 'package:personal_ledger/features/profile/presentation/profile_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProfileSettingsPage', () {
    testWidgets('展示当前个人资料', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      expect(find.text('个人资料'), findsOneWidget);
      expect(find.text('Sky'), findsWidgets);
      expect(find.text('用户名：admin'), findsOneWidget);
      expect(find.text('创建时间：2026-05-01'), findsOneWidget);
    });

    testWidgets('个人资料摘要和表单使用高级表面与入场动效', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(3));
      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(3));
    });

    testWidgets('个人资料设置页可直接切换主题模式和主题色模板', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-settings-theme-panel')),
        360,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-settings-theme-panel')),
        findsOneWidget,
      );
      expect(find.text('设置主题中心'), findsOneWidget);
      expect(find.text('当前模板'), findsOneWidget);
      expect(find.text('模板数量'), findsOneWidget);
      expect(find.text('16 套'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-settings-theme-studio')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-settings-theme-curation-rail')),
        findsOneWidget,
      );
      expect(find.text('推荐主题策展'), findsOneWidget);
      expect(find.text('3 个高频场景'), findsOneWidget);
      expect(find.text('旗舰夜间使用'), findsWidgets);
      expect(find.text('前卫数据流'), findsWidgets);
      expect(find.text('动效先锋界面'), findsWidgets);
      expect(find.text('模式同步'), findsOneWidget);
      expect(find.text('语义色板'), findsOneWidget);
      expect(find.text('跨端预览'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-settings-theme-template-matrix')),
        findsOneWidget,
      );
      expect(find.text('模板适配矩阵'), findsOneWidget);
      expect(find.text('点按切换'), findsOneWidget);
      expect(find.text('日常记账'), findsOneWidget);
      expect(find.text('家庭账本'), findsOneWidget);
      expect(find.text('AI 分析'), findsOneWidget);
      expect(find.text('夜间高频'), findsOneWidget);
      expect(find.text('跨端高频交互'), findsOneWidget);
      expect(find.text('极简旗舰设备'), findsOneWidget);
      expect(find.text('高端暗金'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('profile-settings-template-indigo')),
      );
      await tester.pumpAndSettle();
      var preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_theme_palette'), 'indigo');
      expect(find.text('深海靛蓝'), findsWidgets);
      expect(
        find.byKey(const ValueKey('profile-settings-theme-semantic-preview')),
        findsOneWidget,
      );
      expect(find.text('财务语义预览'), findsOneWidget);
      expect(find.text('周报高光'), findsOneWidget);
      expect(find.text('预算状态'), findsOneWidget);
      expect(find.text('收入色'), findsOneWidget);
      expect(find.text('资产色'), findsOneWidget);
      expect(find.text('支出色'), findsOneWidget);
      expect(find.text('警示色'), findsOneWidget);
      expect(find.text('浅色模式'), findsOneWidget);
      expect(find.text('黑曜蓝'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('profile-settings-featured-theme-plasma')),
      );
      await tester.pumpAndSettle();
      preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_theme_palette'), 'plasma');
      expect(find.text('电浆蓝'), findsWidgets);

      await tester.tap(find.text('深色模式'));
      await tester.pumpAndSettle();
      preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_theme_mode'), AppThemeMode.dark.name);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-settings-theme-obsidian')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('profile-settings-theme-obsidian')),
          matching: find.byType(Semantics),
        ),
        findsWidgets,
      );
      await tester.tap(
        find.byKey(const ValueKey('profile-settings-theme-obsidian')),
      );
      await tester.pumpAndSettle();

      preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('app_theme_palette'), 'obsidian');
      expect(find.text('当前模板'), findsOneWidget);
      expect(find.text('黑曜蓝'), findsWidgets);
      expect(find.text('旗舰暗色'), findsWidgets);
    });

    testWidgets('个人资料头部展示身份状态摘要', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      expect(find.text('账号 ID'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('联系方式'), findsOneWidget);
      expect(find.text('已绑定'), findsWidgets);
      expect(find.text('登录状态'), findsOneWidget);
      expect(find.text('有记录'), findsWidgets);
      expect(find.text('身份状态轨道'), findsOneWidget);
      expect(find.text('身份可识别'), findsOneWidget);
      expect(find.text('身份'), findsOneWidget);
      expect(find.text('联系'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-identity-rail')),
        findsOneWidget,
      );
      expect(find.text('资料完整度'), findsOneWidget);
      expect(find.text('3/4'), findsOneWidget);
      expect(find.text('昵称'), findsAtLeastNWidgets(1));
      expect(find.text('邮箱'), findsAtLeastNWidgets(1));
      expect(find.text('头像'), findsOneWidget);
      expect(find.text('简介'), findsAtLeastNWidgets(1));
    });

    testWidgets('资料完整度根据缺失字段降级展示', (tester) async {
      final repository = _FakeProfileRepository()
        ..profile = _profile(nickname: '', email: '', bio: '');
      await _pumpPage(tester, repository);

      expect(find.text('资料完整度'), findsOneWidget);
      expect(find.text('资料待完善'), findsOneWidget);
      expect(find.text('0/4'), findsOneWidget);
    });

    testWidgets('保存资料时提交当前输入', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('profile-nickname')),
        'Sky New',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-email')),
        'new@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-avatar')),
        'https://example.com/new.png',
      );
      await tester.enterText(find.byKey(const ValueKey('profile-bio')), '继续记账');
      await tester.ensureVisible(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.nickname, 'Sky New');
      expect(repository.updateCalls.single.email, 'new@example.com');
      expect(
        repository.updateCalls.single.avatar,
        'https://example.com/new.png',
      );
      expect(repository.updateCalls.single.bio, '继续记账');
      expect(find.text('个人资料已保存'), findsOneWidget);
      expect(find.text('Sky New'), findsWidgets);
    });

    testWidgets('邮箱格式不正确时不提交保存', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('profile-email')),
        'invalid-email',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, isEmpty);
      expect(find.text('邮箱格式不正确'), findsOneWidget);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeProfileRepository()..getProfileErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('个人资料加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('Sky'), findsWidgets);
      expect(repository.getProfileCalls, 2);
    });

    testWidgets('保存失败时展示错误且保留输入', (tester) async {
      final repository = _FakeProfileRepository()..updateProfileError = '保存失败';
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('profile-nickname')),
        'Sky Failed',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(find.text('Sky Failed'), findsOneWidget);
      expect(find.textContaining('保存失败'), findsOneWidget);
    });

    testWidgets('刷新资料会恢复服务端最新数据', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('profile-nickname')),
        '本地草稿',
      );
      repository.profile = _profile(nickname: 'Server Sky');

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();

      expect(find.text('Server Sky'), findsWidgets);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('profile-nickname')),
      );
      expect(field.controller?.text, 'Server Sky');
      expect(repository.getProfileCalls, 2);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeProfileRepository repository,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: ProfileSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeProfileRepository implements ProfileRepository {
  var profile = _profile();
  var getProfileCalls = 0;
  var getProfileErrors = 0;
  String? updateProfileError;

  final List<UpdateProfileRequest> updateCalls = [];

  @override
  Future<UserProfile> getProfile() async {
    getProfileCalls += 1;
    if (getProfileErrors > 0) {
      getProfileErrors -= 1;
      throw StateError('个人资料加载失败');
    }
    return profile;
  }

  @override
  Future<UserProfile> updateProfile(UpdateProfileRequest request) async {
    updateCalls.add(request);
    final error = updateProfileError;
    if (error != null) {
      throw StateError(error);
    }
    profile = UserProfile(
      id: profile.id,
      username: profile.username,
      nickname: request.nickname,
      email: request.email,
      avatar: request.avatar,
      bio: request.bio,
      createdAt: profile.createdAt,
      lastLoginAt: profile.lastLoginAt,
    );
    return profile;
  }
}

UserProfile _profile({
  String nickname = 'Sky',
  String email = 'sky@example.com',
  String avatar = '',
  String bio = '记账中',
}) {
  return UserProfile(
    id: 1,
    username: 'admin',
    nickname: nickname,
    email: email,
    avatar: avatar,
    bio: bio,
    createdAt: '2026-05-01',
    lastLoginAt: '2026-05-17 09:00:00',
  );
}
