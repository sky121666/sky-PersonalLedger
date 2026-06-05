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

  /// 构建我的页和主题设置。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final rows = [
      _ProfileRow(_ProfileHero(onLogout: () => _confirmLogout(context, ref))),
      _ProfileRow(
        _SettingsSection(
          title: '个人',
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
              icon: Icons.security_outlined,
              color: financeColors.expense,
              title: '账号安全',
              onTap: () => context.push(AppRoutePaths.securitySettings),
            ),
            _SettingsEntry(
              icon: Icons.vpn_key_outlined,
              color: financeColors.income,
              title: '设备授权',
              onTap: () => context.push(AppRoutePaths.apiTokens),
            ),
          ],
        ),
      ),
      _ProfileRow(
        _SettingsSection(
          title: '账本',
          initiallyExpanded: false,
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
              title: '账户流水',
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
          title: '日常',
          initiallyExpanded: false,
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
              title: '负债',
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
            _SettingsEntry(
              icon: Icons.auto_awesome_outlined,
              color: colorScheme.primary,
              title: '财务报告',
              onTap: () => context.push(AppRoutePaths.aiReports),
            ),
            _SettingsEntry(
              icon: Icons.summarize_outlined,
              color: financeColors.asset,
              title: '年度报告',
              onTap: () => context.push(AppRoutePaths.yearlyReport),
            ),
          ],
        ),
      ),
      _ProfileRow(
        _SettingsSection(
          title: '设置',
          initiallyExpanded: false,
          childrenBuilder: () => [
            _SettingsEntry(
              icon: Icons.storage_outlined,
              color: financeColors.asset,
              title: '数据',
              onTap: () => context.push(AppRoutePaths.dataManagement),
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
      appBar: AppBar(title: const Text('我的')),
      body: AdaptivePageContainer(
        child: ListView.builder(
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

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      key: const ValueKey('profile-command-center'),
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '个人记账',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconBadge(
                      icon: Icons.account_balance_wallet_outlined,
                      color: financeColors.asset,
                      size: 24,
                      iconSize: 14,
                    ),
                    const SizedBox(width: 6),
                    IconBadge(
                      icon: Icons.palette_outlined,
                      color: colorScheme.tertiary,
                      size: 24,
                      iconSize: 14,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('profile-logout'),
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            tooltip: null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.childrenBuilder,
    this.initiallyExpanded = true,
  });

  final String title;
  final List<Widget> Function() childrenBuilder;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return _LazySettingsSection(
      title: title,
      childrenBuilder: childrenBuilder,
      initiallyExpanded: initiallyExpanded,
    );
  }
}

class _LazySettingsSection extends StatefulWidget {
  const _LazySettingsSection({
    required this.title,
    required this.childrenBuilder,
    required this.initiallyExpanded,
  });

  final String title;
  final List<Widget> Function() childrenBuilder;
  final bool initiallyExpanded;

  @override
  State<_LazySettingsSection> createState() => _LazySettingsSectionState();
}

class _LazySettingsSectionState extends State<_LazySettingsSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final children = _expanded ? widget.childrenBuilder() : const <Widget>[];
    return PremiumSurface(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('profile-section-${widget.title}'),
          initiallyExpanded: widget.initiallyExpanded,
          maintainState: false,
          onExpansionChanged: (expanded) {
            if (_expanded == expanded) {
              return;
            }
            setState(() => _expanded = expanded);
          },
          tilePadding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
          childrenPadding: const EdgeInsets.only(bottom: 4),
          title: Text(
            widget.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          children: [
            for (final entry in children.indexed) ...[
              if (entry.$1 > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 58,
                  endIndent: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.62),
                ),
              entry.$2,
            ],
          ],
        ),
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
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  IconBadge(icon: icon, color: color, size: 30, iconSize: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    size: 22,
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
          Row(
            children: [
              IconBadge(
                icon: Icons.contrast_outlined,
                color: colorScheme.tertiary,
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
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
          const SizedBox(height: 10),
          Text(
            '模式',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 10),
          DropdownButtonFormField<AppThemePalette>(
            initialValue: settings.palette,
            decoration: InputDecoration(
              labelText: '主题色',
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
