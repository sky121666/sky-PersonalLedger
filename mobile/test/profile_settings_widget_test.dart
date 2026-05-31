import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/profile/data/profile_repository.dart';
import 'package:personal_ledger/features/profile/presentation/profile_settings_page.dart';

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

      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(2));
      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(2));
    });

    testWidgets('个人资料头部展示身份状态摘要', (tester) async {
      final repository = _FakeProfileRepository();
      await _pumpPage(tester, repository);

      expect(find.text('账号 ID'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('联系方式'), findsOneWidget);
      expect(find.text('已绑定'), findsOneWidget);
      expect(find.text('登录状态'), findsOneWidget);
      expect(find.text('有记录'), findsOneWidget);
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

UserProfile _profile({String nickname = 'Sky'}) {
  return UserProfile(
    id: 1,
    username: 'admin',
    nickname: nickname,
    email: 'sky@example.com',
    avatar: '',
    bio: '记账中',
    createdAt: '2026-05-01',
    lastLoginAt: '2026-05-17 09:00:00',
  );
}
