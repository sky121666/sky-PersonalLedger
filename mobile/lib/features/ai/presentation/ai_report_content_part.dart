part of 'ai_reports_page.dart';

class _AIReportsEmptyState extends StatelessWidget {
  const _AIReportsEmptyState({
    required this.generating,
    required this.onGenerate,
  });

  final bool generating;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.asset,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.auto_awesome_outlined,
                color: colorScheme.primary,
                size: 42,
                iconSize: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '还没有报告',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '添加分析方式',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onGenerate,
              icon: generating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: const Text('生成报告'),
            ),
          ),
          if (generating) ...[
            const SizedBox(height: 12),
            const _AIReportGeneratingSurface(compact: true),
          ],
        ],
      ),
    );
  }
}

class _AIReportGeneratingSurface extends StatelessWidget {
  const _AIReportGeneratingSurface({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bars = <double>[0.92, 0.72, 0.54];
    return PremiumSurface(
      padding: EdgeInsets.all(compact ? 14 : 18),
      accentColor: colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                '正在生成报告',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...bars.map(
            (factor) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FractionallySizedBox(
                widthFactor: factor,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const SizedBox(height: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AIReportCard extends StatelessWidget {
  const _AIReportCard({
    required this.report,
    required this.title,
    required this.statusText,
    required this.period,
    required this.deleting,
    required this.onDelete,
    this.onRegenerate,
  });

  final AIReportSummary report;
  final String title;
  final String statusText;
  final String period;
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final parsed = AIReportContentData.parse(report);
    final snapshot = AIReportSnapshotData.parse(report.snapshotJson);
    final isFailed = report.status == 'failed';
    return PremiumSurface(
      key: ValueKey('ai-report-card-${report.id}'),
      padding: EdgeInsets.zero,
      accentColor: isFailed ? colorScheme.error : financeColors.asset,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          expansionTileTheme: const ExpansionTileThemeData(
            tilePadding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            childrenPadding: EdgeInsets.fromLTRB(18, 0, 18, 18),
          ),
        ),
        child: ExpansionTile(
          leading: DecoratedBox(
            decoration: BoxDecoration(
              color: (isFailed ? colorScheme.error : colorScheme.primary)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox.square(
              dimension: 34,
              child: Icon(
                isFailed ? Icons.error_outline : Icons.auto_graph_outlined,
                size: 18,
                color: isFailed ? colorScheme.error : colorScheme.primary,
              ),
            ),
          ),
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(period),
                const SizedBox(height: 4),
                Text(
                  report.providerName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
                ),
                if (parsed.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    parsed.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          trailing: _AIReportStatusChip(
            key: ValueKey('ai-report-status-${report.id}'),
            status: report.status,
            label: statusText,
          ),
          children: [
            _AIReportContent(data: parsed),
            if (snapshot.accountChanges.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AIReportAccountChanges(changes: snapshot.accountChanges),
            ],
            if (isFailed && onRegenerate != null) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onRegenerate,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('重新生成'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: deleting ? null : onDelete,
                  icon: deleting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('删除报告'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AIReportAccountChanges extends StatelessWidget {
  const _AIReportAccountChanges({required this.changes});

  final List<AIReportAccountChangeData> changes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 16,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '账户变化',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...changes.map(
          (change) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    change.accountName.isEmpty ? '账户' : change.accountName,
                  ),
                ),
                Text(
                  _formatSignedMoney(change.balanceDelta),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _moneyToneColor(context, change.balanceDelta),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AIReportStatusChip extends StatelessWidget {
  const _AIReportStatusChip({
    super.key,
    required this.status,
    required this.label,
  });

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final color = switch (status) {
      'completed' => financeColors.income,
      'running' => colorScheme.primary,
      'failed' => colorScheme.error,
      _ => colorScheme.outline,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AIReportContent extends StatelessWidget {
  const _AIReportContent({required this.data});

  final AIReportContentData data;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    if (data.summary.isEmpty &&
        data.highlights.isEmpty &&
        data.risks.isEmpty &&
        data.suggestions.isEmpty) {
      return const Align(alignment: Alignment.centerLeft, child: Text('还没有内容'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.summary.isNotEmpty) Text(data.summary),
        if (data.highlights.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AIReportSection(
            title: '重点',
            icon: Icons.trending_up_outlined,
            color: financeColors.income,
            items: data.highlights,
          ),
        ],
        if (data.risks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AIReportSection(
            title: '关注',
            icon: Icons.warning_amber_outlined,
            color: financeColors.warning,
            items: data.risks,
          ),
        ],
        if (data.suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AIReportSection(
            title: '建议',
            icon: Icons.lightbulb_outline,
            color: Theme.of(context).colorScheme.primary,
            items: data.suggestions,
          ),
        ],
      ],
    );
  }
}

class _AIReportSection extends StatelessWidget {
  const _AIReportSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...items.map((item) => Text('• $item')),
      ],
    );
  }
}

class AIReportSnapshotData {
  const AIReportSnapshotData({required this.accountChanges});

  final List<AIReportAccountChangeData> accountChanges;

  static AIReportSnapshotData parse(String value) {
    if (value.trim().isEmpty) {
      return const AIReportSnapshotData(accountChanges: []);
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        return const AIReportSnapshotData(accountChanges: []);
      }
      final changes = decoded['account_changes'];
      return AIReportSnapshotData(
        accountChanges: changes is List
            ? changes
                  .whereType<Map<String, dynamic>>()
                  .map(AIReportAccountChangeData.fromJson)
                  .where((change) => change.accountName.isNotEmpty)
                  .take(5)
                  .toList()
            : const [],
      );
    } catch (_) {
      return const AIReportSnapshotData(accountChanges: []);
    }
  }
}

class AIReportAccountChangeData {
  const AIReportAccountChangeData({
    required this.accountName,
    required this.balanceDelta,
  });

  final String accountName;
  final double balanceDelta;

  factory AIReportAccountChangeData.fromJson(Map<String, dynamic> json) {
    return AIReportAccountChangeData(
      accountName: json['account_name'] as String? ?? '',
      balanceDelta: _toDouble(json['balance_delta']),
    );
  }
}

class AIReportContentData {
  const AIReportContentData({
    required this.summary,
    required this.highlights,
    required this.risks,
    required this.suggestions,
  });

  final String summary;
  final List<String> highlights;
  final List<String> risks;
  final List<String> suggestions;

  static AIReportContentData parse(AIReportSummary report) {
    final content = _parseContent(report.contentJson);
    return AIReportContentData(
      summary: content['summary'] as String? ?? report.errorMessage,
      highlights: _stringList(content['highlights']),
      risks: _stringList(content['risks']),
      suggestions: _stringList(content['suggestions']),
    );
  }

  static Map<String, dynamic> _parseContent(String value) {
    if (value.trim().isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return {'summary': value};
    }
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.map((item) => '$item').toList();
  }
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _formatSignedMoney(double value) {
  return formatMoney(value, showPositiveSign: true);
}

Color _moneyToneColor(BuildContext context, double value) {
  final financeColors = AppTheme.financeColors(context);
  if (value > 0) return financeColors.income;
  if (value < 0) return financeColors.expense;
  return Theme.of(context).colorScheme.outline;
}
