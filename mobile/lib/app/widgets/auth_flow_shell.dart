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
                          child: PremiumSurface(
                            accentColor: accentColor,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: children,
                            ),
                          ),
                        ),
                        if (footer != null) ...[
                          const SizedBox(height: 10),
                          StaggeredEntrance(index: 2, child: footer!),
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
    return PremiumSurface(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: accentColor, size: 54, iconSize: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  financeColors.asset.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.18
                        : 0.10,
                  ),
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
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
