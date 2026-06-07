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
import '../../auth/application/auth_controller.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  /// 构建功能入口和主题设置。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final rows = [
      _ProfileRow(
        _SettingsSection(
          title: '账本管理',
          childrenBuilder: () => [
            _SettingsEntry(
              icon: Icons.account_balance_wallet_outlined,
              color: financeColors.asset,
              title: '账户',
              onTap: () => context.push(AppRoutePaths.accounts),
            ),
            _SettingsEntry(
              icon: Icons.receipt_long_outlined,
              color: financeColors.warning,
              title: '账户明细',
              onTap: () => context.push(AppRoutePaths.accountLogs),
            ),
            _SettingsEntry(
              icon: Icons.category_outlined,
              color: financeColors.expense,
              title: '分类',
              onTap: () => context.push(AppRoutePaths.categories),
            ),
            _SettingsEntry(
              icon: Icons.label_outline,
              color: financeColors.income,
              title: '标签',
              onTap: () => context.push(AppRoutePaths.tags),
            ),
            _SettingsEntry(
              icon: Icons.bolt_outlined,
              color: colorScheme.tertiary,
              title: '快捷模板',
              onTap: () => context.push(AppRoutePaths.templates),
            ),
          ],
        ),
      ),
      _ProfileRow(
        _SettingsSection(
          title: '计划提醒',
          childrenBuilder: () => [
            _SettingsEntry(
              icon: Icons.savings_outlined,
              color: financeColors.income,
              title: '预算',
              onTap: () => context.push(AppRoutePaths.budgets),
            ),
            _SettingsEntry(
              icon: Icons.notifications_active_outlined,
              color: financeColors.warning,
              title: '负债提醒',
              onTap: () => context.push(AppRoutePaths.reminders),
            ),
            _SettingsEntry(
              icon: Icons.handshake_outlined,
              color: financeColors.asset,
              title: '借贷往来',
              onTap: () => context.push(AppRoutePaths.lendings),
            ),
            _SettingsEntry(
              icon: Icons.diversity_3_outlined,
              color: colorScheme.tertiary,
              title: '家庭成员',
              onTap: () => context.push(AppRoutePaths.family),
            ),
          ],
        ),
      ),
      _ProfileRow(
        _SettingsSection(
          title: '智能与数据',
          childrenBuilder: () => [
            _SettingsEntry(
              icon: Icons.auto_awesome_outlined,
              color: colorScheme.primary,
              title: 'AI 分析',
              onTap: () => context.push(AppRoutePaths.aiReports),
            ),
            _SettingsEntry(
              icon: Icons.summarize_outlined,
              color: financeColors.asset,
              title: '年度报告',
              onTap: () => context.push(AppRoutePaths.yearlyReport),
            ),
            _SettingsEntry(
              icon: Icons.storage_outlined,
              color: financeColors.asset,
              title: '数据备份',
              onTap: () => context.push(AppRoutePaths.dataManagement),
            ),
          ],
        ),
      ),
      _ProfileRow(
        _SettingsSection(
          title: '安全设置',
          childrenBuilder: () => [
            _SettingsEntry(
              icon: Icons.manage_accounts_outlined,
              color: colorScheme.primary,
              title: '个人资料',
              onTap: () => context.push(AppRoutePaths.profileSettings),
            ),
            _SettingsEntry(
              icon: Icons.notifications_none_outlined,
              color: colorScheme.secondary,
              title: '通知设置',
              onTap: () => context.push(AppRoutePaths.notifications),
            ),
            _SettingsEntry(
              icon: Icons.vpn_key_outlined,
              color: financeColors.income,
              title: '设备授权',
              onTap: () => context.push(AppRoutePaths.apiTokens),
            ),
            _SettingsEntry(
              icon: Icons.security_outlined,
              color: financeColors.expense,
              title: '账号安全',
              onTap: () => context.push(AppRoutePaths.securitySettings),
            ),
            _SettingsEntry(
              icon: Icons.swap_horiz,
              color: colorScheme.outline,
              title: '更换账本',
              onTap: () => _confirmChangeServer(context, ref),
            ),
          ],
        ),
      ),
      _ProfileRow(
        _AppearancePanel(
          settings: themeSettings,
          onModeChanged: (value) => _setThemeMode(ref, value),
          onPaletteChanged: (value) => _setThemePalette(ref, value),
        ),
        0,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('功能'),
        actions: [
          IconButton(
            key: const ValueKey('profile-logout'),
            onPressed: () => _confirmLogout(context, ref),
            icon: const Icon(Icons.logout),
            tooltip: null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      body: AdaptivePageContainer(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == rows.length - 1 ? 0 : row.bottomSpacing,
              ),
              child: row.child,
            );
          },
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

  /// 更新主题色。
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
      message: '下次需要重新登录。',
      confirmText: '退出',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(authControllerProvider.notifier).logout();
  }

  /// 展示更换账本确认弹窗。
  Future<void> _confirmChangeServer(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '更换账本',
      message: '需要重新登录。',
      confirmText: '更换',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(authControllerProvider.notifier).changeServer();
  }
}

class _ProfileRow {
  const _ProfileRow(this.child, [this.bottomSpacing = 12]);

  final Widget child;
  final double bottomSpacing;
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.childrenBuilder});

  final String title;
  final List<Widget> Function() childrenBuilder;

  @override
  Widget build(BuildContext context) {
    final children = childrenBuilder();
    return PremiumSurface(
      key: ValueKey('profile-section-$title'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 300 ? 1 : 2;
              final gap = 8.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final child in children)
                    SizedBox(width: itemWidth, child: child),
                ],
              );
            },
          ),
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
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: title,
      child: Material(
        key: ValueKey('profile-entry-$title'),
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: color.withValues(alpha: 0.06),
          focusColor: color.withValues(alpha: 0.08),
          splashColor: color.withValues(alpha: 0.08),
          highlightColor: color.withValues(alpha: 0.05),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  color.withValues(alpha: 0.035),
                  colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.58),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 7, 8),
                child: Row(
                  children: [
                    IconBadge(icon: icon, color: color, size: 30, iconSize: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.62,
                      ),
                      size: 18,
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '外观',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<AppThemeMode>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('系统'),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('深色'),
                ),
              ],
              selected: {settings.mode},
              onSelectionChanged: (selection) =>
                  onModeChanged(selection.firstOrNull),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AppThemePalette>(
            initialValue: settings.palette.selectableEquivalent,
            menuMaxHeight: 360,
            selectedItemBuilder: (context) => [
              for (final palette in AppThemePalette.selectableValues)
                Text(
                  palette.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
            ],
            decoration: InputDecoration(
              labelText: '主题',
              isDense: true,
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
              for (final palette in AppThemePalette.selectableValues)
                DropdownMenuItem(
                  value: palette,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 132),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ThemePaletteDot(
                          palette: palette,
                          selected:
                              palette == settings.palette.selectableEquivalent,
                        ),
                        const SizedBox(width: 12),
                        _ThemePaletteLabel(palette: palette),
                      ],
                    ),
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
  const _ThemePaletteDot({required this.palette, required this.selected});

  final AppThemePalette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = palette.displayAccentColor;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: selected ? 1 : 0.88),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colorScheme.onSurface : colorScheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          if (selected)
            BoxShadow(
              color: color.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: selected
          ? Icon(Icons.check_rounded, color: colorScheme.onPrimary, size: 15)
          : null,
    );
  }
}

class _ThemePaletteLabel extends StatelessWidget {
  const _ThemePaletteLabel({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Text(
        palette.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
