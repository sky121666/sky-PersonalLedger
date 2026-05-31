import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../auth/application/auth_controller.dart';

class ServerConfigPage extends ConsumerStatefulWidget {
  const ServerConfigPage({super.key});

  @override
  ConsumerState<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends ConsumerState<ServerConfigPage> {
  final TextEditingController _serverUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final serverUrl = ref.read(authControllerProvider).serverUrl;
    if (serverUrl != null) {
      _serverUrlController.text = serverUrl;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _submitServerUrl() async {
    await ref
        .read(authControllerProvider.notifier)
        .connectServer(_serverUrlController.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.stage == AuthStage.checking;

    final accentColor = AppTheme.financeColors(context).brand;
    return AuthFlowShell(
      icon: Icons.account_balance_wallet_outlined,
      title: '连接服务器',
      subtitle: '请输入自托管个人记账服务地址，连接后会自动判断是否需要首次初始化。',
      primaryLabel: '自托管入口',
      accentColor: accentColor,
      children: [
        _ConnectionStatusStrip(isLoading: isLoading, accentColor: accentColor),
        const SizedBox(height: 14),
        TextField(
          controller: _serverUrlController,
          enabled: !isLoading,
          decoration: InputDecoration(
            labelText: '服务器地址',
            hintText: 'example.com:8080',
            border: const OutlineInputBorder(),
            errorText: authState.errorMessage,
            prefixIcon: const Icon(Icons.dns_outlined),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => isLoading ? null : _submitServerUrl(),
        ),
        const SizedBox(height: 14),
        const _ServerCapabilityGrid(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: isLoading ? null : _submitServerUrl,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.arrow_forward),
              const SizedBox(width: 8),
              const Text('连接'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '远程正式环境建议使用 HTTPS；本地或内网地址会按当前安全策略校验。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ConnectionStatusStrip extends StatelessWidget {
  const _ConnectionStatusStrip({
    required this.isLoading,
    required this.accentColor,
  });

  final bool isLoading;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accentColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.10,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: isLoading ? Icons.sync : Icons.hub_outlined,
                color: accentColor,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoading ? '正在验证服务' : '私有服务连接',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoading
                          ? '检查地址、初始化状态和登录入口'
                          : '一个地址连接你的 Web、iOS 和 Android 数据源',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ConnectionAssuranceRail(accentColor: accentColor),
        ],
      ),
    );
  }
}

class _ConnectionAssuranceRail extends StatelessWidget {
  const _ConnectionAssuranceRail({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        Expanded(
          child: _ConnectionAssuranceTile(
            icon: Icons.lock_outline,
            label: 'HTTPS',
            color: accentColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ConnectionAssuranceTile(
            icon: Icons.verified_outlined,
            label: '初始化一次',
            color: financeColors.income,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ConnectionAssuranceTile(
            icon: Icons.devices_other_outlined,
            label: '跨端同步',
            color: financeColors.asset,
          ),
        ),
      ],
    );
  }
}

class _ConnectionAssuranceTile extends StatelessWidget {
  const _ConnectionAssuranceTile({
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 5),
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

class _ServerCapabilityGrid extends StatelessWidget {
  const _ServerCapabilityGrid();

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        Expanded(
          child: _ServerCapabilityTile(
            label: '家庭',
            icon: Icons.group_outlined,
            color: financeColors.asset,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ServerCapabilityTile(
            label: 'AI',
            icon: Icons.auto_awesome_outlined,
            color: financeColors.brand,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ServerCapabilityTile(
            label: '备份',
            icon: Icons.cloud_done_outlined,
            color: financeColors.income,
          ),
        ),
      ],
    );
  }
}

class _ServerCapabilityTile extends StatelessWidget {
  const _ServerCapabilityTile({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      accentColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
