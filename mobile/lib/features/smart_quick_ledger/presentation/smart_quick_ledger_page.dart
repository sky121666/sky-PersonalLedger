import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../transactions/data/transaction_models.dart';
import '../data/quick_ledger_draft.dart';
import '../data/quick_ledger_repository.dart';

class SmartQuickLedgerPage extends ConsumerStatefulWidget {
  const SmartQuickLedgerPage({super.key});

  @override
  ConsumerState<SmartQuickLedgerPage> createState() =>
      _SmartQuickLedgerPageState();
}

class _SmartQuickLedgerPageState extends ConsumerState<SmartQuickLedgerPage> {
  final Set<String> _enabledSources = {'wechat', 'alipay', 'bank'};
  String? _busyDraftId;
  bool? _notificationListenerEnabled;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _loadPlatformState();
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(quickLedgerDraftsProvider);
    final rows = [
      _SmartLedgerRow(
        _CapabilityCard(
          isAndroid: _isAndroid,
          isIOS: _isIOS,
          notificationListenerEnabled: _notificationListenerEnabled,
          onOpenNotificationSettings: _openNotificationSettings,
        ),
      ),
      _SmartLedgerRow(
        _SourceSettingsCard(
          enabledSources: _enabledSources,
          onChanged: _toggleSource,
        ),
      ),
      _SmartLedgerRow(
        _PendingDraftsCard(
          drafts: drafts,
          busyDraftId: _busyDraftId,
          onConfirm: _confirmDraft,
          onDismiss: _dismissDraft,
        ),
      ),
      const _SmartLedgerRow(_ShortcutEntryCard(), 0),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('智能快记')),
      body: AdaptivePageContainer(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
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

  Future<void> _loadPlatformState() async {
    final controller = ref.read(quickLedgerDraftsProvider.notifier);
    final notificationEnabled = await controller
        .isNotificationListenerEnabled();
    final enabledSources = await controller.getEnabledSources();
    await controller.loadFromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationListenerEnabled = notificationEnabled;
      _enabledSources
        ..clear()
        ..addAll(enabledSources);
    });
  }

  void _toggleSource(String id, bool enabled) {
    setState(() {
      if (enabled) {
        _enabledSources.add(id);
      } else {
        _enabledSources.remove(id);
      }
    });
    unawaited(
      ref
          .read(quickLedgerDraftsProvider.notifier)
          .setEnabledSources(_enabledSources),
    );
  }

  Future<void> _openNotificationSettings() async {
    await ref
        .read(quickLedgerDraftsProvider.notifier)
        .openNotificationListenerSettings();
  }

  Future<void> _confirmDraft(QuickLedgerDraft draft) async {
    setState(() => _busyDraftId = draft.id);
    try {
      await ref.read(quickLedgerDraftsProvider.notifier).confirm(draft.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已记入账本')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('确认未完成')));
    } finally {
      if (mounted) {
        setState(() => _busyDraftId = null);
      }
    }
  }

  void _dismissDraft(QuickLedgerDraft draft) {
    unawaited(ref.read(quickLedgerDraftsProvider.notifier).dismiss(draft.id));
  }
}

class _SmartLedgerRow {
  const _SmartLedgerRow(this.child, [this.bottomSpacing = 12]);

