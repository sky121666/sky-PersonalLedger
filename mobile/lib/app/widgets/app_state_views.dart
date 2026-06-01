import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'finance_dashboard_widgets.dart';
import 'premium_surface.dart';

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({this.message = '加载中...', super.key});

  final String message;

  /// 构建统一加载态视图。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: _StateViewFrame(
        accentColor: colorScheme.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LoadingIndicatorTile(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _StateDiagnosticDeck(
              items: [
                _StateDiagnosticItem(
                  icon: Icons.storage_outlined,
                  label: '本地缓存',
                  value: '预热中',
                  color: AppTheme.financeColors(context).asset,
                ),
                _StateDiagnosticItem(
                  icon: Icons.wifi_tethering_outlined,
                  label: '接口连通',
                  value: '探测中',
                  color: colorScheme.primary,
                ),
                _StateDiagnosticItem(
                  icon: Icons.auto_awesome_outlined,
                  label: '主题渲染',
                  value: '同步中',
                  color: AppTheme.financeColors(context).income,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StateSignalStrip(
              items: [
                _StateSignalItem(label: '连接', value: '检查中'),
                _StateSignalItem(label: '同步', value: '等待中'),
                _StateSignalItem(label: '界面', value: '渲染中'),
              ],
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            _StateEvidenceRail(
              key: const ValueKey('state-loading-evidence-rail'),
              icon: Icons.sync_outlined,
              title: '加载证据',
              value: '3/3',
              caption: '缓存、接口、主题同步中',
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  /// 构建统一空态视图。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = AppTheme.financeColors(context).asset;
    return Center(
      child: _StateViewFrame(
        accentColor: accentColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon: icon, color: accentColor, size: 58, iconSize: 28),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _StateDiagnosticDeck(
              items: [
                _StateDiagnosticItem(
                  icon: Icons.search_off_outlined,
                  label: '内容状态',
                  value: '空',
                  color: accentColor,
                ),
                _StateDiagnosticItem(
                  icon: Icons.add_circle_outline,
                  label: '下一步',
                  value: action == null ? '等待' : '创建',
                  color: AppTheme.financeColors(context).income,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StateSignalStrip(
              items: [
                _StateSignalItem(label: '状态', value: '暂无内容'),
                _StateSignalItem(
                  label: '操作',
                  value: action == null ? '等待数据' : '可创建',
                ),
              ],
              color: accentColor,
            ),
            const SizedBox(height: 12),
            _StateEvidenceRail(
              key: const ValueKey('state-empty-evidence-rail'),
              icon: Icons.rule_folder_outlined,
              title: '空态证据',
              value: action == null ? '1/2' : '2/2',
              caption: action == null ? '内容为空，等待数据' : '内容为空，可创建',
              color: accentColor,
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    required this.message,
    this.title = '出错了',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  /// 构建统一错误态视图。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: _StateViewFrame(
        accentColor: colorScheme.error,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon: Icons.error_outline,
              color: colorScheme.error,
              size: 58,
              iconSize: 28,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            _StateDiagnosticDeck(
              items: [
                _StateDiagnosticItem(
                  icon: Icons.report_gmailerrorred_outlined,
                  label: '异常状态',
                  value: '已捕获',
                  color: colorScheme.error,
                ),
                _StateDiagnosticItem(
                  icon: Icons.restart_alt_outlined,
                  label: '恢复动作',
                  value: onRetry == null ? '待处理' : '可重试',
                  color: AppTheme.financeColors(context).warning,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StateSignalStrip(
              items: [
                _StateSignalItem(label: '状态', value: '异常'),
                _StateSignalItem(
                  label: '恢复',
                  value: onRetry == null ? '稍后重试' : '可重试',
                ),
              ],
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),
            _StateEvidenceRail(
              key: const ValueKey('state-error-evidence-rail'),
              icon: Icons.health_and_safety_outlined,
              title: '恢复证据',
              value: onRetry == null ? '1/2' : '2/2',
              caption: onRetry == null ? '异常已捕获，等待恢复' : '异常已捕获，可重试',
              color: colorScheme.error,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('state-error-retry-button'),
                onPressed: onRetry,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('重试'),
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

class _StateEvidenceRail extends StatelessWidget {
  const _StateEvidenceRail({
    super.key,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.15
                : 0.075,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
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
          ),
          const SizedBox(width: 8),
          _StateEvidencePill(label: value, color: color),
        ],
      ),
    );
  }
}

class _StateEvidencePill extends StatelessWidget {
  const _StateEvidencePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
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
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _StateViewFrame extends StatelessWidget {
  const _StateViewFrame({required this.accentColor, required this.child});

  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: PremiumSurface(accentColor: accentColor, child: child),
      ),
    );
  }
}

class _StateDiagnosticItem {
  const _StateDiagnosticItem({
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

class _StateDiagnosticDeck extends StatelessWidget {
  const _StateDiagnosticDeck({required this.items});

  final List<_StateDiagnosticItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 8.0;
        final columns = constraints.maxWidth >= 390 && items.length >= 3
            ? 3
            : constraints.maxWidth >= 330 && items.length >= 2
            ? 2
            : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _StateDiagnosticTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _StateDiagnosticTile extends StatelessWidget {
  const _StateDiagnosticTile({required this.item});

  final _StateDiagnosticItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          item.color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.075,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          IconBadge(icon: item.icon, color: item.color, size: 34, iconSize: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StateSignalItem {
  const _StateSignalItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _StateSignalStrip extends StatelessWidget {
  const _StateSignalStrip({required this.items, required this.color});

  final List<_StateSignalItem> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items) _StateSignalChip(item: item, color: color),
      ],
    );
  }
}

class _StateSignalChip extends StatelessWidget {
  const _StateSignalChip({required this.item, required this.color});

  final _StateSignalItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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
      child: Text(
        '${item.label} · ${item.value}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LoadingIndicatorTile extends StatelessWidget {
  const _LoadingIndicatorTile({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.72, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 76,
        height: 58,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            color.withValues(alpha: 0.14),
            colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }
}

class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    required this.title,
    required this.message,
    this.cancelText = '取消',
    this.confirmText = '确认',
    this.isDanger = false,
    super.key,
  });

  final String title;
  final String message;
  final String cancelText;
  final String confirmText;
  final bool isDanger;

  /// 构建统一确认弹窗。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isDanger ? colorScheme.error : colorScheme.primary;
    final riskLabel = isDanger ? '高风险操作' : '确认操作';
    final dialogSemanticLabel = '$title，$riskLabel，需手动确认';
    return Semantics(
      container: true,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: dialogSemanticLabel,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: PremiumSurface(
            semanticLabel: dialogSemanticLabel,
            accentColor: accentColor,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconBadge(
                      icon: isDanger
                          ? Icons.warning_amber_rounded
                          : Icons.help_outline,
                      color: accentColor,
                      size: 48,
                      iconSize: 25,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _StateSignalStrip(
                  items: [
                    _StateSignalItem(
                      label: '操作',
                      value: isDanger ? '高风险' : '待确认',
                    ),
                    _StateSignalItem(label: '结果', value: '需手动确认'),
                  ],
                  color: accentColor,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(cancelText),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: isDanger
                            ? FilledButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                              )
                            : null,
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(confirmText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 展示统一确认弹窗并返回用户选择。
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelText = '取消',
  String confirmText = '确认',
  bool isDanger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AppConfirmDialog(
      title: title,
      message: message,
      cancelText: cancelText,
      confirmText: confirmText,
      isDanger: isDanger,
    ),
  );
  return result ?? false;
}
