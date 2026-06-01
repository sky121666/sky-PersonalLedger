import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.go(AppRoutePaths.serverConfig);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: StaggeredEntrance(
                index: 0,
                child: PremiumSurface(
                  accentColor: financeColors.asset,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconBadge(
                            icon: Icons.account_balance_wallet_outlined,
                            color: financeColors.asset,
                            size: 56,
                            iconSize: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Personal Ledger',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: financeColors.asset,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '正在准备账本环境',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '正在检查本机配置、连接入口和加密上下文，完成后进入服务器设置。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _BootstrapProgressRail(),
                      const SizedBox(height: 12),
                      const _BootstrapReadinessRail(),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        minHeight: 7,
                        color: financeColors.asset,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapReadinessRail extends StatelessWidget {
  const _BootstrapReadinessRail();

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Wrap(
      key: const ValueKey('bootstrap-readiness-rail'),
      spacing: 8,
      runSpacing: 8,
      children: [
        _BootstrapReadinessPill(
          icon: Icons.fact_check_outlined,
          label: '启动检查 3/3',
          color: financeColors.income,
        ),
        _BootstrapReadinessPill(
          icon: Icons.route_outlined,
          label: '下一步服务器',
          color: financeColors.asset,
        ),
        _BootstrapReadinessPill(
          icon: Icons.verified_user_outlined,
          label: '安全上下文预备',
          color: financeColors.warning,
        ),
      ],
    );
  }
}

class _BootstrapReadinessPill extends StatelessWidget {
  const _BootstrapReadinessPill({
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BootstrapProgressRail extends StatelessWidget {
  const _BootstrapProgressRail();

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        Expanded(
          child: _BootstrapSignal(
            icon: Icons.storage_outlined,
            label: '本机配置',
            value: '读取中',
            color: financeColors.asset,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BootstrapSignal(
            icon: Icons.hub_outlined,
            label: '连接入口',
            value: '待确认',
            color: financeColors.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BootstrapSignal(
            icon: Icons.lock_outline,
            label: '安全上下文',
            value: '准备中',
            color: financeColors.income,
          ),
        ),
      ],
    );
  }
}

class _BootstrapSignal extends StatelessWidget {
  const _BootstrapSignal({
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
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(10),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
