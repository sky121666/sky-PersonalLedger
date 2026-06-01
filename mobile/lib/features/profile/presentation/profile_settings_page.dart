import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

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
    _showMessage('主题模板已切换为${palette.label}');
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
          const SizedBox(height: 12),
          _ProfileIdentityRail(profile: profile),
          const SizedBox(height: 12),
          _ProfileCompletenessStrip(profile: profile),
        ],
      ),
    );
  }
}

class _ProfileIdentityRail extends StatelessWidget {
  const _ProfileIdentityRail({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Container(
      key: const ValueKey('profile-identity-rail'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '身份状态轨道',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                profile.email.trim().isEmpty ? '资料待完善' : '身份可识别',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: profile.email.trim().isEmpty
                      ? financeColors.warning
                      : financeColors.income,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileIdentityNode(
                  icon: Icons.person_pin_circle_outlined,
                  label: '身份',
                  value: profile.displayName,
                  color: colorScheme.primary,
                ),
              ),
              _ProfileIdentityArrow(color: colorScheme.outline),
              Expanded(
                child: _ProfileIdentityNode(
                  icon: Icons.alternate_email_outlined,
                  label: '联系',
                  value: profile.email.trim().isEmpty ? '未绑定' : '已绑定',
                  color: financeColors.asset,
                ),
              ),
              _ProfileIdentityArrow(color: colorScheme.outline),
              Expanded(
                child: _ProfileIdentityNode(
                  icon: Icons.history_toggle_off_outlined,
                  label: '登录',
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

class _ProfileIdentityNode extends StatelessWidget {
  const _ProfileIdentityNode({
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
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.18
                    : 0.10,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _ProfileIdentityArrow extends StatelessWidget {
  const _ProfileIdentityArrow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Icon(Icons.chevron_right_rounded, color: color, size: 22),
    );
  }
}

class _ProfileCompletenessStrip extends StatelessWidget {
  const _ProfileCompletenessStrip({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final checks = [
      _ProfileCompletionCheck(
        label: '昵称',
        complete: profile.nickname.trim().isNotEmpty,
      ),
      _ProfileCompletionCheck(
        label: '邮箱',
        complete: profile.email.trim().isNotEmpty,
      ),
      _ProfileCompletionCheck(
        label: '头像',
        complete: profile.avatar.trim().isNotEmpty,
      ),
      _ProfileCompletionCheck(
        label: '简介',
        complete: profile.bio.trim().isNotEmpty,
      ),
    ];
    final completed = checks.where((check) => check.complete).length;
    final progress = completed / checks.length;
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final accent = progress >= 0.75
        ? financeColors.income
        : financeColors.warning;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_outlined, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '资料完整度',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$completed/${checks.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              color: accent,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final check in checks)
                _ProfileCompletionChip(check: check, activeColor: accent),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileCompletionCheck {
  const _ProfileCompletionCheck({required this.label, required this.complete});

  final String label;
  final bool complete;
}

class _ProfileCompletionChip extends StatelessWidget {
  const _ProfileCompletionChip({
    required this.check,
    required this.activeColor,
  });

  final _ProfileCompletionCheck check;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = check.complete ? activeColor : colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: check.complete ? 0.10 : 0.06),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            check.complete ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            check.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
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
                icon: Icons.auto_awesome_outlined,
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
                      '设置主题中心',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '多套主题色模板可在设置内直接切换，并同步财务语义色。',
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
          _ProfileThemePreview(palette: palette),
          const SizedBox(height: 12),
          _ProfileThemeStudioRail(settings: settings),
          const SizedBox(height: 14),
          _ProfileThemeTemplateMatrix(
            selectedPalette: palette,
            onPaletteChanged: onPaletteChanged,
          ),
          const SizedBox(height: 14),
          _ProfileThemeCurationRail(
            selectedPalette: settings.palette,
            onPaletteChanged: onPaletteChanged,
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
          _ProfileThemeSemanticPreview(palette: palette),
          const SizedBox(height: 14),
          _ProfileThemeDnaPanel(palette: palette),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn = constraints.maxWidth >= 520;
              final gap = twoColumn ? 10.0 : 8.0;
              final cardWidth = twoColumn
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final option in AppThemePalette.values)
                    SizedBox(
                      width: cardWidth,
                      child: _ProfileThemeOption(
                        palette: option,
                        selected: option == settings.palette,
                        onTap: () => onPaletteChanged(option),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileThemePreview extends StatelessWidget {
  const _ProfileThemePreview({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.seedColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.10,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.seedColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileThemeMetric(
              label: '当前模板',
              value: palette.label,
              color: palette.seedColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProfileThemeMetric(
              label: '体验定位',
              value: palette.signature,
              color: palette.assetColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ProfileThemeMetric(
              label: '模板数量',
              value: '${AppThemePalette.values.length} 套',
              color: palette.incomeColor,
            ),
          ),
        ],
      ),
    );
  }
}

const _profileFeaturedPalettes = [
  AppThemePalette.obsidian,
  AppThemePalette.aurora,
  AppThemePalette.plasma,
];

class _ProfileThemeCurationRail extends StatelessWidget {
  const _ProfileThemeCurationRail({
    required this.selectedPalette,
    required this.onPaletteChanged,
  });

  final AppThemePalette selectedPalette;
  final ValueChanged<AppThemePalette?> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      key: const ValueKey('profile-settings-theme-curation-rail'),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_mosaic_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '推荐主题策展',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _ProfileThemeCurationPill(
                label: '3 个高频场景',
                color: colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final palette in _profileFeaturedPalettes) ...[
                  _ProfileFeaturedThemeCard(
                    palette: palette,
                    selected: selectedPalette == palette,
                    onTap: () => onPaletteChanged(palette),
                  ),
                  if (palette != _profileFeaturedPalettes.last)
                    const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileFeaturedThemeCard extends StatelessWidget {
  const _ProfileFeaturedThemeCard({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppThemePalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 210,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: selected ? 1 : 0.985,
            child: AnimatedContainer(
              key: ValueKey('profile-settings-featured-theme-${palette.id}'),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 116),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      palette.seedColor.withValues(
                        alpha: selected ? 0.22 : 0.11,
                      ),
                      colorScheme.surface,
                    ),
                    Color.alphaBlend(
                      palette.assetColor.withValues(
                        alpha: selected ? 0.18 : 0.08,
                      ),
                      colorScheme.surface,
                    ),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? palette.seedColor
                      : colorScheme.outlineVariant,
                  width: selected ? 1.6 : 1,
                ),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      color: palette.seedColor.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ProfileFeaturedThemeSwatches(palette: palette),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          key: ValueKey(
                            selected
                                ? 'profile-settings-featured-selected-${palette.id}'
                                : 'profile-settings-featured-unselected-${palette.id}',
                          ),
                          color: selected
                              ? palette.seedColor
                              : colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    palette.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    palette.sceneLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ProfileThemeCurationPill(
                        label: palette.platformCue,
                        color: palette.seedColor,
                      ),
                      const SizedBox(width: 6),
                      _ProfileThemeCurationPill(
                        label: palette.signature,
                        color: palette.assetColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileFeaturedThemeSwatches extends StatelessWidget {
  const _ProfileFeaturedThemeSwatches({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 26,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _ProfileThemeDot(color: palette.seedColor),
          ),
          Positioned(
            left: 16,
            child: _ProfileThemeDot(color: palette.assetColor),
          ),
          Positioned(
            left: 32,
            child: _ProfileThemeDot(color: palette.incomeColor),
          ),
          Positioned(
            left: 48,
            child: _ProfileThemeDot(color: palette.expenseColor),
          ),
        ],
      ),
    );
  }
}

class _ProfileThemeDot extends StatelessWidget {
  const _ProfileThemeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
    );
  }
}

class _ProfileThemeCurationPill extends StatelessWidget {
  const _ProfileThemeCurationPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProfileThemeStudioRail extends StatelessWidget {
  const _ProfileThemeStudioRail({required this.settings});

  final AppThemeSettings settings;

  @override
  Widget build(BuildContext context) {
    final palette = settings.palette;
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      key: const ValueKey('profile-settings-theme-studio'),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileThemeStudioTile(
              icon: Icons.sync_outlined,
              label: '模式同步',
              value: _profileSettingsThemeModeLabel(settings.mode),
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ProfileThemeStudioTile(
              icon: Icons.auto_graph_outlined,
              label: '语义色板',
              value: '4 色',
              color: palette.assetColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ProfileThemeStudioTile(
              icon: Icons.devices_outlined,
              label: '跨端预览',
              value: '双端',
              color: palette.incomeColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileThemeStudioTile extends StatelessWidget {
  const _ProfileThemeStudioTile({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ProfileThemeTemplateMatrix extends StatelessWidget {
  const _ProfileThemeTemplateMatrix({
    required this.selectedPalette,
    required this.onPaletteChanged,
  });

  final AppThemePalette selectedPalette;
  final ValueChanged<AppThemePalette?> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = [
      _ThemeTemplateSignal(
        icon: Icons.account_balance_wallet_outlined,
        label: '日常记账',
        targetPalette: AppThemePalette.teal,
        color: selectedPalette.incomeColor,
      ),
      _ThemeTemplateSignal(
        icon: Icons.family_restroom_outlined,
        label: '家庭账本',
        targetPalette: AppThemePalette.emerald,
        color: selectedPalette.assetColor,
      ),
      _ThemeTemplateSignal(
        icon: Icons.auto_awesome_outlined,
        label: 'AI 分析',
        targetPalette: AppThemePalette.indigo,
        color: selectedPalette.seedColor,
      ),
      _ThemeTemplateSignal(
        icon: Icons.dark_mode_outlined,
        label: '夜间高频',
        targetPalette: AppThemePalette.obsidian,
        color: selectedPalette.warningColor,
      ),
    ];
    return AnimatedContainer(
      key: const ValueKey('profile-settings-theme-template-matrix'),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          selectedPalette.seedColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.06,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selectedPalette.seedColor.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded, color: selectedPalette.seedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '模板适配矩阵',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _ProfileSemanticPill(
                label: '点按切换',
                color: selectedPalette.assetColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn = constraints.maxWidth >= 430;
              final gap = twoColumn ? 10.0 : 8.0;
              final width = twoColumn
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: width,
                      child: _ProfileThemeTemplateTile(
                        item: item,
                        selected: selectedPalette == item.targetPalette,
                        onTap: () => onPaletteChanged(item.targetPalette),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeTemplateSignal {
  const _ThemeTemplateSignal({
    required this.icon,
    required this.label,
    required this.targetPalette,
    required this.color,
  });

  final IconData icon;
  final String label;
  final AppThemePalette targetPalette;
  final Color color;
}

class _ProfileThemeTemplateTile extends StatelessWidget {
  const _ProfileThemeTemplateTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _ThemeTemplateSignal item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.label}主题模板：${item.targetPalette.label}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('profile-settings-template-${item.targetPalette.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            scale: selected ? 1 : 0.985,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  item.color.withValues(
                    alpha: selected
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? 0.24
                              : 0.13)
                        : (Theme.of(context).brightness == Brightness.dark
                              ? 0.16
                              : 0.08),
                  ),
                  colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? item.targetPalette.seedColor
                      : item.color.withValues(alpha: 0.16),
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      color: item.targetPalette.seedColor.withValues(
                        alpha: 0.16,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                ],
              ),
              child: Row(
                children: [
                  IconBadge(
                    icon: item.icon,
                    color: item.color,
                    size: 38,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.targetPalette.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      key: ValueKey(
                        selected
                            ? 'profile-settings-template-selected-${item.targetPalette.id}'
                            : 'profile-settings-template-unselected-${item.targetPalette.id}',
                      ),
                      size: 20,
                      color: selected
                          ? item.targetPalette.seedColor
                          : colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileThemeSemanticPreview extends StatelessWidget {
  const _ProfileThemeSemanticPreview({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppFinanceColors.fromPalette(palette);
    return AnimatedContainer(
      key: const ValueKey('profile-settings-theme-semantic-preview'),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.assetColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.assetColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.query_stats_outlined, color: palette.assetColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '财务语义预览',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _ProfileSemanticPill(
                label: palette.signature,
                color: palette.seedColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ProfileSemanticScenario(
                  icon: Icons.auto_awesome_outlined,
                  title: '周报高光',
                  value: '+18%',
                  caption: '收入趋势',
                  color: financeColors.income,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileSemanticScenario(
                  icon: Icons.savings_outlined,
                  title: '预算状态',
                  value: '72%',
                  caption: '本月使用',
                  color: financeColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProfileSemanticPill(label: '收入色', color: financeColors.income),
              _ProfileSemanticPill(label: '资产色', color: financeColors.asset),
              _ProfileSemanticPill(label: '支出色', color: financeColors.expense),
              _ProfileSemanticPill(label: '警示色', color: financeColors.warning),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileSemanticScenario extends StatelessWidget {
  const _ProfileSemanticScenario({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
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

class _ProfileSemanticPill extends StatelessWidget {
  const _ProfileSemanticPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 30, maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileThemeDnaPanel extends StatelessWidget {
  const _ProfileThemeDnaPanel({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dnaItems = [
      _ThemeDnaSignal(
        icon: Icons.animation_outlined,
        label: '动效取向',
        value: _themeDnaMotionCue(palette),
        color: palette.seedColor,
      ),
      _ThemeDnaSignal(
        icon: Icons.devices_outlined,
        label: '跨端适配',
        value: _themeDnaPlatformCue(palette),
        color: palette.assetColor,
      ),
      _ThemeDnaSignal(
        icon: Icons.contrast_outlined,
        label: '视觉强度',
        value: _themeDnaIntensityCue(palette),
        color: palette.warningColor,
      ),
    ];
    return AnimatedContainer(
      key: const ValueKey('profile-settings-theme-dna-panel'),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.seedColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.seedColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.blur_on_outlined, color: palette.seedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '主题 DNA',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _ProfileSemanticPill(
                label: palette.platformCue,
                color: palette.assetColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ProfileThemeSpectrum(palette: palette),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final threeColumn = constraints.maxWidth >= 560;
              final twoColumn = constraints.maxWidth >= 390;
              final gap = threeColumn ? 10.0 : 8.0;
              final width = threeColumn
                  ? (constraints.maxWidth - gap * 2) / 3
                  : twoColumn
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in dnaItems)
                    SizedBox(
                      width: width,
                      child: _ProfileThemeDnaTile(item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileThemeSpectrum extends StatelessWidget {
  const _ProfileThemeSpectrum({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = [
      palette.seedColor,
      palette.assetColor,
      palette.incomeColor,
      palette.expenseColor,
      palette.warningColor,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '色彩光谱',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              '${colors.length} 组语义色',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final color in colors)
                  Expanded(child: ColoredBox(color: color)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeDnaSignal {
  const _ThemeDnaSignal({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _ProfileThemeDnaTile extends StatelessWidget {
  const _ProfileThemeDnaTile({required this.item});

  final _ThemeDnaSignal item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          item.color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: item.color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: item.color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
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

String _themeDnaMotionCue(AppThemePalette palette) {
  return switch (palette) {
    AppThemePalette.plasma ||
    AppThemePalette.kinetic ||
    AppThemePalette.aurora => '高动效',
    AppThemePalette.obsidian ||
    AppThemePalette.luxe ||
    AppThemePalette.violet => '沉浸过渡',
    AppThemePalette.titanium ||
    AppThemePalette.slate ||
    AppThemePalette.graphite => '克制平滑',
    _ => '轻量动效',
  };
}

String _themeDnaPlatformCue(AppThemePalette palette) {
  return switch (palette) {
    AppThemePalette.violet ||
    AppThemePalette.titanium ||
    AppThemePalette.obsidian => 'iOS / Android',
    AppThemePalette.graphite ||
    AppThemePalette.slate ||
    AppThemePalette.luxe => 'Web / 大屏',
    AppThemePalette.kinetic ||
    AppThemePalette.aurora ||
    AppThemePalette.plasma => '跨端高频',
    _ => '移动优先',
  };
}

String _themeDnaIntensityCue(AppThemePalette palette) {
  return switch (palette) {
    AppThemePalette.obsidian ||
    AppThemePalette.luxe ||
    AppThemePalette.plasma ||
    AppThemePalette.rose => '高对比',
    AppThemePalette.titanium ||
    AppThemePalette.slate ||
    AppThemePalette.graphite => '低饱和',
    _ => '中等强度',
  };
}

class _ProfileThemeMetric extends StatelessWidget {
  const _ProfileThemeMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ProfileThemeOption extends StatelessWidget {
  const _ProfileThemeOption({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppThemePalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = Color.alphaBlend(
      palette.seedColor.withValues(
        alpha: selected
            ? (Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12)
            : (Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.05),
      ),
      colorScheme.surface,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '主题模板：${palette.label}，${palette.signature}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('profile-settings-theme-${palette.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? palette.seedColor
                    : colorScheme.outlineVariant.withValues(alpha: 0.70),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                _ProfileThemeSwatches(palette: palette),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        palette.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        palette.signature,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _ProfileSemanticPill(
                            label: palette.sceneLabel,
                            color: palette.assetColor,
                          ),
                          _ProfileSemanticPill(
                            label: palette.platformCue,
                            color: palette.seedColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? palette.seedColor : colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
          const SizedBox(height: 12),
          _ProfileDraftEvidenceRail(
            nicknameController: nicknameController,
            emailController: emailController,
            avatarController: avatarController,
            bioController: bioController,
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

class _ProfileDraftEvidenceRail extends StatelessWidget {
  const _ProfileDraftEvidenceRail({
    required this.nicknameController,
    required this.emailController,
    required this.avatarController,
    required this.bioController,
  });

  final TextEditingController nicknameController;
  final TextEditingController emailController;
  final TextEditingController avatarController;
  final TextEditingController bioController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        nicknameController,
        emailController,
        avatarController,
        bioController,
      ]),
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final financeColors = AppTheme.financeColors(context);
        final nicknameReady = nicknameController.text.trim().isNotEmpty;
        final email = emailController.text.trim();
        final emailReady = email.isNotEmpty && email.contains('@');
        final avatarReady = avatarController.text.trim().isNotEmpty;
        final bioReady = bioController.text.trim().isNotEmpty;
        final completed = [
          nicknameReady,
          emailReady,
          avatarReady,
          bioReady,
        ].where((ready) => ready).length;
        return Wrap(
          key: const ValueKey('profile-draft-evidence-rail'),
          spacing: 8,
          runSpacing: 8,
          children: [
            _ProfileDraftEvidencePill(
              icon: Icons.fact_check_outlined,
              label: '草稿覆盖 $completed/4',
              color: completed >= 3
                  ? financeColors.income
                  : financeColors.warning,
            ),
            _ProfileDraftEvidencePill(
              icon: Icons.badge_outlined,
              label: nicknameReady ? '昵称就绪' : '昵称待补',
              color: nicknameReady ? colorScheme.primary : colorScheme.outline,
            ),
            _ProfileDraftEvidencePill(
              icon: Icons.alternate_email_outlined,
              label: emailReady ? '邮箱有效' : '邮箱待校验',
              color: emailReady ? financeColors.asset : financeColors.warning,
            ),
            _ProfileDraftEvidencePill(
              icon: Icons.image_outlined,
              label: avatarReady ? '头像已填' : '头像可选',
              color: avatarReady ? colorScheme.tertiary : colorScheme.outline,
            ),
            _ProfileDraftEvidencePill(
              icon: Icons.notes_outlined,
              label: bioReady ? '简介已填' : '简介待补',
              color: bioReady ? financeColors.income : colorScheme.outline,
            ),
          ],
        );
      },
    );
  }
}

class _ProfileDraftEvidencePill extends StatelessWidget {
  const _ProfileDraftEvidencePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.17
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
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
