part of 'ai_reports_page.dart';

class _AIReportsUtilityBar extends StatelessWidget {
  const _AIReportsUtilityBar({
    required this.providerState,
    required this.scheduleState,
    required this.onProviders,
    required this.onSchedule,
  });

  final AsyncValue<AIProviderSetupData> providerState;
  final AsyncValue<AIReportScheduleSettings> scheduleState;
  final VoidCallback onProviders;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final providerLabel = providerState.maybeWhen(
      data: (setup) {
        final enabledCount = setup.providers
            .where((item) => item.enabled)
            .length;
        if (setup.providers.isEmpty) {
          return '未配置';
        }
        return '$enabledCount/${setup.providers.length}';
      },
      loading: () => '加载中',
      orElse: () => '失败',
    );
    final scheduleLabel = scheduleState.maybeWhen(
      data: (settings) => settings.enabled ? '已开启' : '未开启',
      loading: () => '加载中',
      orElse: () => '失败',
    );
    return Row(
      children: [
        Expanded(
          child: _AIUtilityButton(
            icon: Icons.key_outlined,
            title: '分析方式',
            value: providerLabel,
            color: colorScheme.secondary,
            onPressed: onProviders,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AIUtilityButton(
            icon: Icons.event_repeat_outlined,
            title: '定期报告',
            value: scheduleLabel,
            color: colorScheme.primary,
            onPressed: onSchedule,
          ),
        ),
      ],
    );
  }
}

