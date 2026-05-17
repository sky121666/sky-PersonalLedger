import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  var profile = const UserProfile(
    id: 1,
    username: 'admin',
    nickname: 'Sky',
    email: 'sky@example.com',
    avatar: '',
    bio: '记账中',
    createdAt: '2026-05-01',
    lastLoginAt: '2026-05-17 09:00:00',
  );

  final List<UpdateProfileRequest> updateCalls = [];

  @override
  Future<UserProfile> getProfile() async {
    return profile;
  }

  @override
  Future<UserProfile> updateProfile(UpdateProfileRequest request) async {
    updateCalls.add(request);
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
