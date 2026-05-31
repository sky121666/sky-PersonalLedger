import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
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
      return const StaggeredEntrance(
        index: 0,
        child: AppEmptyView(
          title: '暂无个人资料',
          message: '刷新后重试。',
          icon: Icons.manage_accounts_outlined,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        StaggeredEntrance(index: 0, child: _ProfileHeader(profile: profile)),
        const SizedBox(height: 16),
        StaggeredEntrance(
          index: 1,
          child: _ProfileFormCard(
            nicknameController: _nicknameController,
            emailController: _emailController,
            avatarController: _avatarController,
            bioController: _bioController,
            submitting: _submitting,
            onSubmit: _saveProfile,
          ),
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
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '用户名：${profile.username}',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    if (profile.createdAt.isNotEmpty)
                      Text(
                        '创建时间：${profile.createdAt}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    if (profile.lastLoginAt?.isNotEmpty ?? false)
                      Text(
                        '上次登录：${profile.lastLoginAt}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ProfileSignalTile(
                  icon: Icons.badge_outlined,
                  label: '账号 ID',
                  value: '#${profile.id}',
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileSignalTile(
                  icon: Icons.alternate_email_outlined,
                  label: '联系方式',
                  value: profile.email.isEmpty ? '未绑定' : '已绑定',
                  color: financeColors.asset,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileSignalTile(
                  icon: Icons.verified_user_outlined,
                  label: '登录状态',
                  value: (profile.lastLoginAt?.isNotEmpty ?? false)
                      ? '有记录'
                      : '待同步',
                  color: financeColors.income,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSignalTile extends StatelessWidget {
  const _ProfileSignalTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.edit_note_outlined,
                color: colorScheme.tertiary,
                size: 40,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '编辑资料',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ProfileDraftPreview(
            nicknameController: nicknameController,
            emailController: emailController,
            avatarController: avatarController,
          ),
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
    );
  }
}

class _ProfileDraftPreview extends StatelessWidget {
  const _ProfileDraftPreview({
    required this.nicknameController,
    required this.emailController,
    required this.avatarController,
  });

  final TextEditingController nicknameController;
  final TextEditingController emailController;
  final TextEditingController avatarController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        nicknameController,
        emailController,
        avatarController,
      ]),
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final displayName = nicknameController.text.trim().isEmpty
            ? '未设置昵称'
            : nicknameController.text.trim();
        final email = emailController.text.trim().isEmpty
            ? '未设置邮箱'
            : emailController.text.trim();
        final avatar = avatarController.text.trim();
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.tertiary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.tertiary.withValues(alpha: 0.18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _DraftAvatar(displayName: displayName, avatar: avatar),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '资料预览',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colorScheme.tertiary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '当前昵称：$displayName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DraftAvatar extends StatelessWidget {
  const _DraftAvatar({required this.displayName, required this.avatar});

  final String displayName;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: 25,
      backgroundColor: colorScheme.tertiary,
      foregroundColor: colorScheme.onTertiary,
      child: Text(displayName.isEmpty ? '账' : displayName[0]),
    );
    if (avatar.isEmpty) {
      return fallback;
    }
    return ClipOval(
      child: Image.network(
        avatar,
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
