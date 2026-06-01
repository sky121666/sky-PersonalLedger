import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_mode_controller.dart';
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
  var _avatarUploading = false;
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

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final files = result?.files ?? const <PlatformFile>[];
    final file = files.isEmpty ? null : files.single;
    if (file == null) {
      return;
    }

    setState(() => _avatarUploading = true);
    try {
      final url = await ref.read(profileRepositoryProvider).uploadAvatar(file);
      if (!mounted) {
        return;
      }
      setState(() => _avatarController.text = url);
      _showMessage('头像已上传');
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _avatarUploading = false);
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
    final themeSettings = ref.watch(themeControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人资料'),
        actions: [
          IconButton(
            onPressed: _submitting ? null : _loadProfile,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新个人资料',
          ),
        ],
      ),
      body: AdaptivePageContainer(child: _buildBody(themeSettings)),
    );
  }

  Widget _buildBody(AppThemeSettings themeSettings) {
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
            avatarUploading: _avatarUploading,
            onUploadAvatar: _pickAndUploadAvatar,
            onSubmit: _saveProfile,
          ),
        ),
        const SizedBox(height: 16),
        StaggeredEntrance(
          index: 2,
          child: _ProfileThemePanel(
            settings: themeSettings,
            onModeChanged: _setThemeMode,
            onPaletteChanged: _setThemePalette,
          ),
        ),
      ],
    );
  }

  void _setThemeMode(AppThemeMode? mode) {
    if (mode == null) {
      return;
    }
    HapticFeedback.selectionClick();
    ref.read(themeControllerProvider.notifier).setThemeMode(mode);
    _showMessage('外观模式已切换为${_profileSettingsThemeModeLabel(mode)}');
  }

  void _setThemePalette(AppThemePalette? palette) {
    if (palette == null) {
      return;
    }
    HapticFeedback.selectionClick();
    ref.read(themeControllerProvider.notifier).setPalette(palette);
    _showMessage('主题色已切换为${palette.label}');
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
        ],
      ),
    );
  }
}

class _ProfileThemePanel extends StatelessWidget {
  const _ProfileThemePanel({
    required this.settings,
    required this.onModeChanged,
    required this.onPaletteChanged,
  });

  final AppThemeSettings settings;
  final ValueChanged<AppThemeMode?> onModeChanged;
  final ValueChanged<AppThemePalette?> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      key: const ValueKey('profile-settings-theme-panel'),
      accentColor: palette.seedColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.contrast_outlined,
                color: palette.seedColor,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '外观',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '调整显示模式和主题色。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('跟随系统'),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('浅色模式'),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('深色模式'),
                ),
              ],
              selected: {settings.mode},
              onSelectionChanged: (selection) =>
                  onModeChanged(selection.firstOrNull),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<AppThemePalette>(
            initialValue: settings.palette,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            items: [
              for (final option in AppThemePalette.values)
                DropdownMenuItem(
                  value: option,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProfileThemeSwatches(palette: option),
                      const SizedBox(width: 10),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: onPaletteChanged,
          ),
        ],
      ),
    );
  }
}

String _profileSettingsThemeModeLabel(AppThemeMode mode) {
  return switch (mode) {
    AppThemeMode.system => '跟随系统',
    AppThemeMode.light => '浅色',
    AppThemeMode.dark => '深色',
  };
}

class _ProfileThemeSwatches extends StatelessWidget {
  const _ProfileThemeSwatches({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = [
      palette.seedColor,
      palette.assetColor,
      palette.incomeColor,
      palette.expenseColor,
    ];
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          for (var index = 0; index < colors.length; index += 1)
            Positioned(
              left: (index % 2) * 17,
              top: (index ~/ 2) * 17,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: colors[index],
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.4,
                  ),
                ),
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
    required this.avatarUploading,
    required this.onUploadAvatar,
    required this.onSubmit,
  });

  final TextEditingController nicknameController;
  final TextEditingController emailController;
  final TextEditingController avatarController;
  final TextEditingController bioController;
  final bool submitting;
  final bool avatarUploading;
  final VoidCallback onUploadAvatar;
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('profile-avatar-upload'),
              onPressed: submitting || avatarUploading ? null : onUploadAvatar,
              icon: avatarUploading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_outlined),
              label: Text(avatarUploading ? '上传中...' : '上传头像'),
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
