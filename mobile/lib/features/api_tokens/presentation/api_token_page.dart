import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../data/api_token_repository.dart';

const _expiryOptions = [
  _ExpiryOption(0, '永不过期'),
  _ExpiryOption(30, '30 天'),
  _ExpiryOption(90, '90 天'),
  _ExpiryOption(365, '1 年'),
];

class ApiTokenPage extends ConsumerStatefulWidget {
  const ApiTokenPage({super.key});

  @override
  ConsumerState<ApiTokenPage> createState() => _ApiTokenPageState();
}

class _ApiTokenPageState extends ConsumerState<ApiTokenPage> {
  final _nameController = TextEditingController();

  var _tokens = <ApiTokenItem>[];
  var _expiryDays = 0;
  var _loading = true;
  var _submitting = false;
  Object? _error;
  String? _createdToken;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadTokens);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadTokens() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tokens = await ref.read(apiTokenRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() => _tokens = tokens);
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

  Future<void> _createToken() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入令牌名称')));
      return;
    }

    setState(() {
      _submitting = true;
      _createdToken = null;
    });
    try {
      final result = await ref
          .read(apiTokenRepositoryProvider)
          .create(
            ApiTokenCreateRequest(name: name, expiresInDays: _expiryDays),
          );
      final tokens = await ref.read(apiTokenRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() {
        _createdToken = result.token;
        _tokens = tokens;
        _nameController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('令牌创建成功，请立即复制保存')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _deleteToken(ApiTokenItem token) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除令牌',
      message: '删除后使用此令牌的 App 或 API 将无法访问。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(apiTokenRepositoryProvider).delete(token.id);
      final tokens = await ref.read(apiTokenRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() => _tokens = tokens);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('令牌已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _copyCreatedToken() async {
    final token = _createdToken;
    if (token == null || token.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Token'),
        actions: [
          IconButton(
            onPressed: _loadTokens,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: AdaptivePageContainer(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _tokens.isEmpty) {
      return const AppLoadingView(message: '令牌加载中...');
    }
    final error = _error;
    if (error != null && _tokens.isEmpty) {
      return AppErrorView(message: error.toString(), onRetry: _loadTokens);
    }

    return RefreshIndicator(
      onRefresh: _loadTokens,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          StaggeredEntrance(
            index: 0,
            child: _InfoCard(
              tokenCount: _tokens.length,
              createdToken: _createdToken,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 1,
            child: _TokenChannelConsole(
              tokenCount: _tokens.length,
              hasPendingToken: _createdToken != null,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 2,
            child: _TokenExposureRadar(
              tokens: _tokens,
              hasPendingToken: _createdToken != null,
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 3,
            child: _CreateTokenCard(
              nameController: _nameController,
              expiryDays: _expiryDays,
              submitting: _submitting,
              onExpiryChanged: (value) =>
                  setState(() => _expiryDays = value ?? _expiryDays),
              onCreate: _createToken,
            ),
          ),
          if (_createdToken != null) ...[
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 4,
              child: _CreatedTokenCard(
                token: _createdToken!,
                onCopy: _copyCreatedToken,
              ),
            ),
          ],
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: _createdToken == null ? 4 : 5,
            child: _TokenListHeader(tokenCount: _tokens.length),
          ),
          const SizedBox(height: 8),
          StaggeredEntrance(
            index: _createdToken == null ? 5 : 6,
            child: _tokens.isEmpty
                ? const PremiumSurface(
                    padding: EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                    child: AppEmptyView(
                      title: '暂无令牌',
                      message: '创建令牌后可用于 App 或 API 访问。',
                      icon: Icons.vpn_key_outlined,
                    ),
                  )
                : PremiumSurface(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < _tokens.length;
                          index++
                        ) ...[
                          _TokenTile(
                            token: _tokens[index],
                            deleting: _submitting,
                            onDelete: () => _deleteToken(_tokens[index]),
                          ),
                          if (index != _tokens.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TokenListHeader extends StatelessWidget {
  const _TokenListHeader({required this.tokenCount});

  final int tokenCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconBadge(
          icon: Icons.key_outlined,
          color: colorScheme.primary,
          size: 34,
          iconSize: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已创建的令牌',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                tokenCount == 0 ? '当前没有可用访问凭证' : '$tokenCount 个访问凭证正在管理中',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.tokenCount, required this.createdToken});

  final int tokenCount;
  final String? createdToken;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.vpn_key_outlined,
                color: colorScheme.primary,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'API 安全访问',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '完整令牌只会在创建成功后显示一次，请立即保存。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TokenSecurityPill(
                icon: Icons.key_outlined,
                label: '令牌数量',
                value: '$tokenCount 个',
                color: colorScheme.primary,
              ),
              _TokenSecurityPill(
                icon: Icons.lock_clock_outlined,
                label: '显示策略',
                value: createdToken == null ? '隐藏' : '待保存',
                color: createdToken == null
                    ? colorScheme.outline
                    : colorScheme.tertiary,
              ),
              _TokenSecurityPill(
                icon: Icons.fingerprint_outlined,
                label: '列表保护',
                value: '仅前缀',
                color: colorScheme.secondary,
              ),
              _TokenSecurityPill(
                icon: Icons.delete_sweep_outlined,
                label: '失效控制',
                value: '可撤销',
                color: AppTheme.financeColors(context).expense,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TokenSecurityPill extends StatelessWidget {
  const _TokenSecurityPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$label · $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenChannelConsole extends StatelessWidget {
  const _TokenChannelConsole({
    required this.tokenCount,
    required this.hasPendingToken,
  });

  final int tokenCount;
  final bool hasPendingToken;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      key: const ValueKey('api-token-channel-console'),
      accentColor: financeColors.asset,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.route_outlined,
                color: financeColors.asset,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '接口通道控制台',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _TokenChannelStatusPill(
                label: hasPendingToken ? '待保存' : '$tokenCount 个凭证',
                color: hasPendingToken
                    ? colorScheme.tertiary
                    : financeColors.income,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TokenChannelTile(
                  icon: Icons.phone_iphone_outlined,
                  label: '移动端',
                  value: 'App 登录',
                  color: financeColors.income,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TokenChannelTile(
                  icon: Icons.api_outlined,
                  label: 'OpenAPI',
                  value: '外部访问',
                  color: financeColors.asset,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TokenChannelTile(
                  icon: Icons.smart_toy_outlined,
                  label: 'AI/自动化',
                  value: '脚本隔离',
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TokenSafetyRail(
            activeTokens: tokenCount,
            hasPendingToken: hasPendingToken,
          ),
        ],
      ),
    );
  }
}

class _TokenChannelTile extends StatelessWidget {
  const _TokenChannelTile({
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
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
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

class _TokenSafetyRail extends StatelessWidget {
  const _TokenSafetyRail({
    required this.activeTokens,
    required this.hasPendingToken,
  });

  final int activeTokens;
  final bool hasPendingToken;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          financeColors.asset.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: financeColors.asset.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 18, color: financeColors.asset),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              hasPendingToken
                  ? '完整 Token 正在等待复制保存'
                  : activeTokens == 0
                  ? '还没有外部访问凭证'
                  : '完整 Token 不进入列表，仅保留前缀和撤销入口',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenChannelStatusPill extends StatelessWidget {
  const _TokenChannelStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TokenExposureRadar extends StatelessWidget {
  const _TokenExposureRadar({
    required this.tokens,
    required this.hasPendingToken,
  });

  final List<ApiTokenItem> tokens;
  final bool hasPendingToken;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final neverExpires = tokens.where((token) => token.neverExpires).length;
    final unused = tokens.where((token) => token.lastUsedAt == null).length;
    final expiring = tokens.where((token) => !token.neverExpires).length;
    final exposureLabel = hasPendingToken
        ? '待保存'
        : neverExpires > 0
        ? '需巡检'
        : '受控';
    return PremiumSurface(
      key: const ValueKey('api-token-exposure-radar'),
      accentColor: financeColors.warning,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.security_outlined,
                color: financeColors.warning,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '授权暴露面雷达',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _TokenChannelStatusPill(
                label: exposureLabel,
                color: hasPendingToken
                    ? colorScheme.tertiary
                    : neverExpires > 0
                    ? financeColors.warning
                    : financeColors.income,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TokenRadarMetric(
                icon: Icons.all_inclusive_outlined,
                label: '永久凭证',
                value: '$neverExpires 个',
                color: neverExpires > 0
                    ? financeColors.warning
                    : financeColors.income,
              ),
              _TokenRadarMetric(
                icon: Icons.history_toggle_off_outlined,
                label: '未使用',
                value: '$unused 个',
                color: unused > 0 ? financeColors.asset : financeColors.income,
              ),
              _TokenRadarMetric(
                icon: Icons.event_available_outlined,
                label: '限期凭证',
                value: '$expiring 个',
                color: colorScheme.tertiary,
              ),
              _TokenRadarMetric(
                icon: Icons.delete_outline,
                label: '可撤销',
                value: '${tokens.length} 个',
                color: financeColors.expense,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 18,
                color: financeColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasPendingToken
                      ? '新建 Token 仅本次可见，请完成复制后再离开'
                      : tokens.isEmpty
                      ? '当前没有外部访问凭证'
                      : '完整密钥不落入列表，建议定期清理永久凭证',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TokenRadarMetric extends StatelessWidget {
  const _TokenRadarMetric({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Column(
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
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(icon: icon, color: color, size: 42, iconSize: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TokenMetaPill extends StatelessWidget {
  const _TokenMetaPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _CreateTokenCard extends StatelessWidget {
  const _CreateTokenCard({
    required this.nameController,
    required this.expiryDays,
    required this.submitting,
    required this.onExpiryChanged,
    required this.onCreate,
  });

  final TextEditingController nameController;
  final int expiryDays;
  final bool submitting;
  final ValueChanged<int?> onExpiryChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.secondary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            icon: Icons.add_moderator_outlined,
            title: '创建新令牌',
            subtitle: '为移动端、自动化脚本或外部 API 创建独立访问凭证。',
            color: colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('api-token-name'),
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '令牌名称',
              hintText: '例如：我的手机',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '有效期',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _expiryOptions)
                ChoiceChip(
                  label: Text(option.label),
                  selected: expiryDays == option.days,
                  onSelected: submitting
                      ? null
                      : (_) => onExpiryChanged(option.days),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: submitting ? null : onCreate,
            icon: const Icon(Icons.add),
            label: Text(submitting ? '处理中...' : '创建令牌'),
          ),
        ],
      ),
    );
  }
}

class _CreatedTokenCard extends StatelessWidget {
  const _CreatedTokenCard({required this.token, required this.onCopy});

  final String token;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final successColor = AppTheme.financeColors(context).income;
    return PremiumSurface(
      accentColor: successColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            icon: Icons.check_circle_outline,
            title: '令牌创建成功',
            subtitle: '请立即复制并保存，此令牌只显示一次。',
            color: successColor,
          ),
          const SizedBox(height: 12),
          Semantics(
            label: '一次性完整令牌，请复制保存',
            textField: true,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  successColor.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.16
                        : 0.08,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: successColor.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 17,
                        color: successColor,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '一次性密钥保险箱',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: successColor,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      _TokenChannelStatusPill(
                        label: '仅本次可见',
                        color: successColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    key: const ValueKey('api-token-created-value'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    child: SelectableText(
                      token,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy),
            label: const Text('复制令牌'),
          ),
        ],
      ),
    );
  }
}

class _TokenTile extends StatelessWidget {
  const _TokenTile({
    required this.token,
    required this.deleting,
    required this.onDelete,
  });

  final ApiTokenItem token;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final statusColor = token.lastUsedAt == null
        ? financeColors.asset
        : financeColors.income;
    final expiryColor = token.expiresAt == null
        ? financeColors.warning
        : colorScheme.tertiary;
    return Semantics(
      label: '${token.name}，${_tokenSubtitle(token)}',
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colorScheme.primary.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.10
                  : 0.05,
            ),
            colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            IconBadge(
              icon: Icons.smartphone_outlined,
              color: colorScheme.primary,
              size: 42,
              iconSize: 21,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          token.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      _TokenChannelStatusPill(
                        label: token.neverExpires ? '需巡检' : '限期',
                        color: expiryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tokenSubtitle(token),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _TokenMetaPill(
                        icon: Icons.fingerprint_outlined,
                        label: '前缀 ${token.tokenPrefix}...',
                        color: colorScheme.primary,
                      ),
                      _TokenMetaPill(
                        icon: Icons.history_outlined,
                        label: token.lastUsedAt == null
                            ? '未使用'
                            : '最后使用 ${_formatDateTime(token.lastUsedAt!)}',
                        color: statusColor,
                      ),
                      _TokenMetaPill(
                        icon: Icons.event_outlined,
                        label: token.expiresAt == null
                            ? '永不过期'
                            : '${_formatDate(token.expiresAt!)} 过期',
                        color: expiryColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: deleting ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: deleting ? '正在处理' : '删除令牌',
              style: IconButton.styleFrom(
                foregroundColor: financeColors.expense,
                backgroundColor: financeColors.expense.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryOption {
  const _ExpiryOption(this.days, this.label);

  final int days;
  final String label;
}

String _tokenSubtitle(ApiTokenItem token) {
  final parts = <String>[
    '${token.tokenPrefix}...',
    token.lastUsedAt == null
        ? '未使用'
        : '最后使用 ${_formatDateTime(token.lastUsedAt!)}',
    token.expiresAt == null ? '永不过期' : '${_formatDate(token.expiresAt!)} 过期',
  ];
  return parts.join(' · ');
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${_formatDate(value)} ${two(value.hour)}:${two(value.minute)}';
}
