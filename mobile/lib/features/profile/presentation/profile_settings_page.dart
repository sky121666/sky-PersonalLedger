import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../data/profile_repository.dart';

class ProfileSettingsPage extends ConsumerStatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  ConsumerState<ProfileSettingsPage> createState() =>
      _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends ConsumerState<ProfileSettingsPage> {
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _avatarController = TextEditingController();
  final _bioController = TextEditingController();

  UserProfile? _profile;
  var _loading = true;
  var _submitting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadProfile);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _avatarController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ref.read(profileRepositoryProvider).getProfile();
      if (!mounted) {
        return;
      }
      _applyProfile(profile);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      _showMessage('邮箱格式不正确');
      return;
    }

    setState(() => _submitting = true);
    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            UpdateProfileRequest(
              nickname: _nicknameController.text.trim(),
              email: email,
              avatar: _avatarController.text.trim(),
              bio: _bioController.text.trim(),
            ),
          );
      if (!mounted) {
        return;
      }
      _applyProfile(saved);
      _showMessage('个人资料已保存');
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _applyProfile(UserProfile profile) {
    setState(() {
      _profile = profile;
      _nicknameController.text = profile.nickname;
      _emailController.text = profile.email;
      _avatarController.text = profile.avatar;
      _bioController.text = profile.bio;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人资料'),
        actions: [
          IconButton(
            onPressed: _submitting ? null : _loadProfile,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: AdaptivePageContainer(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingView(message: '个人资料加载中...');
    }
    final error = _error;
    if (error != null) {
      return AppErrorView(message: error.toString(), onRetry: _loadProfile);
    }
    final profile = _profile;
    if (profile == null) {
      return const AppEmptyView(
        title: '暂无个人资料',
        message: '刷新后重试。',
        icon: Icons.manage_accounts_outlined,
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _ProfileHeader(profile: profile),
        const SizedBox(height: 16),
        _ProfileFormCard(
          nicknameController: _nicknameController,
          emailController: _emailController,
          avatarController: _avatarController,
          bioController: _bioController,
          submitting: _submitting,
          onSubmit: _saveProfile,
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _ProfileAvatar(profile: profile),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '用户名：${profile.username}',
                    style: TextStyle(color: colorScheme.onPrimaryContainer),
                  ),
                  if (profile.createdAt.isNotEmpty)
                    Text(
                      '创建时间：${profile.createdAt}',
                      style: TextStyle(color: colorScheme.onPrimaryContainer),
                    ),
                  if (profile.lastLoginAt?.isNotEmpty ?? false)
                    Text(
                      '上次登录：${profile.lastLoginAt}',
                      style: TextStyle(color: colorScheme.onPrimaryContainer),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile});

  final UserProfile profile;

  String get _fallbackText {
    return profile.displayName.isEmpty ? '账' : profile.displayName[0];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: 28,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      child: Text(_fallbackText),
    );
    if (profile.avatar.isEmpty) {
      return fallback;
    }
    return ClipOval(
      child: Image.network(
        profile.avatar,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

class _ProfileFormCard extends StatelessWidget {
  const _ProfileFormCard({
    required this.nicknameController,
    required this.emailController,
    required this.avatarController,
    required this.bioController,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController nicknameController;
  final TextEditingController emailController;
  final TextEditingController avatarController;
  final TextEditingController bioController;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('编辑资料', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('profile-nickname'),
              controller: nicknameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '昵称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('profile-email'),
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '邮箱',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('profile-avatar'),
              controller: avatarController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '头像 URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('profile-bio'),
              controller: bioController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '简介',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('profile-save'),
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(submitting ? '保存中...' : '保存资料'),
            ),
          ],
        ),
      ),
    );
  }
}
