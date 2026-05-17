import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/data_management/data/data_management_repository.dart';
import 'package:personal_ledger/features/data_management/presentation/data_management_page.dart';

void main() {
  group('DataManagementPage', () {
    testWidgets('点击下载备份时调用备份接口并展示保存路径', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

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

      expect(find.textContaining('网络失败'), findsOneWidget);
    });

    testWidgets('保存自动备份设置时提交当前设置', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('启用自动备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();

      expect(repository.saveAutoBackupCalls, hasLength(1));
      expect(repository.saveAutoBackupCalls.single.enabled, isTrue);
    });

    testWidgets('保存自动备份设置时会限制保留份数范围', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(find.byType(TextField), '200');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();

      expect(repository.saveAutoBackupCalls, hasLength(1));
      expect(repository.saveAutoBackupCalls.single.maxBackups, 100);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('立即备份会触发服务器备份并刷新文件列表', (tester) async {
      final repository = _FakeDataManagementRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('立即备份'));
      await tester.pumpAndSettle();

      expect(repository.triggerAutoBackupCalls, 1);
      expect(repository.listAutoBackupFilesCalls, greaterThanOrEqualTo(2));
      expect(find.textContaining('auto_backup_user1'), findsOneWidget);
    });

    testWidgets('立即备份失败时展示错误信息', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..triggerAutoBackupError = '磁盘空间不足';
      await _pumpPage(tester, repository);

      await tester.tap(find.text('立即备份'));
      await tester.pumpAndSettle();

      expect(repository.triggerAutoBackupCalls, 1);
      expect(find.textContaining('磁盘空间不足'), findsOneWidget);
    });

    testWidgets('自动备份加载失败后可以刷新恢复', (tester) async {
      final repository = _FakeDataManagementRepository()
        ..getAutoBackupOverviewErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.textContaining('自动备份加载失败'), findsOneWidget);

      await tester.tap(find.byTooltip('刷新自动备份'));
      await tester.pumpAndSettle();

      expect(find.textContaining('自动备份加载失败'), findsNothing);
      expect(find.textContaining('auto_backup_user1'), findsOneWidget);
      expect(repository.getAutoBackupOverviewCalls, 2);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeDataManagementRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
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
