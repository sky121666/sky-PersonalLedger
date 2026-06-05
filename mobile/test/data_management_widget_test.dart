import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/data_management/data/data_management_repository.dart';
import 'package:personal_ledger/features/data_management/presentation/data_management_page.dart';

void main() {
  group('DataManagementPage', () {
    testWidgets('点击保存副本时调用备份接口并展示保存名称', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      expect(find.text('数据保险库'), findsNothing);
      expect(find.text('服务器备份'), findsNothing);
      expect(find.text('保留设置'), findsNothing);
      expect(find.text('账本副本'), findsAtLeastNWidgets(1));
      expect(find.text('完整副本'), findsNothing);
      expect(find.text('完整备份'), findsNothing);
      expect(find.text('交易明细'), findsOneWidget);
      expect(find.text('交易 CSV'), findsNothing);
      expect(find.text('保存副本'), findsOneWidget);
      expect(find.text('下载备份'), findsNothing);
      expect(find.text('保存明细'), findsOneWidget);
      expect(find.text('导出明细'), findsNothing);
      expect(find.text('导出 CSV'), findsNothing);
      expect(find.text('恢复账本'), findsOneWidget);
      expect(find.text('选择副本'), findsNothing);
      expect(
        find.byKey(const ValueKey('restore-panel-toggle')),
        findsOneWidget,
      );
      expect(find.text('选择备份'), findsNothing);
      expect(find.text('数据操作链路'), findsNothing);
      expect(find.byKey(const ValueKey('data-operation-rail')), findsNothing);
      expect(find.byKey(const ValueKey('data-recovery-matrix')), findsNothing);
      expect(find.text('灾备矩阵'), findsNothing);
      expect(
        find.byKey(const ValueKey('data-restore-evidence-rail')),
        findsNothing,
      );
      expect(find.text('恢复前建议备份'), findsNothing);
      expect(find.text('用备份 JSON 覆盖当前账户下的数据。'), findsNothing);
      expect(find.text('导出、恢复和迁移数据前先确认目标文件来源。'), findsNothing);
      await tester.tap(find.text('保存副本'));
      await tester.pumpAndSettle();

      expect(repository.downloadBackupCalls, 1);
      expect(find.textContaining('/tmp/backup.json'), findsNothing);
      expect(find.textContaining('backup.json'), findsAtLeastNWidgets(1));
    });

    testWidgets('点击保存明细时调用交易导出接口', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('保存明细'));
      await tester.pumpAndSettle();

      expect(repository.exportCsvCalls, 1);
      expect(find.textContaining('/tmp/transactions.csv'), findsNothing);
      expect(find.textContaining('transactions.csv'), findsAtLeastNWidgets(1));
    });

    testWidgets('筛选保存明细时提交日期和类型参数', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      expect(find.text('按条件保存'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('data-management-transactions-filter')),
      );
      await tester.pumpAndSettle();
      expect(find.text('筛选导出'), findsNothing);
      expect(find.text('保存明细'), findsWidgets);
      await tester.tap(find.text('支出'));
      await tester.enterText(
        find.byKey(const ValueKey('csv-export-start-date')),
        '2026-05-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('csv-export-end-date')),
        '2026-05-31',
      );
      await tester.tap(find.byKey(const ValueKey('csv-export-filter-submit')));
      await tester.pumpAndSettle();

      expect(repository.exportCsvCalls, 1);
      expect(repository.exportFilters, hasLength(1));
      expect(repository.exportFilters.single?.type, 'expense');
      expect(repository.exportFilters.single?.startDate, DateTime(2026, 5, 1));
      expect(repository.exportFilters.single?.endDate, DateTime(2026, 5, 31));
    });

    testWidgets('备份下载失败时展示错误信息', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..downloadBackupError = '网络失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.text('保存副本'));
      await tester.pumpAndSettle();

      expect(find.textContaining('网络失败'), findsAtLeastNWidgets(1));
    });

    testWidgets('保存自动保存设置时提交当前设置', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      expect(find.text('保存时间'), findsNothing);
      expect(find.text('保留副本数'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('auto-backup-settings-toggle')),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('auto-backup-settings-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('启用自动保存').last,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final backupSwitchSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('auto-backup-enabled-semantics')),
      );
      expect(backupSwitchSemantics.properties.label, '启用自动保存');
      expect(find.text('保存时间'), findsOneWidget);
      expect(find.text('备份时间'), findsNothing);
      expect(find.text('执行小时'), findsNothing);
      expect(find.text('保留副本数'), findsOneWidget);
      expect(find.text('保存份数'), findsNothing);
      expect(find.text('保留份数'), findsNothing);
      await tester.tap(find.text('启用自动保存').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存设置').last,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置').last);
      await tester.pumpAndSettle();

      expect(repository.saveAutoBackupCalls, hasLength(1));
      expect(repository.saveAutoBackupCalls.single.enabled, isTrue);
    });

    testWidgets('保存自动保存设置时会限制保留副本数范围', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('auto-backup-settings-toggle')),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('auto-backup-settings-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField).first,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '200');
      await tester.scrollUntilVisible(
        find.text('保存设置').last,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置').last);
      await tester.pumpAndSettle();

      expect(repository.saveAutoBackupCalls, hasLength(1));
      expect(repository.saveAutoBackupCalls.single.maxBackups, 100);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('立即保存会触发副本保存并刷新文件列表', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.text('立即保存').last,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即保存').last);
      await tester.pumpAndSettle();

      expect(repository.triggerAutoBackupCalls, 1);
      expect(repository.listAutoBackupFilesCalls, greaterThanOrEqualTo(2));
      expect(find.textContaining('auto_backup_user1'), findsNothing);
      expect(find.textContaining('user1_20260516'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('auto-backup-files-toggle')),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('auto-backup-files-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('user1_20260516'), findsOneWidget);
    });

    testWidgets('立即保存失败时展示错误信息', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..triggerAutoBackupError = '磁盘空间不足';
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.text('立即保存').last,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即保存').last);
      await tester.pumpAndSettle();

      expect(repository.triggerAutoBackupCalls, 1);
      expect(find.textContaining('磁盘空间不足'), findsAtLeastNWidgets(1));
    });

    testWidgets('自动保存加载失败后可以刷新恢复', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..getAutoBackupOverviewErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.textContaining('自动保存加载失败'), findsOneWidget);
      expect(find.textContaining('定期副本加载失败'), findsNothing);
      expect(find.textContaining('自动备份加载失败'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('auto-backup-reload')),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auto-backup-reload')));
      await tester.pumpAndSettle();

      expect(find.textContaining('自动备份加载失败'), findsNothing);
      expect(find.textContaining('定期副本加载失败'), findsNothing);
      expect(find.text('自动保存'), findsOneWidget);
      expect(find.text('定期副本'), findsNothing);
      expect(find.text('自动备份'), findsNothing);
      expect(find.textContaining('auto_backup_user1'), findsNothing);
      expect(find.textContaining('user1_20260516'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('auto-backup-files-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('user1_20260516'), findsOneWidget);
      expect(repository.getAutoBackupOverviewCalls, 2);
    });

    testWidgets('数据管理页使用高级表面和清晰操作层级', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository, physicalSize: const Size(1200, 4000));

      expect(find.text('账本副本'), findsAtLeastNWidgets(1));
      expect(find.text('完整副本'), findsNothing);
      expect(find.text('完整备份'), findsNothing);
      expect(find.text('交易明细'), findsOneWidget);
      expect(find.text('交易 CSV'), findsNothing);
      expect(find.text('恢复账本'), findsOneWidget);
      expect(find.text('选择副本'), findsNothing);
      expect(
        find.byKey(const ValueKey('auto-backup-orchestration-panel')),
        findsNothing,
      );
      expect(find.text('自动备份编排'), findsNothing);
      expect(find.text('风险控制'), findsNothing);
      expect(find.text('服务器留存'), findsNothing);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(4));
      expect(find.text('自动保存'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auto-backup-settings-toggle')),
        findsOneWidget,
      );
      expect(find.text('保留副本数'), findsNothing);
      expect(find.text('保存记录'), findsNothing);
      expect(find.text('记录'), findsOneWidget);
      expect(find.textContaining('user1_20260516'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('restore-panel-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('选择副本'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('auto-backup-settings-toggle')),
      );
      await tester.pumpAndSettle();

      expect(find.text('保留副本数'), findsOneWidget);
      expect(find.text('保存记录'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('auto-backup-files-toggle')));
      await tester.pumpAndSettle();

      expect(find.textContaining('user1_20260516'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeDataManagementRepository repository, {
  Size physicalSize = const Size(1200, 2200),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dataManagementRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: DataManagementPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeDataManagementRepository implements DataManagementRepository {
  int downloadBackupCalls = 0;
  int exportCsvCalls = 0;
  final exportFilters = <ExportTransactionsFilter?>[];
  int restoreBackupCalls = 0;
  int getAutoBackupOverviewCalls = 0;
  int getAutoBackupSettingsCalls = 0;
  int triggerAutoBackupCalls = 0;
  int listAutoBackupFilesCalls = 0;
  final List<AutoBackupSettings> saveAutoBackupCalls = [];
  String? downloadBackupError;
  String? triggerAutoBackupError;
  int getAutoBackupOverviewErrors = 0;
  AutoBackupSettings autoBackupSettings = const AutoBackupSettings(
    enabled: false,
    frequency: 'daily',
    hour: 3,
    maxBackups: 10,
  );
  List<AutoBackupFile> autoBackupFiles = const [
    AutoBackupFile(
      filename: 'auto_backup_user1_20260516_120000.json',
      size: 2048,
      createdAt: '2026-05-16 12:00:00',
    ),
  ];

  @override
  Future<DataFileResult> downloadBackup() async {
    downloadBackupCalls += 1;
    final error = downloadBackupError;
    if (error != null) {
      throw Exception(error);
    }
    return const DataFileResult(
      filename: 'backup.json',
      path: '/tmp/backup.json',
      size: 128,
    );
  }

  @override
  Future<DataFileResult> exportTransactionsCsv({
    ExportTransactionsFilter? filter,
  }) async {
    exportCsvCalls += 1;
    exportFilters.add(filter);
    return const DataFileResult(
      filename: 'transactions.csv',
      path: '/tmp/transactions.csv',
      size: 64,
    );
  }

  @override
  Future<void> restoreBackup(PlatformFile file) async {
    restoreBackupCalls += 1;
  }

  @override
  Future<AutoBackupOverview> getAutoBackupOverview() async {
    getAutoBackupOverviewCalls += 1;
    if (getAutoBackupOverviewErrors > 0) {
      getAutoBackupOverviewErrors -= 1;
      throw Exception('自动备份加载失败');
    }
    final settings = await getAutoBackupSettings();
    final files = await listAutoBackupFiles();
    return AutoBackupOverview(
      settings: settings ?? autoBackupSettings,
      files: files ?? const [],
    );
  }

  @override
  Future<AutoBackupSettings?> getAutoBackupSettings() async {
    getAutoBackupSettingsCalls += 1;
    return autoBackupSettings;
  }

  @override
  Future<List<AutoBackupFile>?> listAutoBackupFiles() async {
    listAutoBackupFilesCalls += 1;
    return autoBackupFiles;
  }

  @override
  Future<AutoBackupSettings?> saveAutoBackupSettings(
    AutoBackupSettings settings,
  ) async {
    saveAutoBackupCalls.add(settings);
    autoBackupSettings = settings;
    return autoBackupSettings;
  }

  @override
  Future<void> triggerAutoBackup() async {
    triggerAutoBackupCalls += 1;
    final error = triggerAutoBackupError;
    if (error != null) {
      throw Exception(error);
    }
  }
}
