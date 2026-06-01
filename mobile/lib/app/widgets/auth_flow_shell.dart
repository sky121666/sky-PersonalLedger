import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'finance_dashboard_widgets.dart';
import 'premium_surface.dart';
import 'staggered_entrance.dart';

class AuthFlowShell extends StatelessWidget {
  const AuthFlowShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.accentColor,
    required this.children,
    this.serverUrl,
    this.footer,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final Color accentColor;
  final String? serverUrl;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StaggeredEntrance(
                          index: 0,
                          child: _AuthHeroPanel(
                            icon: icon,
                            title: title,
                            subtitle: subtitle,
                            primaryLabel: primaryLabel,
                            serverUrl: serverUrl,
                            accentColor: accentColor,
                          ),
                        ),
                        const SizedBox(height: 14),
                        StaggeredEntrance(
                          index: 1,
                          child: _AuthExperienceDeck(
                            accentColor: accentColor,
                            serverUrl: serverUrl,
                          ),
                        ),
                        const SizedBox(height: 14),
                        StaggeredEntrance(
                          index: 2,
                          child: PremiumSurface(
                            accentColor: accentColor,
                            semanticLabel: '$primaryLabel 表单',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: children,
                            ),
                          ),
                        ),
                        if (footer != null) ...[
                          const SizedBox(height: 10),
                          StaggeredEntrance(index: 3, child: footer!),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          'Personal Ledger',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthHeroPanel extends StatelessWidget {
  const _AuthHeroPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.accentColor,
    this.serverUrl,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final Color accentColor;
  final String? serverUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PremiumSurface(
      semanticLabel: '$title，$primaryLabel',
      accentColor: accentColor,
      padding: EdgeInsets.zero,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.surfaceRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                accentColor.withValues(alpha: isDark ? 0.24 : 0.14),
                colorScheme.surface,
              ),
              Color.alphaBlend(
                financeColors.asset.withValues(alpha: isDark ? 0.15 : 0.08),
                colorScheme.surface,
              ),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: icon,
                  color: accentColor,
                  size: 56,
                  iconSize: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AuthStatusPill(label: primaryLabel, color: accentColor),
                      const SizedBox(height: 7),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (serverUrl != null && serverUrl!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    financeColors.asset.withValues(alpha: isDark ? 0.18 : 0.10),
                    colorScheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: financeColors.asset.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.dns_outlined,
                      color: financeColors.asset,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        serverUrl!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.verified_outlined,
                      color: financeColors.income,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthExperienceDeck extends StatelessWidget {
  const _AuthExperienceDeck({required this.accentColor, this.serverUrl});

  final Color accentColor;
  final String? serverUrl;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final cards = [
      _AuthExperienceData(
        icon: Icons.phone_iphone_outlined,
        label: 'iOS 动效',
        value: '弹性入场',
        color: accentColor,
      ),
      _AuthExperienceData(
        icon: Icons.android_outlined,
        label: 'Android 状态层',
        value: '触控反馈',
        color: financeColors.income,
      ),
      _AuthExperienceData(
        icon: Icons.palette_outlined,
        label: '主题色联动',
        value: '全局同步',
        color: financeColors.asset,
      ),
    ];
    return PremiumSurface(
      key: const ValueKey('auth-experience-deck'),
      semanticLabel: '跨端安全控制台，$_serverLabel，iOS 动效，Android 状态层，主题色联动',
      accentColor: accentColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.security_outlined,
                color: accentColor,
                size: 40,
                iconSize: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '跨端安全控制台',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _AuthStatusPill(
                label: _serverLabel,
                color: serverUrl == null || serverUrl!.trim().isEmpty
                    ? Theme.of(context).colorScheme.outline
                    : financeColors.income,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final entry in cards.indexed) ...[
                Expanded(child: _AuthExperienceTile(data: entry.$2)),
                if (entry.$1 != cards.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String get _serverLabel {
    final value = serverUrl?.trim();
    if (value == null || value.isEmpty) {
      return '待连接';
    }
    return '私有服务';
  }
}

class _AuthExperienceData {
  const _AuthExperienceData({
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

class _AuthExperienceTile extends StatelessWidget {
  const _AuthExperienceTile({required this.data});

  final _AuthExperienceData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          data.color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(data.icon, color: data.color, size: 19),
          const SizedBox(height: 8),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
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

class _AuthStatusPill extends StatelessWidget {
  const _AuthStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
