import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: AdaptivePageContainer(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _DataManagementHero(
              isBusy: _isBusy,
              autoBackupEnabled: _autoBackupSettings.enabled,
              backupCount: _autoBackupFiles.length,
              maxBackups: _autoBackupSettings.maxBackups,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _MessagePanel(
                icon: Icons.error_outline,
                message: _errorMessage!,
                isError: true,
              ),
            ],
            if (_lastSavedPath != null) ...[
              const SizedBox(height: 12),
              _MessagePanel(
                icon: Icons.folder_outlined,
                message: '文件已保存到 $_lastSavedPath',
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '数据出口',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _ActionCard(
              icon: Icons.backup_outlined,
              title: '完整备份',
              subtitle: '导出账户、分类、交易、预算、提醒、借贷、标签和个人资料。',
              buttonLabel: '下载备份',
              busy: _busyAction == 'backup',
              enabled: !_isBusy,
              onPressed: _downloadBackup,
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.table_view_outlined,
              title: '交易 CSV',
              subtitle: '导出当前全部交易明细，方便用表格软件继续分析。',
              buttonLabel: '导出 CSV',
              busy: _busyAction == 'csv',
              enabled: !_isBusy,
              onPressed: _exportTransactionsCsv,
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.restore_outlined,
              title: '恢复备份',
              subtitle: '用备份 JSON 覆盖当前账户下的数据。恢复前建议先下载一份最新备份。',
              buttonLabel: '选择备份恢复',
              busy: _busyAction == 'restore',
              enabled: !_isBusy,
              isDanger: true,
              onPressed: _pickAndRestoreBackup,
            ),
            const SizedBox(height: 12),
            _AutoBackupCard(
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

  Future<void> _pickAndRestoreBackup() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '恢复备份',
      message: '恢复会覆盖当前账户下的数据。建议先下载最新备份后再继续。',
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
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
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
          const SizedBox(height: 14),
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

class _DataManagementHero extends StatelessWidget {
  const _DataManagementHero({
    required this.isBusy,
    required this.autoBackupEnabled,
    required this.backupCount,
    required this.maxBackups,
  });

  final bool isBusy;
  final bool autoBackupEnabled;
  final int backupCount;
  final int maxBackups;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = isBusy ? colorScheme.tertiary : colorScheme.primary;
    return PremiumSurface(
      accentColor: statusColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: isBusy ? Icons.sync_outlined : Icons.shield_moon_outlined,
                color: statusColor,
                size: 50,
                iconSize: 25,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据保险库',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isBusy ? '数据操作正在执行，请不要关闭应用。' : '恢复备份会覆盖当前数据，请确认备份来源可信。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              MetricPill(
                label: '自动备份',
                value: autoBackupEnabled ? '已启用' : '未启用',
                icon: autoBackupEnabled
                    ? Icons.verified_outlined
                    : Icons.pause_circle_outline,
                color: autoBackupEnabled
                    ? colorScheme.primary
                    : colorScheme.outline,
              ),
              MetricPill(
                label: '服务器备份',
                value: '$backupCount 个',
                icon: Icons.cloud_done_outlined,
                color: colorScheme.tertiary,
              ),
              MetricPill(
                label: '保留策略',
                value: '$maxBackups 份',
                icon: Icons.inventory_2_outlined,
                color: colorScheme.secondary,
              ),
            ],
          ),
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
              Switch(value: value, onChanged: enabled ? onChanged : null),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconBadge(
            icon: Icons.description_outlined,
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
                  file.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatFileSize(file.size)} · ${file.createdAt}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
    final background = isError
        ? colorScheme.errorContainer
        : colorScheme.surfaceContainerHighest;
    final foreground = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
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
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    this.isDanger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isDanger ? colorScheme.error : colorScheme.primary;
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
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
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
        ],
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
