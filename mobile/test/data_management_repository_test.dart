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
}
