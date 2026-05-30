import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../data/ai_report_repository.dart';

class AIReportsPage extends ConsumerStatefulWidget {
  const AIReportsPage({super.key});

  @override
  ConsumerState<AIReportsPage> createState() => _AIReportsPageState();
}

class _AIReportsPageState extends ConsumerState<AIReportsPage> {
  var _generating = false;
  var _savingSchedule = false;
  var _triggeringSchedule = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiReportsProvider);
    final scheduleState = ref.watch(aiReportScheduleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 财务报告'),
        actions: [
          IconButton(
            onPressed: _generating ? null : _generateWeeklyReport,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            tooltip: '生成本周报告',
          ),
        ],
      ),
      body: AdaptivePageContainer(
        child: state.when(
          loading: () => const AppLoadingView(message: '正在加载 AI 报告'),
          error: (error, stackTrace) => AppErrorView(
            message: 'AI 报告加载失败：$error',
            onRetry: () => ref.invalidate(aiReportsProvider),
          ),
          data: (reports) {
            final scheduleSurface = _AIReportScheduleSurface(
              state: scheduleState,
              saving: _savingSchedule,
              triggering: _triggeringSchedule,
              onChanged: _saveSchedule,
              onTrigger: _triggerSchedule,
            );
            if (reports.isEmpty) {
              return ListView(
                children: [
                  scheduleSurface,
                  const SizedBox(height: 12),
                  _AIReportsEmptyState(
                    generating: _generating,
                    onGenerate: _generating ? null : _generateWeeklyReport,
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: reports.length + (_generating ? 1 : 0) + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return scheduleSurface;
                }
                if (_generating && index == 1) {
                  return const _AIReportGeneratingSurface();
                }
                final reportIndex = index - 1 - (_generating ? 1 : 0);
                final report = reports[reportIndex];
                return StaggeredEntrance(
                  index: index,
                  child: _AIReportCard(
                    report: report,
                    title: _reportTitle(report.reportType),
                    statusText: _statusText(report.status),
                    period:
                        '${_formatDate(report.periodStart)} - ${_formatDate(report.periodEnd)}',
                    onRegenerate: report.status == 'failed'
                        ? _generateWeeklyReport
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _generateWeeklyReport() async {
    setState(() => _generating = true);
    try {
      final now = DateTime.now();
      final weekday = now.weekday;
      final start = DateTime(now.year, now.month, now.day - weekday + 1);
      final end = start.add(const Duration(days: 6));
      await ref
          .read(aiReportRepositoryProvider)
          .generateReport(
            GenerateAIReportRequest(
              reportType: 'weekly',
              periodStart: _formatRequestDate(start),
              periodEnd: _formatRequestDate(end),
            ),
          );
      ref.invalidate(aiReportsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 报告已生成')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('AI 报告生成失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  Future<void> _saveSchedule(AIReportScheduleSettings settings) async {
    setState(() => _savingSchedule = true);
    try {
      await ref
          .read(aiReportRepositoryProvider)
          .updateScheduleSettings(settings);
      ref.invalidate(aiReportScheduleProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('自动报告设置已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存自动报告失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _savingSchedule = false);
      }
    }
  }

  Future<void> _triggerSchedule() async {
    setState(() => _triggeringSchedule = true);
    try {
      final results = await ref
          .read(aiReportRepositoryProvider)
          .triggerSchedule();
      ref
        ..invalidate(aiReportsProvider)
        ..invalidate(aiReportScheduleProvider);
      final succeeded = results.fold<int>(
        0,
        (sum, result) => sum + result.succeeded,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(succeeded > 0 ? '已生成 $succeeded 份自动报告' : '自动报告检查完成'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('触发自动报告失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _triggeringSchedule = false);
      }
    }
  }

  String _formatRequestDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _reportTitle(String type) {
    return switch (type) {
      'weekly' => '每周总结',
      'monthly' => '月度总结',
      'family' => '家庭分析',
      'budget' => '预算建议',
      _ => '财务分析',
    };
  }

  String _statusText(String status) {
    return switch (status) {
      'completed' => '已完成',
      'running' => '生成中',
      'failed' => '失败',
      _ => '待处理',
    };
  }

  String _formatDate(String value) {
    if (value.length >= 10) {
      return value.substring(0, 10);
    }
    return value;
  }
}

class _AIReportScheduleSurface extends StatelessWidget {
  const _AIReportScheduleSurface({
    required this.state,
    required this.saving,
    required this.triggering,
    required this.onChanged,
    required this.onTrigger,
  });

  final AsyncValue<AIReportScheduleSettings> state;
  final bool saving;
  final bool triggering;
  final ValueChanged<AIReportScheduleSettings> onChanged;
  final VoidCallback onTrigger;

  @override
  Widget build(BuildContext context) {
    return state.when(
      loading: () => const PremiumSurface(
        child: ListTile(
          leading: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('正在加载自动报告设置'),
        ),
      ),
      error: (error, stackTrace) => PremiumSurface(
        accentColor: Theme.of(context).colorScheme.error,
        child: Text('自动报告设置加载失败：$error'),
      ),
      data: (settings) => _AIReportScheduleForm(
        settings: settings,
        saving: saving,
        triggering: triggering,
        onChanged: onChanged,
        onTrigger: onTrigger,
      ),
    );
  }
}

class _AIReportScheduleForm extends StatelessWidget {
  const _AIReportScheduleForm({
    required this.settings,
    required this.saving,
    required this.triggering,
    required this.onChanged,
    required this.onTrigger,
  });

  final AIReportScheduleSettings settings;
  final bool saving;
  final bool triggering;
  final ValueChanged<AIReportScheduleSettings> onChanged;
  final VoidCallback onTrigger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat_outlined, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '自动报告',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _AIReportStatusChip(
                status: settings.enabled ? 'completed' : 'pending',
                label: settings.enabled ? '已开启' : '默认关闭',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.enabled,
            title: const Text('启用自动生成'),
            subtitle: const Text('只发送聚合快照，不包含交易备注和附件。'),
            onChanged: saving
                ? null
                : (value) => onChanged(settings.copyWith(enabled: value)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                selected: settings.weeklyEnabled,
                label: const Text('每周总结'),
                onSelected: saving
                    ? null
                    : (value) =>
                          onChanged(settings.copyWith(weeklyEnabled: value)),
              ),
              FilterChip(
                selected: settings.monthlyEnabled,
                label: const Text('月度总结'),
                onSelected: saving
                    ? null
                    : (value) =>
                          onChanged(settings.copyWith(monthlyEnabled: value)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('运行小时'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _normalizedHour(settings.hour),
                items: [
                  for (var hour = 0; hour < 24; hour++)
                    DropdownMenuItem(value: hour, child: Text('$hour:00')),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) {
                          onChanged(settings.copyWith(hour: value));
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '周报上次检查：${settings.lastWeeklyRun.isEmpty ? '无' : settings.lastWeeklyRun}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
          Text(
            '月报上次检查：${settings.lastMonthlyRun.isEmpty ? '无' : settings.lastMonthlyRun}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: triggering ? null : onTrigger,
              icon: triggering
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_outlined),
              label: const Text('立即触发应生成报告'),
            ),
          ),
        ],
      ),
    );
  }

  int _normalizedHour(int hour) {
    if (hour < 0) return 0;
    if (hour > 23) return 23;
    return hour;
  }
}

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
    return Center(
      child: PremiumSurface(
        accentColor: AppTheme.assetColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '暂无 AI 报告',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '配置 OpenAI 兼容 Provider 后，可生成周报并在这里查看聚合后的财务洞察。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onGenerate,
              icon: generating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: const Text('生成本周报告'),
            ),
            if (generating) ...[
              const SizedBox(height: 12),
              const _AIReportGeneratingSurface(compact: true),
            ],
          ],
        ),
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
                '正在生成 AI 洞察',
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
    this.onRegenerate,
  });

  final AIReportSummary report;
  final String title;
  final String statusText;
  final String period;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final parsed = AIReportContentData.parse(report);
    final isFailed = report.status == 'failed';
    return PremiumSurface(
      padding: EdgeInsets.zero,
      accentColor: isFailed ? colorScheme.error : AppTheme.assetColor,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          expansionTileTheme: const ExpansionTileThemeData(
            tilePadding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            childrenPadding: EdgeInsets.fromLTRB(18, 0, 18, 18),
          ),
        ),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor:
                (isFailed ? colorScheme.error : colorScheme.primary).withValues(
                  alpha: 0.12,
                ),
            foregroundColor: isFailed ? colorScheme.error : colorScheme.primary,
            child: Icon(
              isFailed ? Icons.error_outline : Icons.auto_graph_outlined,
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
                  '${report.providerName} / ${report.model}',
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
            status: report.status,
            label: statusText,
          ),
          children: [
            _AIReportContent(data: parsed),
            if (isFailed && onRegenerate != null) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: onRegenerate,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('重新生成'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AIReportStatusChip extends StatelessWidget {
  const _AIReportStatusChip({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      'completed' => AppTheme.incomeColor,
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
    if (data.summary.isEmpty &&
        data.highlights.isEmpty &&
        data.risks.isEmpty &&
        data.suggestions.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('暂无报告内容'),
      );
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
            color: AppTheme.incomeColor,
            items: data.highlights,
          ),
        ],
        if (data.risks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AIReportSection(
            title: '风险',
            icon: Icons.warning_amber_outlined,
            color: AppTheme.warningColor,
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
