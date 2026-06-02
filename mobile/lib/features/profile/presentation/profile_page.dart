import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../auth/application/auth_controller.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  /// 构建我的页和主题设置。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: AdaptivePageContainer(
        child: ListView(
          children: [
            StaggeredEntrance(
              index: 0,
              child: _ProfileHero(onLogout: () => _confirmLogout(context, ref)),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 1,
              child: _SettingsSection(
                title: '资产配置',
                children: [
                  _SettingsEntry(
                    icon: Icons.manage_accounts_outlined,
                    color: colorScheme.primary,
                    title: '个人资料',
                    subtitle: '编辑昵称、邮箱和简介',
                    onTap: () => context.push(AppRoutePaths.profileSettings),
                  ),
                  _SettingsEntry(
                    icon: Icons.account_balance_wallet_outlined,
                    color: financeColors.asset,
                    title: '账户管理',
                    subtitle: '新增、编辑、归档和删除账户',
                    onTap: () => context.push(AppRoutePaths.accounts),
                  ),
                  _SettingsEntry(
                    icon: Icons.receipt_long_outlined,
                    color: financeColors.warning,
                    title: '账户流水',
                    subtitle: '查看全部账户余额变动记录',
                    onTap: () => context.push(AppRoutePaths.accountLogs),
                  ),
                  _SettingsEntry(
                    icon: Icons.category_outlined,
                    color: financeColors.expense,
                    title: '分类管理',
                    subtitle: '维护收入和支出分类',
                    onTap: () => context.push(AppRoutePaths.categories),
                  ),
                  _SettingsEntry(
                    icon: Icons.label_outline,
                    color: financeColors.income,
                    title: '标签管理',
                    subtitle: '维护交易标签和使用标记',
                    onTap: () => context.push(AppRoutePaths.tags),
                  ),
                  _SettingsEntry(
                    icon: Icons.bolt_outlined,
                    color: colorScheme.tertiary,
                    title: '快捷模板',
                    subtitle: '保存常用收支并一键记账',
                    onTap: () => context.push(AppRoutePaths.templates),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 2,
              child: _SettingsSection(
                title: '常用功能',
                children: [
                  _SettingsEntry(
                    icon: Icons.savings_outlined,
                    color: financeColors.income,
                    title: '预算管理',
                    subtitle: '设置总预算和分类预算提醒线',
                    onTap: () => context.push(AppRoutePaths.budgets),
                  ),
                  _SettingsEntry(
                    icon: Icons.notifications_active_outlined,
                    color: financeColors.warning,
                    title: '负债管理',
                    subtitle: '查看还款提醒和还款记录',
                    onTap: () => context.push(AppRoutePaths.reminders),
                  ),
                  _SettingsEntry(
                    icon: Icons.handshake_outlined,
                    color: financeColors.asset,
                    title: '借贷往来',
                    subtitle: '管理借出、借入和还款记录',
                    onTap: () => context.push(AppRoutePaths.lendings),
                  ),
                  _SettingsEntry(
                    icon: Icons.diversity_3_outlined,
                    color: colorScheme.tertiary,
                    title: '家庭成员',
                    subtitle: '管理家庭记账成员和支出归属',
                    onTap: () => context.push(AppRoutePaths.family),
                  ),
                  _SettingsEntry(
                    icon: Icons.auto_awesome_outlined,
                    color: colorScheme.primary,
                    title: 'AI 财务报告',
                    subtitle: '查看每周总结和智能分析',
                    onTap: () => context.push(AppRoutePaths.aiReports),
                  ),
                  _SettingsEntry(
                    icon: Icons.summarize_outlined,
                    color: financeColors.asset,
                    title: '年度报告',
                    subtitle: '查看年度收支、结余和分类排行',
                    onTap: () => context.push(AppRoutePaths.yearlyReport),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 3,
              child: _SettingsSection(
                title: '系统设置',
                children: [
                  _SettingsEntry(
                    icon: Icons.notifications_none_outlined,
                    color: colorScheme.secondary,
                    title: '通知设置',
                    onTap: () => context.push(AppRoutePaths.notifications),
                  ),
                  _SettingsEntry(
                    icon: Icons.security_outlined,
                    color: financeColors.expense,
                    title: '账号安全',
                    onTap: () => context.push(AppRoutePaths.securitySettings),
                  ),
                  _SettingsEntry(
                    icon: Icons.vpn_key_outlined,
                    color: financeColors.income,
                    title: 'API Token',
                    subtitle: '管理 App 和外部 API 访问令牌',
                    onTap: () => context.push(AppRoutePaths.apiTokens),
                  ),
                  _SettingsEntry(
                    icon: Icons.storage_outlined,
                    color: financeColors.asset,
                    title: '数据管理',
                    subtitle: '备份、恢复和导出交易数据',
                    onTap: () => context.push(AppRoutePaths.dataManagement),
                  ),
                  _SettingsEntry(
                    icon: Icons.dns_outlined,
                    color: colorScheme.outline,
                    title: '更换服务器',
                    subtitle: '清除本机登录态并重新连接服务地址',
                    onTap: () => _confirmChangeServer(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 4,
              child: _AppearancePanel(
                settings: themeSettings,
                onModeChanged: (value) => _setThemeMode(ref, value),
                onPaletteChanged: (value) => _setThemePalette(ref, value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 更新主题模式。
  void _setThemeMode(WidgetRef ref, AppThemeMode? value) {
    if (value == null) {
      return;
    }
    HapticFeedback.selectionClick();
    ref.read(themeControllerProvider.notifier).setThemeMode(value);
  }

  /// 更新主题色。
  void _setThemePalette(WidgetRef ref, AppThemePalette? value) {
    if (value == null) {
      return;
    }
    HapticFeedback.selectionClick();
    ref.read(themeControllerProvider.notifier).setPalette(value);
  }

  /// 展示退出确认弹窗。
  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '确认退出',
      message: '退出后需要重新输入密码登录。',
      confirmText: '退出',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(authControllerProvider.notifier).logout();
  }

  /// 展示更换服务器确认弹窗。
  Future<void> _confirmChangeServer(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '更换服务器',
      message: '这会清除当前服务器地址和本机登录态，之后需要重新连接。',
      confirmText: '更换',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(authControllerProvider.notifier).changeServer();
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      key: const ValueKey('profile-command-center'),
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.account_balance_wallet_outlined,
                color: colorScheme.primary,
                size: 48,
                iconSize: 25,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '个人记账',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '管理账户、分类、预算和数据安全',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                tooltip: '退出登录',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Semantics(
        button: true,
        label: subtitle == null ? title : '$title，$subtitle',
        child: Material(
          key: ValueKey('profile-entry-$title'),
          color: Color.alphaBlend(
            color.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.08
                  : 0.035,
            ),
            colorScheme.surface,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: color.withValues(alpha: 0.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            hoverColor: color.withValues(alpha: 0.08),
            focusColor: color.withValues(alpha: 0.10),
            splashColor: color.withValues(alpha: 0.10),
            highlightColor: color.withValues(alpha: 0.06),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconBadge(icon: icon, color: color, size: 34, iconSize: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: color.withValues(alpha: 0.72),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({
    required this.settings,
    required this.onModeChanged,
    required this.onPaletteChanged,
  });

  final AppThemeSettings settings;
  final ValueChanged<AppThemeMode?> onModeChanged;
  final ValueChanged<AppThemePalette?> onPaletteChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      key: const ValueKey('profile-appearance-panel'),
      accentColor: settings.palette.seedColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.contrast_outlined,
                color: settings.palette.seedColor,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '外观',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '外观模式',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 18),
          Text(
            '主题色',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
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
              for (final palette in AppThemePalette.values)
                DropdownMenuItem(
                  value: palette,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ThemePaletteDot(palette: palette),
                      const SizedBox(width: 10),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          palette.label,
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

class _ThemePaletteDot extends StatelessWidget {
  const _ThemePaletteDot({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        children: [
          for (var index = 0; index < 3; index += 1)
            Positioned(
              left: index * 7,
              child: Container(
                width: 14,
                height: 24,
                decoration: BoxDecoration(
                  color: [
                    palette.seedColor,
                    palette.assetColor,
                    palette.incomeColor,
                  ][index],
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
