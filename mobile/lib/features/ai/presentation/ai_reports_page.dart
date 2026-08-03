import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../data/ai_report_repository.dart';

part 'ai_report_content_part.dart';
part 'ai_report_settings_part.dart';

class AIReportsPage extends ConsumerStatefulWidget {
  const AIReportsPage({super.key});

  @override
  ConsumerState<AIReportsPage> createState() => _AIReportsPageState();
}

class _AIReportsPageState extends ConsumerState<AIReportsPage> {
  var _generating = false;
  var _savingSchedule = false;
  var _triggeringSchedule = false;
  String? _testingProviderId;
  String? _deletingReportId;
  final _deletedReportIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiReportsProvider);
    final scheduleState = ref.watch(aiReportScheduleProvider);
    final providerState = ref.watch(aiProviderSetupProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('财务报告'),
        actions: [
          IconButton(
            key: const ValueKey('ai-report-generate'),
            onPressed: _generating ? null : _showGenerateReportSheet,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            tooltip: '生成财务报告',
          ),
        ],
      ),
      body: AdaptivePageContainer(
        child: state.when(
          loading: () => const AppLoadingView(message: '正在加载报告'),
          error: (error, stackTrace) => AppErrorView(
            message: '报告加载失败',
            onRetry: () => ref.invalidate(aiReportsProvider),
          ),
          data: (reports) {
            final visibleReports = reports
                .where((report) => !_deletedReportIds.contains(report.id))
                .toList();
            final providerSurface = _AIProviderSetupSurface(
              state: providerState,
              testingProviderId: _testingProviderId,
              onAdd: _showProviderSheet,
              onEdit: (setup, provider) =>
                  _showProviderSheet(setup, provider: provider),
              onDelete: _deleteProvider,
              onTest: _testProvider,
            );
            final scheduleSurface = _AIReportScheduleSurface(
              state: scheduleState,
              saving: _savingSchedule,
              triggering: _triggeringSchedule,
              onChanged: _saveSchedule,
              onTrigger: _triggerSchedule,
            );
            final utilityBar = _AIReportsUtilityBar(
              providerState: providerState,
              scheduleState: scheduleState,
              onProviders: () => _showSettingsSheet(providerSurface),
              onSchedule: () => _showSettingsSheet(scheduleSurface),
            );
            if (visibleReports.isEmpty) {
              final rows = [
                providerSurface,
                const SizedBox(height: 12),
                scheduleSurface,
                const SizedBox(height: 12),
                _AIReportsEmptyState(
                  generating: _generating,
                  onGenerate: _generating ? null : _showGenerateReportSheet,
                ),
              ];
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => rows[index],
              );
            }
            return ListView.separated(
              itemCount: visibleReports.length + (_generating ? 1 : 0) + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return utilityBar;
                }
                if (_generating && index == 1) {
                  return const _AIReportGeneratingSurface();
                }
                final reportIndex = index - 1 - (_generating ? 1 : 0);
                final report = visibleReports[reportIndex];
                return _AIReportCard(
                  report: report,
                  title: _reportTitle(report.reportType),
                  statusText: _statusText(report.status),
                  period:
                      '${_formatDate(report.periodStart)} - ${_formatDate(report.periodEnd)}',
                  deleting: _deletingReportId == report.id,
                  onDelete: () => _deleteReport(report),
                  onRegenerate: report.status == 'failed'
                      ? _showGenerateReportSheet
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showSettingsSheet(Widget content) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: SingleChildScrollView(child: content),
        ),
      ),
    );
  }

  Future<void> _showProviderSheet(
    AIProviderSetupData setup, {
    AIProviderSummary? provider,
  }) async {
    final presets = setup.presets.isEmpty
        ? const [
            AIProviderPreset(
              id: 'deepseek',
              name: 'DeepSeek',
              providerType: 'openai_compatible',
              baseUrl: 'https://api.deepseek.com',
              model: 'deepseek-v4-flash',
              models: [
                'deepseek-v4-flash',
                'deepseek-v4-pro',
                'deepseek-chat',
                'deepseek-reasoner',
              ],
            ),
          ]
        : setup.presets;
    final request = await showModalBottomSheet<SaveAIProviderRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _AIProviderEditorSheet(presets: presets, provider: provider),
    );
    if (request == null) {
      return;
    }
    try {
      if (provider == null) {
        await ref.read(aiReportRepositoryProvider).createProvider(request);
      } else {
        await ref
            .read(aiReportRepositoryProvider)
            .updateProvider(provider.id, request);
      }
      ref.invalidate(aiProviderSetupProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider == null ? '方式已保存' : '方式已更新')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存方式失败')));
      }
    }
  }

  Future<void> _deleteProvider(AIProviderSummary provider) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除分析方式',
      message: '删除「${provider.name}」？',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      await ref.read(aiReportRepositoryProvider).deleteProvider(provider.id);
      ref.invalidate(aiProviderSetupProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('方式已删除')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除方式失败')));
      }
    }
  }

  Future<void> _testProvider(AIProviderSummary provider) async {
    setState(() => _testingProviderId = provider.id);
    try {
      await ref.read(aiReportRepositoryProvider).testProvider(provider.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('服务检查通过')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('服务检查失败')));
      }
    } finally {
      if (mounted) {
        setState(() => _testingProviderId = null);
      }
    }
  }

  Future<void> _showGenerateReportSheet() async {
    late final AIProviderSetupData setup;
    try {
      setup = await ref.read(aiProviderSetupProvider.future);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分析方式加载失败')));
      }
      return;
    }
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    final weekday = now.weekday;
    final start = DateTime(now.year, now.month, now.day - weekday + 1);
    final end = start.add(const Duration(days: 6));
    final request = await showModalBottomSheet<GenerateAIReportRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AIReportGenerateSheet(
        providers: setup.providers
            .where((provider) => provider.enabled)
            .toList(),
        defaultStart: _formatRequestDate(start),
        defaultEnd: _formatRequestDate(end),
      ),
    );
    if (request == null) {
      return;
    }
    await _generateReport(request);
  }

  Future<void> _generateReport(GenerateAIReportRequest request) async {
    setState(() => _generating = true);
    try {
      await ref.read(aiReportRepositoryProvider).generateReport(request);
      ref.invalidate(aiReportsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('报告已生成')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('报告生成失败')));
      }
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  Future<void> _deleteReport(AIReportSummary report) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除报告',
      message: '删除「${_reportTitle(report.reportType)}」？',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _deletingReportId = report.id);
    try {
      await ref.read(aiReportRepositoryProvider).deleteReport(report.id);
      setState(() => _deletedReportIds.add(report.id));
      final _ = await ref.refresh(aiReportsProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('报告已删除')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除报告失败')));
      }
    } finally {
      if (mounted) {
        setState(() => _deletingReportId = null);
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
        ).showSnackBar(const SnackBar(content: Text('定期报告设置已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存定期报告失败')));
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
            content: Text(succeeded > 0 ? '已生成 $succeeded 份定期报告' : '定期报告检查完成'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成定期报告失败')));
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
