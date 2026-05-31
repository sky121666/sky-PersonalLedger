import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/data_management/data/data_management_repository.dart';
import 'package:personal_ledger/features/data_management/presentation/data_management_page.dart';

void main() {
  group('DataManagementPage', () {
    testWidgets('点击下载备份时调用备份接口并展示保存路径', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      expect(find.text('数据保险库'), findsOneWidget);
      expect(find.text('传输路径'), findsOneWidget);
      expect(find.text('覆盖确认'), findsWidgets);
      expect(find.text('备份留存'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('data-vault-health-panel')),
        findsOneWidget,
      );
      expect(find.text('保险库健康层'), findsOneWidget);
      expect(find.text('手动保护'), findsWidgets);
      expect(find.text('服务器备份'), findsWidgets);
      expect(find.text('留存水位'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);
      expect(find.text('JSON 全量'), findsAtLeastNWidgets(1));
      expect(find.text('CSV 分析'), findsOneWidget);
      expect(find.text('恢复二次确认'), findsOneWidget);
      expect(find.text('本机保存'), findsAtLeastNWidgets(1));
      expect(find.text('数据操作链路'), findsOneWidget);
      expect(find.text('手动保护'), findsWidgets);
      expect(find.text('1 个备份'), findsOneWidget);
      expect(find.text('CSV 明细'), findsOneWidget);
      expect(find.byKey(const ValueKey('data-operation-rail')), findsOneWidget);
      expect(find.text('导出、恢复和迁移数据前先确认目标文件来源。'), findsOneWidget);
      await tester.tap(find.text('下载备份'));
      await tester.pumpAndSettle();

      expect(repository.downloadBackupCalls, 1);
      expect(find.textContaining('/tmp/backup.json'), findsOneWidget);
    });

    testWidgets('点击导出 CSV 时调用交易导出接口', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('导出 CSV'));
      await tester.pumpAndSettle();

      expect(repository.exportCsvCalls, 1);
      expect(find.textContaining('/tmp/transactions.csv'), findsOneWidget);
    });

    testWidgets('备份下载失败时展示错误信息', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..downloadBackupError = '网络失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.text('下载备份'));
      await tester.pumpAndSettle();

      expect(find.textContaining('网络失败'), findsAtLeastNWidgets(1));
    });

    testWidgets('保存自动备份设置时提交当前设置', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.text('启用自动备份').last,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('启用自动备份').last);
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

    testWidgets('保存自动备份设置时会限制保留份数范围', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

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

    testWidgets('立即备份会触发服务器备份并刷新文件列表', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.text('立即备份').last,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即备份').last);
      await tester.pumpAndSettle();

      expect(repository.triggerAutoBackupCalls, 1);
      expect(repository.listAutoBackupFilesCalls, greaterThanOrEqualTo(2));
      expect(find.textContaining('auto_backup_user1'), findsOneWidget);
    });

    testWidgets('立即备份失败时展示错误信息', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..triggerAutoBackupError = '磁盘空间不足';
      await _pumpPage(tester, repository);

      await tester.scrollUntilVisible(
        find.text('立即备份').last,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即备份').last);
      await tester.pumpAndSettle();

      expect(repository.triggerAutoBackupCalls, 1);
      expect(find.textContaining('磁盘空间不足'), findsOneWidget);
    });

    testWidgets('自动备份加载失败后可以刷新恢复', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..getAutoBackupOverviewErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.textContaining('自动备份加载失败'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byTooltip('刷新自动备份'),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刷新自动备份'));
      await tester.pumpAndSettle();

      expect(find.textContaining('自动备份加载失败'), findsNothing);
      expect(find.textContaining('auto_backup_user1'), findsOneWidget);
      expect(repository.getAutoBackupOverviewCalls, 2);
    });

    testWidgets('数据管理页使用高级表面和分段入场动效', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository, physicalSize: const Size(1200, 4000));

      expect(find.text('JSON 全量'), findsAtLeastNWidgets(1));
      expect(find.text('表格分析'), findsOneWidget);
      expect(find.text('覆盖恢复'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auto-backup-orchestration-panel')),
        findsOneWidget,
      );
      expect(find.text('自动备份编排'), findsOneWidget);
      expect(find.text('待启用'), findsAtLeastNWidgets(1));
      expect(find.text('频率'), findsOneWidget);
      expect(find.text('执行'), findsOneWidget);
      expect(find.text('留存'), findsOneWidget);
      expect(find.text('1/10'), findsOneWidget);
      expect(find.text('风险控制'), findsAtLeastNWidgets(1));
      expect(find.text('安全导出'), findsAtLeastNWidgets(1));
      expect(find.text('服务器留存'), findsOneWidget);
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(5));
      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(7));
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeDataManagementRepository repository, {
  Size physicalSize = const Size(1200, 1600),
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
  Future<DataFileResult> exportTransactionsCsv() async {
    exportCsvCalls += 1;
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
