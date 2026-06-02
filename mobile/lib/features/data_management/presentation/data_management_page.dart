import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../data/data_management_repository.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  final _maxBackupsController = TextEditingController(text: '10');
  String? _busyAction;
  String? _lastSavedPath;
  String? _errorMessage;
  AutoBackupSettings _autoBackupSettings = const AutoBackupSettings(
    enabled: false,
    frequency: 'daily',
    hour: 3,
    maxBackups: 10,
  );
  List<AutoBackupFile> _autoBackupFiles = const [];
  bool _autoBackupLoading = true;

  bool get _isBusy => _busyAction != null;

  @override
  void initState() {
    super.initState();
    _loadAutoBackup();
  }

  @override
  void dispose() {
    _maxBackupsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Scaffold(
      appBar: AppBar(title: const Text('数据')),
      body: AdaptivePageContainer(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (_errorMessage != null) ...[
              StaggeredEntrance(
                index: 0,
                child: _MessagePanel(
                  icon: Icons.error_outline,
                  message: _errorMessage!,
                  isError: true,
                ),
              ),
            ],
            if (_lastSavedPath != null) ...[
              StaggeredEntrance(
                index: 0,
                child: _MessagePanel(
                  icon: Icons.folder_outlined,
                  message: '文件已保存到 $_lastSavedPath',
                ),
              ),
            ],
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 1,
              child: const _DataSectionHeader(
                icon: Icons.output_outlined,
                title: '数据',
              ),
            ),
            const SizedBox(height: 10),
            StaggeredEntrance(
              index: 2,
              child: _ActionCard(
                icon: Icons.backup_outlined,
                accentColor: financeColors.asset,
                title: '完整备份',
                buttonLabel: '下载备份',
                busy: _busyAction == 'backup',
                enabled: !_isBusy,
                onPressed: _downloadBackup,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 3,
              child: _ActionCard(
                icon: Icons.table_view_outlined,
                accentColor: financeColors.income,
                title: '交易 CSV',
                buttonLabel: '导出 CSV',
                secondaryLabel: '筛选导出',
                busy: _busyAction == 'csv',
                enabled: !_isBusy,
                onPressed: _exportTransactionsCsv,
                onSecondaryPressed: _showCsvExportSheet,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 4,
              child: _ActionCard(
                icon: Icons.restore_outlined,
                accentColor: colorScheme.error,
                title: '恢复数据',
                buttonLabel: '选择备份',
                busy: _busyAction == 'restore',
                enabled: !_isBusy,
                isDanger: true,
                onPressed: _pickAndRestoreBackup,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 5,
              child: _AutoBackupCard(
                settings: _autoBackupSettings,
                files: _autoBackupFiles,
                maxBackupsController: _maxBackupsController,
                loading: _autoBackupLoading || _busyAction == 'auto-backup',
                enabled: !_isBusy,
                onEnabledChanged: (value) {
                  setState(() {
                    _autoBackupSettings = _autoBackupSettings.copyWith(
                      enabled: value,
                    );
                  });
                },
                onFrequencyChanged: (value) {
                  setState(() {
                    _autoBackupSettings = _autoBackupSettings.copyWith(
                      frequency: value,
                    );
                  });
                },
                onHourChanged: (value) {
                  setState(() {
                    _autoBackupSettings = _autoBackupSettings.copyWith(
                      hour: value,
                    );
                  });
                },
                onSave: _saveAutoBackupSettings,
                onTrigger: _triggerAutoBackup,
                onReload: _loadAutoBackup,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadBackup() async {
    await _runFileAction(
      action: 'backup',
      request: ref.read(dataManagementRepositoryProvider).downloadBackup,
      successMessage: (result) => '备份已保存：${result.filename}',
    );
  }

  Future<void> _exportTransactionsCsv() async {
    await _runFileAction(
      action: 'csv',
      request: ref.read(dataManagementRepositoryProvider).exportTransactionsCsv,
      successMessage: (result) => 'CSV 已保存：${result.filename}',
    );
  }

  Future<void> _showCsvExportSheet() async {
    final filter = await showModalBottomSheet<ExportTransactionsFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _CsvExportFilterSheet(),
    );
    if (filter == null || !mounted) {
      return;
    }
    await _runFileAction(
      action: 'csv',
      request: () => ref
          .read(dataManagementRepositoryProvider)
          .exportTransactionsCsv(filter: filter),
      successMessage: (result) => 'CSV 已保存：${result.filename}',
    );
  }

  Future<void> _pickAndRestoreBackup() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '恢复数据',
      message: '将用所选备份覆盖当前账户数据。',
      confirmText: '继续恢复',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: false,
    );
    final files = result?.files ?? const <PlatformFile>[];
    final file = files.isEmpty ? null : files.single;
    if (file == null) {
      return;
    }

    setState(() {
      _busyAction = 'restore';
      _errorMessage = null;
      _lastSavedPath = null;
    });

    try {
      await ref.read(dataManagementRepositoryProvider).restoreBackup(file);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('备份恢复完成')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
      _showDataError(error);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _loadAutoBackup() async {
    setState(() {
      _autoBackupLoading = true;
      _errorMessage = null;
    });

    try {
      final overview = await ref
          .read(dataManagementRepositoryProvider)
          .getAutoBackupOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _autoBackupSettings = overview.settings;
        _autoBackupFiles = overview.files;
        _maxBackupsController.text = overview.settings.maxBackups.toString();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _autoBackupLoading = false);
      }
    }
  }

  Future<void> _saveAutoBackupSettings() async {
    final maxBackups =
        int.tryParse(_maxBackupsController.text.trim()) ??
        _autoBackupSettings.maxBackups;
    final settings = _autoBackupSettings.copyWith(
      maxBackups: maxBackups.clamp(1, 100),
    );

    setState(() {
      _busyAction = 'auto-backup';
      _errorMessage = null;
      _lastSavedPath = null;
      _autoBackupSettings = settings;
      _maxBackupsController.text = settings.maxBackups.toString();
    });

    try {
      final saved = await ref
          .read(dataManagementRepositoryProvider)
          .saveAutoBackupSettings(settings);
      if (!mounted) {
        return;
      }
      setState(() {
        _autoBackupSettings = saved ?? settings;
        _maxBackupsController.text = _autoBackupSettings.maxBackups.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('自动备份设置已保存')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
      _showDataError(error);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _triggerAutoBackup() async {
    setState(() {
      _busyAction = 'auto-backup';
      _errorMessage = null;
      _lastSavedPath = null;
    });

    try {
      final repository = ref.read(dataManagementRepositoryProvider);
      await repository.triggerAutoBackup();
      final files = await repository.listAutoBackupFiles();
      if (!mounted) {
        return;
      }
      setState(() => _autoBackupFiles = files ?? const []);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('自动备份已触发')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
      _showDataError(error);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _runFileAction({
    required String action,
    required Future<DataFileResult> Function() request,
    required String Function(DataFileResult result) successMessage,
  }) async {
    setState(() {
      _busyAction = action;
      _errorMessage = null;
      _lastSavedPath = null;
    });

    try {
      final result = await request();
      if (!mounted) {
        return;
      }
      setState(() => _lastSavedPath = result.path);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage(result))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
      _showDataError(error);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  void _showDataError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class _DataSectionHeader extends StatelessWidget {
  const _DataSectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconBadge(
          icon: icon,
          color: colorScheme.primary,
          size: 36,
          iconSize: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AutoBackupCard extends StatelessWidget {
  const _AutoBackupCard({
    required this.settings,
    required this.files,
    required this.maxBackupsController,
    required this.loading,
    required this.enabled,
    required this.onEnabledChanged,
    required this.onFrequencyChanged,
    required this.onHourChanged,
    required this.onSave,
    required this.onTrigger,
    required this.onReload,
  });

  final AutoBackupSettings settings;
  final List<AutoBackupFile> files;
  final TextEditingController maxBackupsController;
  final bool loading;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onFrequencyChanged;
  final ValueChanged<int> onHourChanged;
  final VoidCallback onSave;
  final VoidCallback onTrigger;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = settings.enabled
        ? colorScheme.primary
        : colorScheme.outline;
    return PremiumSurface(
      accentColor: statusColor,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.schedule_outlined,
                color: statusColor,
                size: 46,
                iconSize: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自动备份',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      settings.lastBackup == null ||
                              settings.lastBackup!.isEmpty
                          ? '定时在服务器生成备份文件'
                          : '上次备份：${settings.lastBackup}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: enabled && !loading ? onReload : null,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新自动备份',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SwitchPanel(
            value: settings.enabled,
            enabled: enabled && !loading,
            onChanged: onEnabledChanged,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'daily',
                  label: Text('每天'),
                  icon: Icon(Icons.today_outlined),
                ),
                ButtonSegment(
                  value: 'weekly',
                  label: Text('每周'),
                  icon: Icon(Icons.view_week_outlined),
                ),
                ButtonSegment(
                  value: 'monthly',
                  label: Text('每月'),
                  icon: Icon(Icons.calendar_month_outlined),
                ),
              ],
              selected: {settings.frequency},
              showSelectedIcon: false,
              onSelectionChanged: enabled && !loading
                  ? (values) => onFrequencyChanged(values.first)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey(settings.hour),
                  initialValue: settings.hour,
                  decoration: InputDecoration(
                    labelText: '执行小时',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.access_time_outlined,
                      color: colorScheme.primary,
                    ),
                  ),
                  items: [
                    for (var hour = 0; hour < 24; hour++)
                      DropdownMenuItem(
                        value: hour,
                        child: Text('${hour.toString().padLeft(2, '0')}:00'),
                      ),
                  ],
                  onChanged: enabled && !loading && settings.enabled
                      ? (value) {
                          if (value != null) {
                            onHourChanged(value);
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: maxBackupsController,
                  enabled: enabled && !loading,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '保留份数',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.inventory_2_outlined,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled && !loading ? onSave : null,
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(loading ? '处理中...' : '保存设置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled && !loading ? onTrigger : null,
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('立即备份'),
                ),
              ),
            ],
          ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '已有备份',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${files.length} 个文件',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final file in files.take(3)) ...[
              _BackupFileRow(file: file),
              if (file != files.take(3).last) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _SwitchPanel extends StatelessWidget {
  const _SwitchPanel({
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onChanged(!value) : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              IconBadge(
                icon: Icons.auto_awesome_motion_outlined,
                color: value ? colorScheme.primary : colorScheme.outline,
                size: 38,
                iconSize: 19,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '启用自动备份',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '按设定频率保留服务器端备份',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                key: const ValueKey('auto-backup-enabled-semantics'),
                label: '启用自动备份',
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

class _BackupFileRow extends StatelessWidget {
  const _BackupFileRow({required this.file});

  final AutoBackupFile file;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Semantics(
      label:
          '${file.filename}，${_formatFileSize(file.size)}，创建于 ${file.createdAt}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            financeColors.asset.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.13
                  : 0.06,
            ),
            colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: financeColors.asset.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            IconBadge(
              icon: Icons.description_outlined,
              color: financeColors.asset,
              size: 38,
              iconSize: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatFileSize(file.size)} · ${file.createdAt}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = isError ? colorScheme.error : colorScheme.primary;
    return PremiumSurface(
      accentColor: foreground,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon: icon, color: foreground, size: 38, iconSize: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.buttonLabel,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.isDanger = false,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String buttonLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isDanger ? colorScheme.error : accentColor;
    return PremiumSurface(
      accentColor: iconColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, color: iconColor, size: 46, iconSize: 23),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: isDanger
                ? FilledButton.tonalIcon(
                    onPressed: enabled ? onPressed : null,
                    icon: _ButtonIcon(busy: busy, fallback: Icons.upload_file),
                    label: Text(busy ? '恢复中...' : buttonLabel),
                  )
                : FilledButton.icon(
                    onPressed: enabled ? onPressed : null,
                    icon: _ButtonIcon(
                      busy: busy,
                      fallback: Icons.download_outlined,
                    ),
                    label: Text(busy ? '处理中...' : buttonLabel),
                  ),
          ),
          if (secondaryLabel != null && onSecondaryPressed != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: enabled ? onSecondaryPressed : null,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(secondaryLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CsvExportFilterSheet extends StatefulWidget {
  const _CsvExportFilterSheet();

  @override
  State<_CsvExportFilterSheet> createState() => _CsvExportFilterSheetState();
}

class _CsvExportFilterSheetState extends State<_CsvExportFilterSheet> {
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  String _type = '';
  String? _errorText;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _submit() {
    DateTime? parseDate(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      return DateTime.tryParse(trimmed);
    }

    final start = parseDate(_startController.text);
    final end = parseDate(_endController.text);
    if (_startController.text.trim().isNotEmpty && start == null ||
        _endController.text.trim().isNotEmpty && end == null) {
      setState(() => _errorText = '日期格式应为 YYYY-MM-DD');
      return;
    }
    if (start != null && end != null && start.isAfter(end)) {
      setState(() => _errorText = '开始日期不能晚于结束日期');
      return;
    }
    Navigator.of(context).pop(
      ExportTransactionsFilter(
        startDate: start,
        endDate: end,
        type: _type.isEmpty ? null : _type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '筛选导出',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '', label: Text('全部')),
                ButtonSegment(value: 'expense', label: Text('支出')),
                ButtonSegment(value: 'income', label: Text('收入')),
                ButtonSegment(value: 'transfer', label: Text('转账')),
              ],
              selected: {_type},
              onSelectionChanged: (values) =>
                  setState(() => _type = values.first),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('csv-export-start-date'),
              controller: _startController,
              decoration: const InputDecoration(
                labelText: '开始日期',
                hintText: '2026-05-01',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('csv-export-end-date'),
              controller: _endController,
              decoration: InputDecoration(
                labelText: '结束日期',
                hintText: '2026-05-31',
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('csv-export-filter-submit'),
                onPressed: _submit,
                icon: const Icon(Icons.download_outlined),
                label: const Text('导出'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonIcon extends StatelessWidget {
  const _ButtonIcon({required this.busy, required this.fallback});

  final bool busy;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    if (!busy) {
      return Icon(fallback);
    }
    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

String _formatFileSize(int size) {
  if (size >= 1024 * 1024) {
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (size >= 1024) {
    return '${(size / 1024).toStringAsFixed(1)} KB';
  }
  return '$size B';
}
