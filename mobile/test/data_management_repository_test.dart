import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/data_management/data/data_management_repository.dart';

void main() {
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
