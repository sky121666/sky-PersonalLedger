import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// 构建我的页和主题设置入口。
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
                title: '能力中心',
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
                    subtitle: '查看还款提醒和上岸进度',
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
                    subtitle: '配置提醒通道和通知类型',
                    onTap: () => context.push(AppRoutePaths.notifications),
                  ),
                  _SettingsEntry(
                    icon: Icons.security_outlined,
                    color: financeColors.expense,
                    title: '账号安全',
                    subtitle: '修改密码和配置安全入口',
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
    ref.read(themeControllerProvider.notifier).setThemeMode(value);
  }

  /// 更新主题色模板。
  void _setThemePalette(WidgetRef ref, AppThemePalette? value) {
    if (value == null) {
      return;
    }
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
      accentColor: colorScheme.primary,
      child: Row(
        children: [
          IconBadge(
            icon: Icons.person_outline,
            color: colorScheme.primary,
            size: 54,
            iconSize: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '个人记账',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Flutter 原生移动端',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
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
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color, size: 38, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
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
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: settings.palette.seedColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.palette_outlined,
                color: settings.palette.seedColor,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '主题色模板',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '为移动端仪表盘切换不同高级色彩方案',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ThemeLivePreview(
            palette: settings.palette,
            financeColors: financeColors,
          ),
          const SizedBox(height: 12),
          _AppliedThemeStrip(palette: settings.palette),
          const SizedBox(height: 12),
          _ThemeCapabilityMatrix(settings: settings),
          const SizedBox(height: 18),
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
            '主题模板',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn = constraints.maxWidth >= 520;
              final gap = twoColumn ? 12.0 : 10.0;
              final cardWidth = twoColumn
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final palette in AppThemePalette.values)
                    SizedBox(
                      width: cardWidth,
                      child: _ThemePaletteOption(
                        palette: palette,
                        selected: settings.palette == palette,
                        onTap: () => onPaletteChanged(palette),
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

class _AppliedThemeStrip extends StatelessWidget {
  const _AppliedThemeStrip({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
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
          Icon(Icons.done_all_outlined, color: palette.seedColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '当前已应用：${palette.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _PaletteSignaturePill(palette: palette),
        ],
      ),
    );
  }
}

class _ThemeCapabilityMatrix extends StatelessWidget {
  const _ThemeCapabilityMatrix({required this.settings});

  final AppThemeSettings settings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        Expanded(
          child: _ThemeCapabilityTile(
            icon: Icons.grid_view_outlined,
            label: '模板矩阵',
            value: '${AppThemePalette.values.length} 套',
            color: settings.palette.seedColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ThemeCapabilityTile(
            icon: Icons.contrast_outlined,
            label: '模式控制',
            value: _themeModeLabel(settings.mode),
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ThemeCapabilityTile(
            icon: Icons.auto_graph_outlined,
            label: '财务语义',
            value: '4 色',
            color: financeColors.asset,
          ),
        ),
      ],
    );
  }

  String _themeModeLabel(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => '系统',
      AppThemeMode.light => '浅色',
      AppThemeMode.dark => '深色',
    };
  }
}

class _ThemeCapabilityTile extends StatelessWidget {
  const _ThemeCapabilityTile({
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
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
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

class _ThemeLivePreview extends StatelessWidget {
  const _ThemeLivePreview({required this.palette, required this.financeColors});

  final AppThemePalette palette;
  final AppFinanceColors financeColors;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              palette.seedColor.withValues(alpha: 0.22),
              colorScheme.surface,
            ),
            Color.alphaBlend(
              palette.assetColor.withValues(alpha: 0.16),
              colorScheme.surface,
            ),
            Color.alphaBlend(
              palette.warningColor.withValues(alpha: 0.10),
              colorScheme.surface,
            ),
          ],
        ),
        border: Border.all(color: palette.seedColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.space_dashboard_outlined,
                color: palette.seedColor,
                size: 38,
                iconSize: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${palette.label} 预览',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '+12.8%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: financeColors.income,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '¥12,840.00',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PreviewMetric(
                  label: '资产',
                  value: '8.4w',
                  color: financeColors.asset,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PreviewMetric(
                  label: '提醒',
                  value: '3 项',
                  color: financeColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PreviewMetric(
                  label: '支出',
                  value: '2.1w',
                  color: financeColors.expense,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({
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
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(10),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePaletteOption extends StatelessWidget {
  const _ThemePaletteOption({
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
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: selected ? 1 : 0.985,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 154),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    palette.seedColor.withValues(alpha: selected ? 0.18 : 0.08),
                    colorScheme.surface,
                  ),
                  Color.alphaBlend(
                    palette.assetColor.withValues(
                      alpha: selected ? 0.14 : 0.06,
                    ),
                    colorScheme.surface,
                  ),
                ],
              ),
              border: Border.all(
                color: selected
                    ? palette.seedColor
                    : colorScheme.outlineVariant.withValues(alpha: 0.72),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: palette.seedColor.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ThemePalettePreview(palette: palette),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: selected
                          ? Icon(
                              Icons.check_circle,
                              key: const ValueKey('selected'),
                              color: palette.seedColor,
                            )
                          : Icon(
                              Icons.radio_button_unchecked,
                              key: const ValueKey('unselected'),
                              color: colorScheme.outline,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        palette.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PaletteSignaturePill(palette: palette),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  palette.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _PaletteSignalBar(
                        color: palette.incomeColor,
                        height: 22,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _PaletteSignalBar(
                        color: palette.assetColor,
                        height: 30,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _PaletteSignalBar(
                        color: palette.expenseColor,
                        height: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _PaletteSignalBar(
                        color: palette.warningColor,
                        height: 26,
                      ),
                    ),
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: selected
                      ? Padding(
                          key: const ValueKey('selected-palette-roles'),
                          padding: const EdgeInsets.only(top: 12),
                          child: _PaletteRoleLegend(palette: palette),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('unselected-palette-roles'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteRoleLegend extends StatelessWidget {
  const _PaletteRoleLegend({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _PaletteRoleChip(label: '收入色', color: palette.incomeColor),
        _PaletteRoleChip(label: '资产色', color: palette.assetColor),
        _PaletteRoleChip(label: '支出色', color: palette.expenseColor),
        _PaletteRoleChip(label: '警示色', color: palette.warningColor),
      ],
    );
  }
}

class _PaletteRoleChip extends StatelessWidget {
  const _PaletteRoleChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.20
                : 0.10,
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
          const SizedBox(width: 5),
          Text(
            label,
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

class _PaletteSignaturePill extends StatelessWidget {
  const _PaletteSignaturePill({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.seedColor.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.seedColor.withValues(alpha: 0.16)),
      ),
      child: Text(
        palette.signature,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.seedColor,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PaletteSignalBar extends StatelessWidget {
  const _PaletteSignalBar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePalettePreview extends StatelessWidget {
  const _ThemePalettePreview({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 42,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(left: 0, child: _PaletteDot(color: palette.seedColor)),
          Positioned(left: 18, child: _PaletteDot(color: palette.assetColor)),
          Positioned(left: 36, child: _PaletteDot(color: palette.incomeColor)),
          Positioned(left: 54, child: _PaletteDot(color: palette.warningColor)),
        ],
      ),
    );
  }
}

class _PaletteDot extends StatelessWidget {
  const _PaletteDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );
  }
}
