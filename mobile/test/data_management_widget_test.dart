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
}

class _FakeDataManagementRepository implements DataManagementRepository {
  int downloadBackupCalls = 0;
  int exportCsvCalls = 0;
  int restoreBackupCalls = 0;
  String? downloadBackupError;

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
}