  final Widget child;
  final double bottomSpacing;
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.isAndroid,
    required this.isIOS,
    required this.notificationListenerEnabled,
    required this.onOpenNotificationSettings,
  });

  final bool isAndroid;
  final bool isIOS;
  final bool? notificationListenerEnabled;
  final VoidCallback onOpenNotificationSettings;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      key: const ValueKey('smart-ledger-capability-card'),
      accentColor: financeColors.asset,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.auto_awesome_outlined,
                color: financeColors.asset,
                size: 42,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '智能候选记账',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '本地解析 · 确认后入账',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CapabilityLine(
            icon: Icons.android_outlined,
            title: 'Android',
            value: _androidStatus,
            active: isAndroid,
            onTap: isAndroid ? onOpenNotificationSettings : null,
          ),
          const SizedBox(height: 8),
          _CapabilityLine(
            icon: Icons.phone_iphone_outlined,
            title: 'iOS',
            value: isIOS ? '快捷入口可用' : '快捷入口',
            active: isIOS,
          ),
        ],
      ),
    );
  }

  String get _androidStatus {
    if (!isAndroid) {
      return '通知监听';
    }
    return notificationListenerEnabled == true ? '已开启' : '待授权';
  }
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine({
    required this.icon,
    required this.title,
    required this.value,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = active ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: 0.06),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceSettingsCard extends StatelessWidget {
  const _SourceSettingsCard({
    required this.enabledSources,
    required this.onChanged,
  });

  final Set<String> enabledSources;
  final void Function(String id, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final sources = [
      _SourceConfig('wechat', '微信支付', 'com.tencent.mm', Icons.chat_outlined),
      _SourceConfig(
        'alipay',
        '支付宝',
        'com.eg.android.AlipayGphone',
        Icons.account_balance_wallet_outlined,
      ),
      _SourceConfig('bank', '银行提醒', '银行 App 白名单', Icons.account_balance),
      _SourceConfig('unionpay', '云闪付', '支付通知', Icons.credit_card_outlined),
    ];
    return PremiumSurface(
      key: const ValueKey('smart-ledger-source-card'),
      accentColor: AppTheme.financeColors(context).income,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '通知来源',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final source in sources)
            _SourceSwitchTile(
              source: source,
              enabled: enabledSources.contains(source.id),
              onChanged: (enabled) => onChanged(source.id, enabled),
            ),
          const SizedBox(height: 4),
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _RuleChip(label: '金额'),
              _RuleChip(label: '商户'),
              _RuleChip(label: '收支'),
              _RuleChip(label: '去重'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceConfig {
  const _SourceConfig(this.id, this.title, this.subtitle, this.icon);

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _SourceSwitchTile extends StatelessWidget {
  const _SourceSwitchTile({
    required this.source,
    required this.enabled,
    required this.onChanged,
  });

  final _SourceConfig source;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('smart-ledger-source-${source.id}'),
      label: source.title,
      toggled: enabled,
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(source.icon, size: 20),
        title: Text(
          source.title,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          source.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }
}

class _PendingDraftsCard extends StatelessWidget {
  const _PendingDraftsCard({
    required this.drafts,
    required this.busyDraftId,
    required this.onConfirm,
    required this.onDismiss,
  });

  final List<QuickLedgerDraft> drafts;
  final String? busyDraftId;
  final ValueChanged<QuickLedgerDraft> onConfirm;
  final ValueChanged<QuickLedgerDraft> onDismiss;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      key: const ValueKey('smart-ledger-pending-card'),
      accentColor: AppTheme.financeColors(context).warning,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '待确认',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${drafts.length} 条',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (drafts.isEmpty)
            Text(
              '暂无候选',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final draft in drafts.indexed) ...[
              _DraftTile(
                draft: draft.$2,
                busy: busyDraftId == draft.$2.id,
                onConfirm: () => onConfirm(draft.$2),
                onDismiss: () => onDismiss(draft.$2),
              ),
              if (draft.$1 != drafts.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.busy,
    required this.onConfirm,
    required this.onDismiss,
  });

  final QuickLedgerDraft draft;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final amountColor = draft.type == TransactionType.income
        ? financeColors.income
        : financeColors.expense;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          amountColor.withValues(alpha: 0.045),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: draft.source == QuickLedgerDraftSource.androidNotification
                    ? Icons.notifications_active_outlined
                    : Icons.bolt_outlined,
                color: amountColor,
                size: 38,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.sourceName} · ${draft.suggestedCategoryName.isEmpty ? draft.typeLabel : draft.suggestedCategoryName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatSignedMoney(draft.amount, draft.type),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ConfidencePill(value: draft.confidence),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onDismiss,
                child: const Text('忽略'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                key: ValueKey('smart-ledger-confirm-${draft.id}'),
                onPressed: busy ? null : onConfirm,
                child: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('确认'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round().clamp(0, 100);
    return Text(
      '$percent%',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ShortcutEntryCard extends StatelessWidget {
  const _ShortcutEntryCard();

  @override
  Widget build(BuildContext context) {
    final items = [
      _ShortcutItem(Icons.keyboard_voice_outlined, 'Siri', '快捷指令'),
      _ShortcutItem(Icons.widgets_outlined, '小组件', '桌面入口'),
      _ShortcutItem(Icons.ios_share_outlined, '分享', '文本导入'),
      _ShortcutItem(Icons.image_search_outlined, '截图', 'OCR'),
    ];
    return PremiumSurface(
      key: const ValueKey('smart-ledger-shortcut-card'),
      accentColor: Theme.of(context).colorScheme.tertiary,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '快捷入口',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: width,
                      child: _ShortcutTile(item: item),
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

class _ShortcutItem {
  const _ShortcutItem(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.item});

  final _ShortcutItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.tertiary.withValues(alpha: 0.045),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 19, color: colorScheme.tertiary),
          const SizedBox(height: 6),
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            item.subtitle,
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

String _formatSignedMoney(double amount, TransactionType type) {
  final sign = type == TransactionType.income ? '+' : '-';
  return '$sign¥${amount.toStringAsFixed(2)}';
}
