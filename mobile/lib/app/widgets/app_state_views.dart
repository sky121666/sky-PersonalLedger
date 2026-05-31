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
            _StateSignalStrip(
              items: [
                _StateSignalItem(label: '连接', value: '检查中'),
                _StateSignalItem(label: '同步', value: '等待中'),
                _StateSignalItem(label: '界面', value: '渲染中'),
              ],
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
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton(
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
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: isDanger
              ? FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
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
