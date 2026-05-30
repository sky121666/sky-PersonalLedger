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
  String? _testingProviderId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiReportsProvider);
    final scheduleState = ref.watch(aiReportScheduleProvider);
    final providerState = ref.watch(aiProviderSetupProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 财务报告'),
        actions: [
          IconButton(
            onPressed: _generating ? null : _showGenerateReportSheet,
            icon: _generating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            tooltip: '生成报告',
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
            if (reports.isEmpty) {
              return ListView(
                children: [
                  providerSurface,
                  const SizedBox(height: 12),
                  scheduleSurface,
                  const SizedBox(height: 12),
                  _AIReportsEmptyState(
                    generating: _generating,
                    onGenerate: _generating ? null : _showGenerateReportSheet,
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: reports.length + (_generating ? 1 : 0) + 2,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return providerSurface;
                }
                if (index == 1) {
                  return scheduleSurface;
                }
                if (_generating && index == 2) {
                  return const _AIReportGeneratingSurface();
                }
                final reportIndex = index - 2 - (_generating ? 1 : 0);
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
                        ? _showGenerateReportSheet
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
          SnackBar(
            content: Text(provider == null ? 'Provider 已保存' : 'Provider 已更新'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存 Provider 失败：$error')));
      }
    }
  }

  Future<void> _deleteProvider(AIProviderSummary provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 Provider'),
        content: Text('删除「${provider.name}」？已生成报告不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(aiReportRepositoryProvider).deleteProvider(provider.id);
      ref.invalidate(aiProviderSetupProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Provider 已删除')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除 Provider 失败：$error')));
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
        ).showSnackBar(const SnackBar(content: Text('连接测试通过')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('连接测试失败：$error')));
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
        ).showSnackBar(SnackBar(content: Text('Provider 配置加载失败：$error')));
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

class _AIProviderSetupSurface extends StatelessWidget {
  const _AIProviderSetupSurface({
    required this.state,
    required this.testingProviderId,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  final AsyncValue<AIProviderSetupData> state;
  final String? testingProviderId;
  final ValueChanged<AIProviderSetupData> onAdd;
  final void Function(AIProviderSetupData setup, AIProviderSummary provider)
  onEdit;
  final ValueChanged<AIProviderSummary> onDelete;
  final ValueChanged<AIProviderSummary> onTest;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return state.when(
      loading: () => const PremiumSurface(
        child: ListTile(
          leading: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('正在加载 Provider 配置'),
        ),
      ),
      error: (error, stackTrace) => PremiumSurface(
        accentColor: colorScheme.error,
        child: Text('Provider 配置加载失败：$error'),
      ),
      data: (setup) {
        return PremiumSurface(
          accentColor: colorScheme.secondary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.key_outlined, color: colorScheme.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Provider 配置',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => onAdd(setup),
                    icon: const Icon(Icons.add_outlined),
                    label: const Text('添加 Provider'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '支持 DeepSeek、OpenAI 和 OpenAI-compatible 网关。API Key 保存后不会回显。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
              ),
              const SizedBox(height: 12),
              if (setup.providers.isEmpty)
                Text(
                  '暂无 Provider',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
                )
              else
                ...setup.providers.map(
                  (provider) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: colorScheme.secondary
                                      .withValues(alpha: 0.12),
                                  foregroundColor: colorScheme.secondary,
                                  child: const Icon(Icons.smart_toy_outlined),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        provider.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${provider.baseUrl} / ${provider.model}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colorScheme.outline,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _AIReportStatusChip(
                                  status: provider.enabled
                                      ? 'completed'
                                      : 'pending',
                                  label: provider.enabled ? '启用' : '停用',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  key: ValueKey(
                                    'ai-provider-edit-${provider.id}',
                                  ),
                                  onPressed: () => onEdit(setup, provider),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('编辑'),
                                ),
                                const SizedBox(width: 4),
                                OutlinedButton.icon(
                                  key: ValueKey(
                                    'ai-provider-test-${provider.id}',
                                  ),
                                  onPressed: testingProviderId == null
                                      ? () => onTest(provider)
                                      : null,
                                  icon: testingProviderId == provider.id
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.bolt_outlined),
                                  label: const Text('测试'),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  key: ValueKey(
                                    'ai-provider-delete-${provider.id}',
                                  ),
                                  onPressed: () => onDelete(provider),
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: '删除 Provider',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AIProviderEditorSheet extends StatefulWidget {
  const _AIProviderEditorSheet({required this.presets, this.provider});

  final List<AIProviderPreset> presets;
  final AIProviderSummary? provider;

  @override
  State<_AIProviderEditorSheet> createState() => _AIProviderEditorSheetState();
}

class _AIProviderEditorSheetState extends State<_AIProviderEditorSheet> {
  late AIProviderPreset _selectedPreset;
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  var _enabled = true;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _selectedPreset = provider == null
        ? widget.presets.first
        : widget.presets.firstWhere(
            (preset) => preset.providerType == provider.providerType,
            orElse: () => widget.presets.first,
          );
    _nameController = TextEditingController(
      text: provider?.name ?? _selectedPreset.name,
    );
    _baseUrlController = TextEditingController(
      text: provider?.baseUrl ?? _selectedPreset.baseUrl,
    );
    _modelController = TextEditingController(
      text: provider?.model ?? _selectedPreset.model,
    );
    _apiKeyController = TextEditingController();
    _enabled = provider?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.provider == null ? '添加 Provider' : '编辑 Provider',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedPreset.id,
                decoration: const InputDecoration(labelText: '预设'),
                items: [
                  for (final preset in widget.presets)
                    DropdownMenuItem(
                      value: preset.id,
                      child: Text(preset.name),
                    ),
                ],
                onChanged: (value) {
                  final preset = widget.presets.firstWhere(
                    (item) => item.id == value,
                    orElse: () => widget.presets.first,
                  );
                  setState(() {
                    _selectedPreset = preset;
                    _nameController.text = preset.name;
                    _baseUrlController.text = preset.baseUrl;
                    _modelController.text = preset.model;
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(labelText: 'Base URL'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(labelText: '模型'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ai-provider-api-key'),
                controller: _apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  helperText: '编辑时留空则不更换；保存后不会回显，也不会写入备份。',
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                title: const Text('启用'),
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('ai-provider-save'),
                  onPressed: _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存 Provider'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (name.isEmpty ||
        baseUrl.isEmpty ||
        model.isEmpty ||
        (widget.provider == null && apiKey.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请完整填写 Provider 信息')));
      return;
    }
    Navigator.of(context).pop(
      SaveAIProviderRequest(
        name: name,
        providerType: _selectedPreset.providerType,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        enabled: _enabled,
      ),
    );
  }
}

class _AIReportGenerateSheet extends StatefulWidget {
  const _AIReportGenerateSheet({
    required this.providers,
    required this.defaultStart,
    required this.defaultEnd,
  });

  final List<AIProviderSummary> providers;
  final String defaultStart;
  final String defaultEnd;

  @override
  State<_AIReportGenerateSheet> createState() => _AIReportGenerateSheetState();
}

class _AIReportGenerateSheetState extends State<_AIReportGenerateSheet> {
  late String _reportType;
  late String _providerId;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  var _maskNames = true;

  @override
  void initState() {
    super.initState();
    _reportType = 'weekly';
    _providerId = widget.providers.isEmpty ? '' : widget.providers.first.id;
    _startController = TextEditingController(text: widget.defaultStart);
    _endController = TextEditingController(text: widget.defaultEnd);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '生成 AI 报告',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _reportType,
                decoration: const InputDecoration(labelText: '报告类型'),
                items: const [
                  DropdownMenuItem(value: 'weekly', child: Text('每周总结')),
                  DropdownMenuItem(value: 'monthly', child: Text('月度总结')),
                  DropdownMenuItem(value: 'family', child: Text('家庭分析')),
                  DropdownMenuItem(value: 'budget', child: Text('预算建议')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _reportType = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _providerId,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('自动选择启用 Provider'),
                  ),
                  for (final provider in widget.providers)
                    DropdownMenuItem(
                      value: provider.id,
                      child: Text('${provider.name} / ${provider.model}'),
                    ),
                ],
                onChanged: (value) => setState(() => _providerId = value ?? ''),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ai-report-start-date'),
                      controller: _startController,
                      decoration: const InputDecoration(
                        labelText: '开始日期',
                        hintText: 'YYYY-MM-DD',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ai-report-end-date'),
                      controller: _endController,
                      decoration: const InputDecoration(
                        labelText: '结束日期',
                        hintText: 'YYYY-MM-DD',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _maskNames,
                title: const Text('遮蔽成员和账户名称'),
                subtitle: const Text('发送给 Provider 前替换为成员1、账户1等匿名标签。'),
                onChanged: (value) => setState(() => _maskNames = value),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('ai-report-generate-submit'),
                  onPressed: _submit,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('生成报告'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final start = _startController.text.trim();
    final end = _endController.text.trim();
    if (start.isEmpty || end.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写报告周期')));
      return;
    }
    final startDate = _parseDate(start);
    final endDate = _parseDate(end);
    if (startDate == null || endDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日期格式应为 YYYY-MM-DD')));
      return;
    }
    if (startDate.isAfter(endDate)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('开始日期不能晚于结束日期')));
      return;
    }
    Navigator.of(context).pop(
      GenerateAIReportRequest(
        reportType: _reportType,
        providerId: _providerId.isEmpty ? null : _providerId,
        periodStart: start,
        periodEnd: end,
        maskNames: _maskNames,
      ),
    );
  }

  DateTime? _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    return DateTime.tryParse(value);
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
              key: const ValueKey('ai-schedule-trigger'),
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
              '配置 OpenAI 兼容 Provider 后，可选择周期生成聚合后的财务洞察。',
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
              label: const Text('生成报告'),
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
    final snapshot = AIReportSnapshotData.parse(report.snapshotJson);
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
            if (snapshot.accountChanges.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AIReportAccountChanges(changes: snapshot.accountChanges),
            ],
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
  final prefix = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  return '$prefix¥${value.abs().toStringAsFixed(2)}';
}

Color _moneyToneColor(BuildContext context, double value) {
  if (value > 0) return AppTheme.incomeColor;
  if (value < 0) return AppTheme.expenseColor;
  return Theme.of(context).colorScheme.outline;
}
