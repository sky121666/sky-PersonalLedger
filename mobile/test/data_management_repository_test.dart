import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:personal_ledger/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/data_management/data/data_management_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('system save', () {
    late Directory directory;
    late _SavePicker picker;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ledger-export-test-');
      picker = _SavePicker()..destination = '${directory.path}/chosen.json';
      FilePicker.platform = picker;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path,
          );
    });
    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await directory.delete(recursive: true);
    });
    test(
      'backup passes actual downloaded bytes and safe name to system save',
      () async {
        final repository = DataManagementRepository(_DownloadClient());
        await repository.downloadBackup();
        expect(picker.savedBytes, [123, 125]);
        expect(picker.savedName, 'backup.json');
      },
    );
    test(
      'desktop writes the exact bytes to the chosen filename containing percent',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        picker.destination = '${directory.path}/100%账本.json';
        final result = await DataManagementRepository(
          _DownloadClient(),
        ).downloadBackup();
        expect(await File(result.path).readAsBytes(), [123, 125]);
        expect(result.filename, '100%账本.json');
        expect(picker.savedBytes, isNull);
      },
    );
    test(
      'desktop permission or invalid destination cannot report success',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        picker.destination = directory.path;
        await expectLater(
          DataManagementRepository(_DownloadClient()).downloadBackup(),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
    test('system cancellation does not report a saved path', () async {
      picker.destination = null;
      final result = await DataManagementRepository(
        _DownloadClient(),
      ).downloadBackup();
      expect(result.path, isEmpty);
      expect(picker.savedBytes, [123, 125]);
    });
  });
  group('safeDownloadFilename', () {
    test('uses fallback for empty or directory-only names', () {
      expect(
        safeDownloadFilename(null, fallback: 'backup.json'),
        'backup.json',
      );
      expect(safeDownloadFilename('', fallback: 'backup.json'), 'backup.json');
      expect(
        safeDownloadFilename('../', fallback: 'backup.json'),
        'backup.json',
      );
    });

    test('strips path segments from response header filenames', () {
      expect(
        safeDownloadFilename('../../backup.json', fallback: 'fallback.json'),
        'backup.json',
      );
      expect(
        safeDownloadFilename(
          r'..\exports\transactions.csv',
          fallback: 'fallback.csv',
        ),
        'transactions.csv',
      );
    });

    test('rejects dot segments and null bytes', () {
      expect(
        safeDownloadFilename('..', fallback: 'backup.json'),
        'backup.json',
      );
      expect(
        safeDownloadFilename('backup\u0000.json', fallback: 'backup.json'),
        'backup.json',
      );
    });
  });

  group('TransactionImportPreview', () {
    test('parses preview counts, diagnostics and commit state', () {
      final preview = TransactionImportPreview.fromJson({
        'id': 'import-1',
        'filename': 'transactions.csv',
        'format': 'csv',
        'status': 'previewed',
        'total_rows': 3,
        'valid_rows': 2,
        'invalid_rows': 0,
        'duplicate_rows': 1,
        'created_rows': 0,
        'rolled_back_rows': 0,
        'rows_truncated': false,
        'created_at': '2026-08-01T10:00:00Z',
        'expires_at': '2026-08-01T10:30:00Z',
        'rows': [
          {
            'row': 2,
            'type': 'expense',
            'amount': 25.5,
            'transaction_date': '2026-08-01T00:00:00Z',
            'account': '现金',
            'category': '餐饮',
            'valid': true,
            'duplicate': true,
            'warnings': ['该行已经导入'],
          },
        ],
      });

      expect(preview.canCommit, isTrue);
      expect(preview.canRollback, isFalse);
      expect(preview.importableRows, 1);
      expect(preview.rows.single.warnings, ['该行已经导入']);
    });

    test('committed batch exposes rollback state', () {
      final preview = TransactionImportPreview.fromJson({
        'id': 'import-1',
        'status': 'committed',
        'total_rows': 2,
        'valid_rows': 2,
        'created_rows': 2,
        'created_at': '2026-08-01T10:00:00Z',
        'expires_at': '2026-08-02T10:00:00Z',
      });

      expect(preview.canCommit, isFalse);
      expect(preview.canRollback, isTrue);
    });
  });
}

class _DownloadClient implements ApiClient {
  @override
  Future<Response<List<int>>> getBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async => Response(
    requestOptions: RequestOptions(path: path),
    data: [123, 125],
    headers: Headers.fromMap({
      'content-disposition': ['attachment; filename="../../backup.json"'],
    }),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SavePicker extends FilePicker {
  String? destination;
  String? savedName;
  Uint8List? savedBytes;
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    return destination;
  }
}