class _AIUtilityButton extends StatelessWidget {
  const _AIUtilityButton({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
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
              Icon(Icons.chevron_right, color: colorScheme.outline, size: 18),
            ],
          ),
        ),
      ),
    );
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
          title: Text('定期报告加载中'),
        ),
      ),
      error: (error, stackTrace) => PremiumSurface(
        accentColor: Theme.of(context).colorScheme.error,
        child: const Text('定期报告设置加载失败'),
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
          title: Text('分析方式加载中'),
        ),
      ),
      error: (error, stackTrace) => PremiumSurface(
        accentColor: colorScheme.error,
        child: const Text('分析方式加载失败'),
      ),
      data: (setup) {
        return PremiumSurface(
          accentColor: colorScheme.secondary,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '分析方式',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.key_outlined,
                    size: 18,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => onAdd(setup),
                    icon: const Icon(Icons.add_outlined),
                    label: const Text('添加方式'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (setup.providers.isEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.42,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.link_off_outlined,
                          size: 18,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '还没有方式',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...setup.providers.map(
                  (provider) => _AIProviderCompactRow(
                    provider: provider,
                    testing: testingProviderId == provider.id,
                    disabled: testingProviderId != null,
                    onEdit: () => onEdit(setup, provider),
                    onDelete: () => onDelete(provider),
                    onTest: () => onTest(provider),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AIProviderCompactRow extends StatefulWidget {
  const _AIProviderCompactRow({
    required this.provider,
    required this.testing,
    required this.disabled,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  final AIProviderSummary provider;
  final bool testing;
  final bool disabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  @override
  State<_AIProviderCompactRow> createState() => _AIProviderCompactRowState();
}

class _AIProviderCompactRowState extends State<_AIProviderCompactRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final testing = widget.testing;
    final disabled = widget.disabled;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    final onTest = widget.onTest;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(
                        Icons.smart_toy_outlined,
                        size: 18,
                        color: colorScheme.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                provider.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _AIReportStatusChip(
                              status: provider.enabled
                                  ? 'completed'
                                  : 'pending',
                              label: provider.enabled ? '启用' : '停用',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (testing)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      key: ValueKey('ai-provider-toggle-${provider.id}'),
                      tooltip: _expanded
                          ? '收起${provider.name}设置'
                          : '展开${provider.name}设置',
                      onPressed: disabled
                          ? null
                          : () => setState(() {
                              _expanded = !_expanded;
                            }),
                      icon: Icon(_expanded ? Icons.remove : Icons.add),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _AIProviderQuickAction(
                      key: ValueKey('ai-provider-action-test-${provider.id}'),
                      icon: Icons.health_and_safety_outlined,
                      label: '检查',
                      onPressed: disabled ? null : onTest,
                    ),
                    _AIProviderQuickAction(
                      key: ValueKey('ai-provider-action-edit-${provider.id}'),
                      icon: Icons.edit_outlined,
                      label: '编辑',
                      onPressed: disabled ? null : onEdit,
                    ),
                    _AIProviderQuickAction(
                      key: ValueKey('ai-provider-action-delete-${provider.id}'),
                      icon: Icons.delete_outline,
                      label: '删除',
                      onPressed: disabled ? null : onDelete,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AIProviderQuickAction extends StatelessWidget {
  const _AIProviderQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        foregroundColor: colorScheme.onSurface,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        side: BorderSide(color: colorScheme.outline),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
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
                widget.provider == null ? '添加方式' : '编辑方式',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedPreset.id,
                decoration: const InputDecoration(labelText: '分析方式'),
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
                decoration: const InputDecoration(labelText: '服务地址'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(labelText: '分析能力'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ai-provider-api-key'),
                controller: _apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密钥'),
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
                  label: const Text('保存方式'),
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
      ).showSnackBar(const SnackBar(content: Text('请补全方式信息')));
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
                '生成报告',
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
                decoration: const InputDecoration(labelText: '分析方式'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('默认方式')),
                  for (final provider in widget.providers)
                    DropdownMenuItem(
                      value: provider.id,
                      child: Text(provider.name),
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
                        hintText: '2026-05-01',
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
                        hintText: '2026-05-31',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _maskNames,
                title: const Text('隐藏姓名'),
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
      ).showSnackBar(const SnackBar(content: Text('请输入有效日期')));
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
    final normalizedHour = _normalizedHour(settings.hour);
    return PremiumSurface(
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '定期报告',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.event_repeat_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              _AIReportStatusChip(
                status: settings.enabled ? 'completed' : 'pending',
                label: settings.enabled ? '已开启' : '未开启',
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AIScheduleSummaryRow(
            hour: normalizedHour,
            weeklyEnabled: settings.weeklyEnabled,
            monthlyEnabled: settings.monthlyEnabled,
          ),
          const SizedBox(height: 10),
          _AIScheduleEnablePanel(
            value: settings.enabled,
            enabled: !saving,
            onChanged: (value) => onChanged(settings.copyWith(enabled: value)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: normalizedHour,
                  decoration: const InputDecoration(
                    labelText: '生成时间',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var hour = 0; hour < 24; hour++)
                      DropdownMenuItem(
                        value: hour,
                        child: Text('${hour.toString().padLeft(2, '0')}:00'),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            onChanged(settings.copyWith(hour: value));
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: settings.weeklyEnabled,
                label: const Text('每周总结'),
                onSelected: saving
                    ? null
                    : (value) =>
                          onChanged(settings.copyWith(weeklyEnabled: value)),
              ),
              const SizedBox(width: 6),
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
              label: const Text('立即生成'),
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

class _AIScheduleSummaryRow extends StatelessWidget {
  const _AIScheduleSummaryRow({
    required this.hour,
    required this.weeklyEnabled,
    required this.monthlyEnabled,
  });

  final int hour;
  final bool weeklyEnabled;
  final bool monthlyEnabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabledTypes = [
      if (weeklyEnabled) '每周总结',
      if (monthlyEnabled) '月度总结',
    ].join(' / ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _AISchedulePill(
            icon: Icons.schedule_outlined,
            label: '生成',
            value: '${hour.toString().padLeft(2, '0')}:00',
          ),
          _AISchedulePill(
            icon: Icons.privacy_tip_outlined,
            label: '报告类型',
            value: enabledTypes.isEmpty ? '未选择' : enabledTypes,
          ),
        ],
      ),
    );
  }
}

class _AISchedulePill extends StatelessWidget {
  const _AISchedulePill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: colorScheme.primary, size: 16),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _AIScheduleEnablePanel extends StatelessWidget {
  const _AIScheduleEnablePanel({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = value ? colorScheme.primary : colorScheme.outline;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onChanged(!value) : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.20)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '启用定期生成',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value ? '当前已开启' : '当前未开启',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                value
                    ? Icons.auto_awesome_motion_outlined
                    : Icons.motion_photos_paused_outlined,
                size: 18,
                color: accentColor,
              ),
              const SizedBox(width: 10),
              Semantics(
                key: const ValueKey('ai-schedule-enabled-semantics'),
                label: '启用定期生成报告',
                toggled: value,
                enabled: enabled,
                child: Switch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
