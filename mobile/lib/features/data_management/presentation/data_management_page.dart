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
      appBar: AppBar(title: const Text('数据管理')),
      body: AdaptivePageContainer(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            StaggeredEntrance(
              index: 0,
              child: _DataManagementHero(
                isBusy: _isBusy,
                autoBackupEnabled: _autoBackupSettings.enabled,
                backupCount: _autoBackupFiles.length,
                maxBackups: _autoBackupSettings.maxBackups,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 1,
              child: _DataVaultHealthPanel(
                settings: _autoBackupSettings,
                files: _autoBackupFiles,
                loading: _autoBackupLoading,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              StaggeredEntrance(
                index: 2,
                child: _MessagePanel(
                  icon: Icons.error_outline,
                  message: _errorMessage!,
                  isError: true,
                ),
              ),
            ],
            if (_lastSavedPath != null) ...[
              const SizedBox(height: 12),
              StaggeredEntrance(
                index: 2,
                child: _MessagePanel(
                  icon: Icons.folder_outlined,
                  message: '文件已保存到 $_lastSavedPath',
                ),
              ),
            ],
            const SizedBox(height: 16),
            StaggeredEntrance(
              index: 3,
              child: const _DataSectionHeader(
                icon: Icons.output_outlined,
                title: '数据出口',
                subtitle: '导出、恢复和迁移数据前先确认目标文件来源。',
              ),
            ),
            const SizedBox(height: 10),
            StaggeredEntrance(
              index: 4,
              child: _DataOperationRail(
                backupCount: _autoBackupFiles.length,
                autoBackupEnabled: _autoBackupSettings.enabled,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 5,
              child: _DataRecoveryMatrix(
                autoBackupEnabled: _autoBackupSettings.enabled,
                backupCount: _autoBackupFiles.length,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 6,
              child: _ActionCard(
                icon: Icons.backup_outlined,
                accentColor: financeColors.asset,
                title: '完整备份',
                statusLabel: 'JSON 全量',
                subtitle: '导出账户、分类、交易、预算、提醒、借贷、标签和个人资料。',
                buttonLabel: '下载备份',
                busy: _busyAction == 'backup',
                enabled: !_isBusy,
                onPressed: _downloadBackup,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 7,
              child: _ActionCard(
                icon: Icons.table_view_outlined,
                accentColor: financeColors.income,
                title: '交易 CSV',
                statusLabel: '表格分析',
                subtitle: '导出当前全部交易明细，方便用表格软件继续分析。',
                buttonLabel: '导出 CSV',
                busy: _busyAction == 'csv',
                enabled: !_isBusy,
                onPressed: _exportTransactionsCsv,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 8,
              child: _ActionCard(
                icon: Icons.restore_outlined,
                accentColor: colorScheme.error,
                title: '恢复备份',
                statusLabel: '覆盖恢复',
                subtitle: '用备份 JSON 覆盖当前账户下的数据。恢复前建议先下载一份最新备份。',
                buttonLabel: '选择备份恢复',
                busy: _busyAction == 'restore',
                enabled: !_isBusy,
                isDanger: true,
                onPressed: _pickAndRestoreBackup,
              ),
            ),
            const SizedBox(height: 12),
            StaggeredEntrance(
              index: 9,
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

class _DataOperationRail extends StatelessWidget {
  const _DataOperationRail({
    required this.backupCount,
    required this.autoBackupEnabled,
  });

  final int backupCount;
  final bool autoBackupEnabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Container(
      key: const ValueKey('data-operation-rail'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.schema_outlined,
                color: colorScheme.primary,
                size: 38,
                iconSize: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '数据操作链路',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                autoBackupEnabled ? '自动保护中' : '手动保护',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: autoBackupEnabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DataOperationNode(
                  icon: Icons.archive_outlined,
                  label: '封存',
                  value: backupCount == 0 ? '无服务器备份' : '$backupCount 个备份',
                  color: financeColors.asset,
                ),
              ),
              _DataOperationArrow(color: colorScheme.outline),
              Expanded(
                child: _DataOperationNode(
                  icon: Icons.table_chart_outlined,
                  label: '分析',
                  value: 'CSV 明细',
                  color: financeColors.income,
                ),
              ),
              _DataOperationArrow(color: colorScheme.outline),
              Expanded(
                child: _DataOperationNode(
                  icon: Icons.restore_page_outlined,
                  label: '恢复',
                  value: '覆盖确认',
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataRecoveryMatrix extends StatelessWidget {
  const _DataRecoveryMatrix({
    required this.autoBackupEnabled,
    required this.backupCount,
  });

  final bool autoBackupEnabled;
  final int backupCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final protectionColor = autoBackupEnabled && backupCount > 0
        ? financeColors.income
        : financeColors.warning;
    return PremiumSurface(
      key: const ValueKey('data-recovery-matrix'),
      accentColor: protectionColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.grid_view_rounded,
                color: protectionColor,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '灾备矩阵',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '把导出、分析、恢复拆成可判断的安全路径',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _DataMatrixPill(
                label: autoBackupEnabled ? '自动链路' : '手动链路',
                color: protectionColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final threeColumn = constraints.maxWidth >= 560;
              final twoColumn = constraints.maxWidth >= 380;
              final gap = threeColumn ? 10.0 : 8.0;
              final width = threeColumn
                  ? (constraints.maxWidth - gap * 2) / 3
                  : twoColumn
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              final tiles = [
                _DataRecoveryMatrixTileData(
                  icon: Icons.data_object_outlined,
                  title: '完整备份',
                  value: backupCount == 0 ? '待生成' : '$backupCount 份',
                  caption: 'JSON 可恢复',
                  color: financeColors.asset,
                ),
                _DataRecoveryMatrixTileData(
                  icon: Icons.query_stats_outlined,
                  title: '交易分析',
                  value: 'CSV',
                  caption: '表格复盘',
                  color: financeColors.income,
                ),
                _DataRecoveryMatrixTileData(
                  icon: Icons.gpp_maybe_outlined,
                  title: '恢复闸门',
                  value: '二次确认',
                  caption: '覆盖前阻断',
                  color: colorScheme.error,
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width: width,
                      child: _DataRecoveryMatrixTile(data: tile),
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

class _DataRecoveryMatrixTileData {
  const _DataRecoveryMatrixTileData({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;
}

class _DataRecoveryMatrixTile extends StatelessWidget {
  const _DataRecoveryMatrixTile({required this.data});

  final _DataRecoveryMatrixTileData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          data.color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(data.icon, color: data.color, size: 19),
              const Spacer(),
              Icon(
                Icons.arrow_outward_rounded,
                color: data.color.withValues(alpha: 0.78),
                size: 17,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _DataMatrixPill(label: data.caption, color: data.color),
        ],
      ),
    );
  }
}

class _DataMatrixPill extends StatelessWidget {
  const _DataMatrixPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DataVaultHealthPanel extends StatelessWidget {
  const _DataVaultHealthPanel({
    required this.settings,
    required this.files,
    required this.loading,
  });

  final AutoBackupSettings settings;
  final List<AutoBackupFile> files;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final latestFile = files.isEmpty ? null : files.first;
    final retentionRatio = settings.maxBackups <= 0
        ? 0.0
        : (files.length / settings.maxBackups).clamp(0.0, 1.0).toDouble();
    final healthColor = loading
        ? colorScheme.secondary
        : settings.enabled && files.isNotEmpty
        ? financeColors.income
        : financeColors.warning;
    return PremiumSurface(
      key: const ValueKey('data-vault-health-panel'),
      accentColor: healthColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.health_and_safety_outlined,
                color: healthColor,
                size: 42,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '保险库健康层',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loading
                          ? '正在同步服务器备份状态'
                          : latestFile == null
                          ? '建议开启自动备份并生成第一份服务器备份'
                          : '最近备份：${latestFile.createdAt}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _DataVaultHealthPill(
                label: settings.enabled ? '自动保护' : '手动保护',
                icon: settings.enabled
                    ? Icons.verified_outlined
                    : Icons.pan_tool_alt_outlined,
                color: settings.enabled
                    ? financeColors.income
                    : colorScheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DataVaultHealthPill(
                label: '服务器备份',
                icon: Icons.cloud_done_outlined,
                color: files.isEmpty
                    ? colorScheme.outline
                    : financeColors.asset,
              ),
              _DataVaultHealthPill(
                label: '${files.length} 个',
                icon: latestFile == null
                    ? Icons.pending_actions_outlined
                    : Icons.cloud_done_outlined,
                color: files.isEmpty
                    ? colorScheme.outline
                    : financeColors.asset,
              ),
              _DataVaultHealthPill(
                label: '留存水位',
                icon: Icons.inventory_2_outlined,
                color: retentionRatio >= 0.9
                    ? financeColors.warning
                    : financeColors.income,
              ),
              _DataVaultHealthPill(
                label: '${(retentionRatio * 100).round()}%',
                icon: Icons.speed_outlined,
                color: retentionRatio >= 0.9
                    ? financeColors.warning
                    : financeColors.income,
              ),
              _DataVaultHealthPill(
                label: 'JSON 全量',
                icon: Icons.data_object_outlined,
                color: financeColors.asset,
              ),
              _DataVaultHealthPill(
                label: 'CSV 分析',
                icon: Icons.table_chart_outlined,
                color: financeColors.income,
              ),
              _DataVaultHealthPill(
                label: '恢复二次确认',
                icon: Icons.verified_user_outlined,
                color: colorScheme.error,
              ),
              _DataVaultHealthPill(
                label: '本机保存',
                icon: Icons.devices_outlined,
                color: colorScheme.tertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataVaultHealthPill extends StatelessWidget {
  const _DataVaultHealthPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 32, maxWidth: 156),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataOperationNode extends StatelessWidget {
  const _DataOperationNode({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.18
                    : 0.1,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _DataOperationArrow extends StatelessWidget {
  const _DataOperationArrow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Icon(Icons.chevron_right_rounded, color: color, size: 22),
    );
  }
}

class _DataSectionHeader extends StatelessWidget {
  const _DataSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

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
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
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
          const SizedBox(height: 14),
          _AutoBackupOrchestrationPanel(settings: settings, files: files),
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

class _AutoBackupOrchestrationPanel extends StatelessWidget {
  const _AutoBackupOrchestrationPanel({
    required this.settings,
    required this.files,
  });

  final AutoBackupSettings settings;
  final List<AutoBackupFile> files;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final retentionRatio = settings.maxBackups <= 0
        ? 0.0
        : (files.length / settings.maxBackups).clamp(0.0, 1.0).toDouble();
    final accent = settings.enabled ? financeColors.asset : colorScheme.outline;
    return AnimatedContainer(
      key: const ValueKey('auto-backup-orchestration-panel'),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.075,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '自动备份编排',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _AutoBackupStatusPill(
                label: settings.enabled ? '计划运行' : '待启用',
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AutoBackupOrchestrationTile(
                  icon: Icons.event_repeat_outlined,
                  label: '频率',
                  value: _frequencyLabel(settings.frequency),
                  color: financeColors.asset,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AutoBackupOrchestrationTile(
                  icon: Icons.access_time_filled_outlined,
                  label: '执行',
                  value: '${settings.hour.toString().padLeft(2, '0')}:00',
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AutoBackupOrchestrationTile(
                  icon: Icons.inventory_2_outlined,
                  label: '留存',
                  value: '${files.length}/${settings.maxBackups}',
                  color: retentionRatio >= 0.9
                      ? financeColors.warning
                      : financeColors.income,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: retentionRatio,
              color: retentionRatio >= 0.9
                  ? financeColors.warning
                  : financeColors.income,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }

  String _frequencyLabel(String frequency) {
    return switch (frequency) {
      'weekly' => '每周',
      'monthly' => '每月',
      _ => '每天',
    };
  }
}

class _AutoBackupOrchestrationTile extends StatelessWidget {
  const _AutoBackupOrchestrationTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoBackupStatusPill extends StatelessWidget {
  const _AutoBackupStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
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
          const SizedBox(height: 16),
          _DataTrustRail(
            autoBackupEnabled: autoBackupEnabled,
            maxBackups: maxBackups,
          ),
        ],
      ),
    );
  }
}

class _DataTrustRail extends StatelessWidget {
  const _DataTrustRail({
    required this.autoBackupEnabled,
    required this.maxBackups,
  });

  final bool autoBackupEnabled;
  final int maxBackups;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        Expanded(
          child: _DataTrustTile(
            icon: Icons.download_done_outlined,
            label: '传输路径',
            value: '本机保存',
            color: financeColors.asset,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DataTrustTile(
            icon: Icons.verified_user_outlined,
            label: '覆盖确认',
            value: '二次确认',
            color: colorScheme.error,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DataTrustTile(
            icon: autoBackupEnabled
                ? Icons.cloud_sync_outlined
                : Icons.cloud_off_outlined,
            label: '备份留存',
            value: autoBackupEnabled ? '$maxBackups 份' : '待启用',
            color: autoBackupEnabled
                ? colorScheme.primary
                : colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _DataTrustTile extends StatelessWidget {
  const _DataTrustTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _BackupFileSignal(
                        icon: Icons.storage_outlined,
                        label: _formatFileSize(file.size),
                        color: financeColors.asset,
                      ),
                      _BackupFileSignal(
                        icon: Icons.schedule_outlined,
                        label: file.createdAt,
                        color: colorScheme.tertiary,
                      ),
                      _BackupFileSignal(
                        icon: Icons.verified_outlined,
                        label: '服务器留存',
                        color: financeColors.income,
                      ),
                    ],
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

class _BackupFileSignal extends StatelessWidget {
  const _BackupFileSignal({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 176),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.15
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCardSignal extends StatelessWidget {
  const _ActionCardSignal({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            color.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.15
                  : 0.08,
            ),
            colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 1),
            Text(
              label,
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
    );
  }
}

class _ActionControlStrip extends StatelessWidget {
  const _ActionControlStrip({required this.color, required this.isDanger});

  final Color color;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        _ActionCardSignal(
          icon: isDanger
              ? Icons.warning_amber_outlined
              : Icons.verified_user_outlined,
          label: '风险控制',
          value: isDanger ? '覆盖确认' : '安全导出',
          color: isDanger ? colorScheme.error : financeColors.income,
        ),
        const SizedBox(width: 8),
        _ActionCardSignal(
          icon: isDanger ? Icons.upload_file_outlined : Icons.download_outlined,
          label: '操作路径',
          value: isDanger ? '本机选择' : '本机保存',
          color: color,
        ),
        const SizedBox(width: 8),
        _ActionCardSignal(
          icon: isDanger ? Icons.restore_page_outlined : Icons.bolt_outlined,
          label: '执行方式',
          value: isDanger ? '恢复' : '即时',
          color: isDanger ? colorScheme.error : colorScheme.tertiary,
        ),
      ],
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
    required this.statusLabel,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    this.isDanger = false,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String statusLabel;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;
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
                    const SizedBox(height: 7),
                    _ActionStatusPill(label: statusLabel, color: iconColor),
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
          const SizedBox(height: 14),
          _ActionControlStrip(color: iconColor, isDanger: isDanger),
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

class _ActionStatusPill extends StatelessWidget {
  const _ActionStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
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
