import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../transactions/application/ledger_refresh.dart';
import '../data/data_management_repository.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  final _maxBackupsController = TextEditingController(text: '10');
  String? _busyAction;
  String? _lastSavedName;
  String? _errorMessage;
  AutoBackupSettings _autoBackupSettings = const AutoBackupSettings(
    enabled: false,
    frequency: 'daily',
    hour: 3,
    maxBackups: 10,
  );
  List<AutoBackupFile> _autoBackupFiles = const [];
  bool _autoBackupLoading = true;
  bool _showAutoBackupSettings = false;
  bool _showAutoBackupFiles = false;
  bool _showRecovery = false;
  bool _showTransactionImport = false;
  bool _transactionImportLoading = true;
  TransactionImportPreview? _transactionImportPreview;
  List<TransactionImportPreview> _transactionImportHistory = const [];

  bool get _isBusy => _busyAction != null;

  @override
  void initState() {
    super.initState();
    _loadAutoBackup();
    _loadRecentTransactionImport();
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
    final rows = _buildRows(colorScheme, financeColors);
    return Scaffold(
      appBar: AppBar(title: const Text('数据')),
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

  List<_DataManagementRow> _buildRows(
    ColorScheme colorScheme,
    AppFinanceColors financeColors,
  ) {
    return [
      if (_errorMessage != null)
        _DataManagementRow(
          _MessagePanel(
            icon: Icons.error_outline,
            message: _errorMessage!,
            isError: true,
          ),
          10,
        ),
      if (_lastSavedName != null)
        _DataManagementRow(
          _MessagePanel(
            icon: Icons.folder_outlined,
            message: '已保存：$_lastSavedName',
          ),
          10,
        ),
      _DataManagementRow(
        _PrimaryDataActionsCard(
          backupBusy: _busyAction == 'backup',
          csvBusy: _busyAction == 'csv',
          enabled: !_isBusy,
          backupColor: financeColors.asset,
          csvColor: financeColors.income,
          onBackup: _downloadBackup,
          onExportCsv: _exportTransactionsCsv,
          onFilterCsv: _showCsvExportSheet,
        ),
      ),
      _DataManagementRow(
        _TransactionImportPanel(
          preview: _transactionImportPreview,
          history: _transactionImportHistory,
          loading:
              _transactionImportLoading || _busyAction == 'transaction-import',
          enabled: !_isBusy,
          expanded: _showTransactionImport,
          onToggle: () {
            setState(() => _showTransactionImport = !_showTransactionImport);
          },
          onPick: _pickTransactionImport,
          onValidate: _validateTransactionImport,
          onCommit: _commitTransactionImport,
          onRollback: _rollbackTransactionImport,
          onSelect: _selectTransactionImport,
        ),
      ),
      _DataManagementRow(
        _RecoveryPanel(
          icon: Icons.restore_outlined,
          accentColor: colorScheme.error,
          title: '恢复账本',
          buttonLabel: '选择副本',
          busy: _busyAction == 'restore',
          enabled: !_isBusy,
          expanded: _showRecovery,
          onToggle: () {
            setState(() {
              _showRecovery = !_showRecovery;
            });
          },
          onPressed: _pickAndRestoreBackup,
        ),
      ),
      _DataManagementRow(
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
              _autoBackupSettings = _autoBackupSettings.copyWith(hour: value);
            });
          },
          onSave: _saveAutoBackupSettings,
          onTrigger: _triggerAutoBackup,
          onReload: _loadAutoBackup,
          showSettings: _showAutoBackupSettings,
          showFiles: _showAutoBackupFiles,
          onToggleSettings: () {
            setState(() {
              _showAutoBackupSettings = !_showAutoBackupSettings;
            });
          },
          onToggleFiles: () {
            setState(() {
              _showAutoBackupFiles = !_showAutoBackupFiles;
            });
          },
        ),
        0,
      ),
    ];
  }

  Future<void> _downloadBackup() async {
    await _runFileAction(
      action: 'backup',
      request: ref.read(dataManagementRepositoryProvider).downloadBackup,
      successMessage: (result) => '副本已保存：${result.filename}。文件未加密，请妥善保管。',
    );
  }

  Future<void> _exportTransactionsCsv() async {
    await _runFileAction(
      action: 'csv',
      request: ref.read(dataManagementRepositoryProvider).exportTransactionsCsv,
      successMessage: (result) => '明细已保存：${result.filename}',
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
      successMessage: (result) => '明细已保存：${result.filename}',
    );
  }

  Future<void> _pickAndRestoreBackup() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '恢复账本',
      message: '恢复所选副本？',
      confirmText: '恢复',
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
      _lastSavedName = null;
    });

    try {
      await ref.read(dataManagementRepositoryProvider).restoreBackup(file);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('数据已恢复')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyDataMessage(error);
      setState(() => _errorMessage = message);
      _showDataError(message);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _loadRecentTransactionImport() async {
    setState(() => _transactionImportLoading = true);
    try {
      final repository = ref.read(dataManagementRepositoryProvider);
      final history = await repository.listRecentTransactionImports();
      final preview = history.isEmpty
          ? null
          : await repository.getTransactionImport(history.first.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _transactionImportHistory = history;
        _transactionImportPreview = preview;
        if (preview != null) {
          _upsertTransactionImport(preview);
        }
        _showTransactionImport = history.isNotEmpty;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = _friendlyDataMessage(error));
    } finally {
      if (mounted) {
        setState(() => _transactionImportLoading = false);
      }
    }
  }

  Future<void> _pickTransactionImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'json'],
      allowMultiple: false,
      withData: false,
    );
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _busyAction = 'transaction-import';
      _errorMessage = null;
      _lastSavedName = null;
    });
    try {
      final preview = await ref
          .read(dataManagementRepositoryProvider)
          .previewTransactionImport(files.single);
      if (!mounted) {
        return;
      }
      setState(() => _upsertTransactionImport(preview));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('预览已生成，账本尚未发生变化')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyDataMessage(error);
      setState(() => _errorMessage = message);
      _showDataError(message);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _validateTransactionImport() async {
    final preview = _transactionImportPreview;
    if (preview == null) {
      return;
    }
    await _runTransactionImportAction(
      request: () => ref
          .read(dataManagementRepositoryProvider)
          .validateTransactionImport(preview.id),
      successMessage: '已按当前账户和分类重新检查',
    );
  }

  Future<void> _selectTransactionImport(
    TransactionImportPreview summary,
  ) async {
    setState(() {
      _busyAction = 'transaction-import';
      _errorMessage = null;
    });
    try {
      final preview = await ref
          .read(dataManagementRepositoryProvider)
          .getTransactionImport(summary.id);
      if (!mounted) {
        return;
      }
      setState(() => _upsertTransactionImport(preview));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyDataMessage(error);
      setState(() => _errorMessage = message);
      _showDataError(message);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _commitTransactionImport() async {
    final preview = _transactionImportPreview;
    if (preview == null || !preview.canCommit) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '导入 ${preview.importableRows} 条交易',
      message: '系统会一次性写入全部有效交易；24 小时内可以完整撤销。',
      confirmText: '确认导入',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runTransactionImportAction(
      request: () => ref
          .read(dataManagementRepositoryProvider)
          .commitTransactionImport(preview.id),
      successMessage: '交易已导入，24 小时内可以撤销',
      refreshLedger: true,
    );
  }

  Future<void> _rollbackTransactionImport() async {
    final preview = _transactionImportPreview;
    if (preview == null || !preview.canRollback) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '撤销本次导入',
      message: '将删除本批次创建的 ${preview.createdRows} 条交易，并原子恢复账户余额。',
      confirmText: '撤销导入',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runTransactionImportAction(
      request: () => ref
          .read(dataManagementRepositoryProvider)
          .rollbackTransactionImport(preview.id),
      successMessage: '本次导入已完整撤销',
      refreshLedger: true,
    );
  }

  Future<void> _runTransactionImportAction({
    required Future<TransactionImportPreview> Function() request,
    required String successMessage,
    bool refreshLedger = false,
  }) async {
    setState(() {
      _busyAction = 'transaction-import';
      _errorMessage = null;
    });
    try {
      final preview = await request();
      if (!mounted) {
        return;
      }
      setState(() => _upsertTransactionImport(preview));
      if (refreshLedger) {
        ref.invalidateLedgerMutationViews();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyDataMessage(error);
      setState(() => _errorMessage = message);
      _showDataError(message);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  void _upsertTransactionImport(TransactionImportPreview preview) {
    _transactionImportPreview = preview;
    _transactionImportHistory = [
      preview,
      for (final item in _transactionImportHistory)
        if (item.id != preview.id) item,
    ];
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
      setState(() => _errorMessage = _friendlyDataMessage(error));
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
      _lastSavedName = null;
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
      ).showSnackBar(const SnackBar(content: Text('自动保存设置已保存')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyDataMessage(error);
      setState(() => _errorMessage = message);
      _showDataError(message);
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
      _lastSavedName = null;
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
      ).showSnackBar(const SnackBar(content: Text('自动保存已开始')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyDataMessage(error);
      setState(() => _errorMessage = message);
      _showDataError(message);
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
      _lastSavedName = null;
    });

    try {
      final result = await request();
      if (!mounted) {
        return;
      }
      setState(() => _lastSavedName = result.filename);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage(result))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyDataMessage(error);
      setState(() => _errorMessage = message);
      _showDataError(message);
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  String _friendlyDataMessage(Object error) {
    return error
        .toString()
        .replaceAll('自动备份', '自动保存')
        .replaceAll('备份文件', '副本')
        .replaceAll('备份', '副本')
        .replaceAll('导出', '保存');
  }

  void _showDataError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DataManagementRow {
  const _DataManagementRow(this.child, [this.bottomSpacing = 12]);

  final Widget child;
  final double bottomSpacing;
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
    required this.showSettings,
    required this.showFiles,
    required this.onToggleSettings,
    required this.onToggleFiles,
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
  final bool showSettings;
  final bool showFiles;
  final VoidCallback onToggleSettings;
  final VoidCallback onToggleFiles;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = settings.enabled
        ? colorScheme.primary
        : colorScheme.outline;
    final visibleFiles = files.take(3).toList(growable: false);
    return PremiumSurface(
      accentColor: statusColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自动保存',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      settings.lastBackup == null ||
                              settings.lastBackup!.isEmpty
                          ? '还没有保存记录'
                          : '最近：${settings.lastBackup}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('auto-backup-reload'),
                onPressed: enabled && !loading ? onReload : null,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新保存记录',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('auto-backup-settings-toggle'),
                  onPressed: enabled ? onToggleSettings : null,
                  icon: Icon(showSettings ? Icons.remove : Icons.add),
                  label: Text(showSettings ? '收起设置' : '设置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled && !loading ? onTrigger : null,
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_outlined),
                  label: Text(loading ? '处理中' : '立即保存'),
                ),
              ),
            ],
          ),
          if (showSettings) ...[
            const SizedBox(height: 12),
            _SwitchPanel(
              value: settings.enabled,
              enabled: enabled && !loading,
              onChanged: onEnabledChanged,
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(settings.hour),
                    initialValue: settings.hour,
                    decoration: InputDecoration(
                      labelText: '保存时间',
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
                      labelText: '保留副本数',
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled && !loading ? onSave : null,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(loading ? '处理中' : '保存设置'),
              ),
            ),
          ],
          if (files.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('记录', style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                OutlinedButton.icon(
                  key: const ValueKey('auto-backup-files-toggle'),
                  onPressed: enabled ? onToggleFiles : null,
                  icon: Icon(showFiles ? Icons.remove : Icons.add),
                  label: Text(showFiles ? '收起' : '展开'),
                ),
              ],
            ),
            if (showFiles) ...[
              const SizedBox(height: 10),
              for (var index = 0; index < visibleFiles.length; index++) ...[
                _BackupFileRow(file: visibleFiles[index]),
                if (index != visibleFiles.length - 1) const SizedBox(height: 8),
              ],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '启用自动保存',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value ? '当前已开启' : '当前未开启',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                key: const ValueKey('auto-backup-enabled-semantics'),
                label: '启用自动保存',
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
    return Semantics(
      label: '${file.filename}，${_formatFileSize(file.size)}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _compactBackupName(file.filename),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(file.size),
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
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: foreground),
        ],
      ),
    );
  }
}

class _TransactionImportPanel extends StatelessWidget {
  const _TransactionImportPanel({
    required this.preview,
    required this.history,
    required this.loading,
    required this.enabled,
    required this.expanded,
    required this.onToggle,
    required this.onPick,
    required this.onValidate,
    required this.onCommit,
    required this.onRollback,
    required this.onSelect,
  });

  final TransactionImportPreview? preview;
  final List<TransactionImportPreview> history;
  final bool loading;
  final bool enabled;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onPick;
  final VoidCallback onValidate;
  final VoidCallback onCommit;
  final VoidCallback onRollback;
  final ValueChanged<TransactionImportPreview> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activePreview = preview;
    return PremiumSurface(
      accentColor: colorScheme.primary,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Semantics(
            button: true,
            enabled: enabled,
            label: expanded ? '收起导入交易' : '展开导入交易',
            onTap: enabled ? onToggle : null,
            child: ExcludeSemantics(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('transaction-import-toggle'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: enabled ? onToggle : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.file_upload_outlined,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '导入交易',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activePreview == null
                                      ? '先预览，再一次性写入账本'
                                      : '${_transactionImportStatusLabel(activePreview.status)} · ${activePreview.filename}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (loading)
                            const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              expanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: colorScheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (expanded) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: activePreview == null
                  ? SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('transaction-import-pick'),
                        onPressed: enabled && !loading ? onPick : null,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('选择 CSV 或 JSON'),
                      ),
                    )
                  : Column(
                      children: [
                        _TransactionImportDetails(
                          preview: activePreview,
                          loading: loading,
                          enabled: enabled,
                          onPick: onPick,
                          onValidate: onValidate,
                          onCommit: onCommit,
                          onRollback: onRollback,
                        ),
                        if (history.any(
                          (item) => item.id != activePreview.id,
                        )) ...[
                          const SizedBox(height: 12),
                          _TransactionImportHistory(
                            items: history
                                .where((item) => item.id != activePreview.id)
                                .toList(growable: false),
                            enabled: enabled && !loading,
                            onSelect: onSelect,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionImportDetails extends StatelessWidget {
  const _TransactionImportDetails({
    required this.preview,
    required this.loading,
    required this.enabled,
    required this.onPick,
    required this.onValidate,
    required this.onCommit,
    required this.onRollback,
  });

  final TransactionImportPreview preview;
  final bool loading;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onValidate;
  final VoidCallback onCommit;
  final VoidCallback onRollback;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final diagnosticRows = preview.rows
        .where((row) => row.errors.isNotEmpty || row.warnings.isNotEmpty)
        .take(3)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                preview.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _transactionImportStatusLabel(preview.status),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: preview.invalidRows > 0
                    ? colorScheme.error
                    : colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _ImportStat(label: '总计', value: preview.totalRows),
            _ImportStat(label: '有效', value: preview.validRows),
            _ImportStat(label: '错误', value: preview.invalidRows),
            _ImportStat(label: '重复', value: preview.duplicateRows),
          ],
        ),
        if (diagnosticRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final row in diagnosticRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      (row.errors.isNotEmpty
                              ? colorScheme.errorContainer
                              : colorScheme.tertiaryContainer)
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '第 ${row.row} 行 · ${(row.errors.isNotEmpty ? row.errors : row.warnings).join('；')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
        if (preview.rowsTruncated) ...[
          const SizedBox(height: 4),
          Text(
            '仅显示前 200 行预览，提交仍会处理全部记录。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (preview.canRollback)
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: const ValueKey('transaction-import-rollback'),
              onPressed: enabled && !loading ? onRollback : null,
              icon: const Icon(Icons.undo_outlined),
              label: Text('撤销已导入的 ${preview.createdRows} 条'),
            ),
          )
        else if (preview.status == 'rolled_back')
          Text(
            '本批次已撤销，账户余额已恢复。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('transaction-import-validate'),
                  onPressed: enabled && !loading ? onValidate : null,
                  child: const Text('重新检查'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('transaction-import-commit'),
                  onPressed: enabled && !loading && preview.canCommit
                      ? onCommit
                      : null,
                  child: Text('导入 ${preview.importableRows} 条'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            key: const ValueKey('transaction-import-pick-another'),
            onPressed: enabled && !loading ? onPick : null,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('选择其他文件'),
          ),
        ),
      ],
    );
  }
}

class _TransactionImportHistory extends StatelessWidget {
  const _TransactionImportHistory({
    required this.items,
    required this.enabled,
    required this.onSelect,
  });

  final List<TransactionImportPreview> items;
  final bool enabled;
  final ValueChanged<TransactionImportPreview> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '近期批次',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('transaction-import-history-${item.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? () => onSelect(item) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${_transactionImportStatusLabel(item.status)} · ${item.totalRows} 条',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ImportStat extends StatelessWidget {
  const _ImportStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _transactionImportStatusLabel(String status) {
  return switch (status) {
    'previewed' => '待确认',
    'validated' => '已检查',
    'committed' => '可撤销',
    'rolled_back' => '已撤销',
    _ => status,
  };
}

class _RecoveryPanel extends StatelessWidget {
  const _RecoveryPanel({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.buttonLabel,
    required this.busy,
    required this.enabled,
    required this.expanded,
    required this.onToggle,
    required this.onPressed,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String buttonLabel;
  final bool busy;
  final bool enabled;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: accentColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: accentColor),
              IconButton(
                key: const ValueKey('restore-panel-toggle'),
                onPressed: enabled ? onToggle : null,
                tooltip: expanded ? '收起恢复账本' : '展开恢复账本',
                icon: Icon(expanded ? Icons.remove : Icons.add),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: const ValueKey('restore-backup-button'),
                onPressed: enabled ? onPressed : null,
                icon: _ButtonIcon(busy: busy, fallback: Icons.upload_file),
                label: Text(busy ? '恢复中' : buttonLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrimaryDataActionsCard extends StatelessWidget {
  const _PrimaryDataActionsCard({
    required this.backupBusy,
    required this.csvBusy,
    required this.enabled,
    required this.backupColor,
    required this.csvColor,
    required this.onBackup,
    required this.onExportCsv,
    required this.onFilterCsv,
  });

  final bool backupBusy;
  final bool csvBusy;
  final bool enabled;
  final Color backupColor;
  final Color csvColor;
  final VoidCallback onBackup;
  final VoidCallback onExportCsv;
  final VoidCallback onFilterCsv;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: backupColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        children: [
          _DataActionLine(
            icon: Icons.backup_outlined,
            color: backupColor,
            title: '账本副本',
            buttonLabel: backupBusy ? '处理中' : '保存副本',
            busy: backupBusy,
            enabled: enabled,
            onPressed: onBackup,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          _DataActionLine(
            icon: Icons.table_view_outlined,
            color: csvColor,
            title: '交易明细',
            buttonLabel: csvBusy ? '处理中' : '保存明细',
            busy: csvBusy,
            enabled: enabled,
            onPressed: onExportCsv,
            secondaryKey: const ValueKey('data-management-transactions-filter'),
            onSecondaryPressed: onFilterCsv,
          ),
        ],
      ),
    );
  }
}

class _DataActionLine extends StatelessWidget {
  const _DataActionLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.buttonLabel,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    this.secondaryKey,
    this.onSecondaryPressed,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String buttonLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;
  final Key? secondaryKey;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        if (onSecondaryPressed != null) ...[
          IconButton(
            key: secondaryKey,
            onPressed: enabled ? onSecondaryPressed : null,
            tooltip: '筛选交易明细',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.filter_alt_outlined),
          ),
          const SizedBox(width: 4),
        ],
        FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: _ButtonIcon(busy: busy, fallback: Icons.download_outlined),
          label: Text(buttonLabel),
        ),
      ],
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
      setState(() => _errorText = '请输入有效日期');
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
              '筛选明细',
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
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('保存明细'),
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

String _compactBackupName(String filename) {
  final normalized = filename
      .replaceFirst(RegExp(r'^auto_backup_'), '')
      .replaceFirst(RegExp(r'\.json$'), '');
  return normalized.isEmpty ? filename : normalized;
}
