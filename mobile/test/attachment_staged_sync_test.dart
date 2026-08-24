import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/attachments/data/attachment_after_save_exception.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/attachments/data/attachment_repository.dart';
import 'package:personal_ledger/features/attachments/data/attachment_staged_sync.dart';

void main() {
  test(
    'partial upload persists successes and retries only failed files',
    () async {
      final repository = _FakeAttachmentRepository()..failOnceFor.add('b.pdf');
      final persisted = <List<String>>[];

      final error = await _captureAttachmentError(
        () => syncPendingAttachments(
          repository: repository,
          category: 'lendings',
          refId: 'lend-1',
          retainedAttachments: const [],
          pendingFiles: const [
            PendingAttachmentFile(path: '/tmp/a.pdf', name: 'a.pdf'),
            PendingAttachmentFile(path: '/tmp/b.pdf', name: 'b.pdf'),
          ],
          persistAttachments: (attachments) async {
            persisted.add(attachments.map((item) => item.path).toList());
          },
          failureMessage: '附件未完成',
        ),
      );

      expect(persisted, [
        ['lendings/lend-1/a.pdf'],
      ]);
      expect(repository.uploadNames, ['a.pdf', 'b.pdf']);

      await error.retry!();

      expect(repository.uploadNames, ['a.pdf', 'b.pdf', 'b.pdf']);
      expect(persisted.last, [
        'lendings/lend-1/a.pdf',
        'lendings/lend-1/b.pdf',
      ]);
    },
  );

  test(
    'metadata failure keeps confirmed upload and retries only metadata',
    () async {
      final repository = _FakeAttachmentRepository();
      var persistFailures = 1;
      final persisted = <List<String>>[];

      final error = await _captureAttachmentError(
        () => syncPendingAttachments(
          repository: repository,
          category: 'reminders',
          refId: 'reminder-1',
          retainedAttachments: const [],
          pendingFiles: const [
            PendingAttachmentFile(path: '/tmp/a.pdf', name: 'a.pdf'),
          ],
          persistAttachments: (attachments) async {
            if (persistFailures > 0) {
              persistFailures -= 1;
              throw StateError('metadata failed');
            }
            persisted.add(attachments.map((item) => item.path).toList());
          },
          failureMessage: '附件未完成',
        ),
      );

      expect(repository.deletePaths, isEmpty);

      await error.retry!();

      expect(repository.uploadNames, ['a.pdf']);
      expect(persisted.single, ['reminders/reminder-1/a.pdf']);
    },
  );

  test(
    'committed metadata with lost response remains linked and retries idempotently',
    () async {
      final repository = _FakeAttachmentRepository();
      var persistFailures = 1;
      var serverMetadata = <String>[];
      final attempts = <List<String>>[];

      final error = await _captureAttachmentError(
        () => syncPendingAttachments(
          repository: repository,
          category: 'reminders',
          refId: 'reminder-1',
          retainedAttachments: const [],
          pendingFiles: const [
            PendingAttachmentFile(path: '/tmp/a.pdf', name: 'a.pdf'),
          ],
          persistAttachments: (attachments) async {
            final paths = attachments.map((item) => item.path).toList();
            attempts.add(paths);
            serverMetadata = paths;
            if (persistFailures > 0) {
              persistFailures -= 1;
              throw StateError('response lost after commit');
            }
          },
          failureMessage: '附件未完成',
        ),
      );

      expect(serverMetadata, ['reminders/reminder-1/a.pdf']);
      expect(repository.deletePaths, isEmpty);

      await error.retry!();

      expect(repository.uploadNames, ['a.pdf']);
      expect(attempts, [
        ['reminders/reminder-1/a.pdf'],
        ['reminders/reminder-1/a.pdf'],
      ]);
      expect(serverMetadata, ['reminders/reminder-1/a.pdf']);
    },
  );

  test(
    'uncommitted metadata leaves only a GC-eligible orphan when retry is abandoned',
    () async {
      final repository = _FakeAttachmentRepository();
      var serverMetadata = <String>['reminders/reminder-1/old.pdf'];

      await _captureAttachmentError(
        () => syncPendingAttachments(
          repository: repository,
          category: 'reminders',
          refId: 'reminder-1',
          retainedAttachments: const [],
          pendingFiles: const [
            PendingAttachmentFile(path: '/tmp/a.pdf', name: 'a.pdf'),
          ],
          persistAttachments: (_) async {
            throw StateError('metadata rejected before commit');
          },
          failureMessage: '附件未完成',
        ),
      );

      expect(repository.uploadNames, ['a.pdf']);
      expect(repository.deletePaths, isEmpty);
      expect(serverMetadata, ['reminders/reminder-1/old.pdf']);
    },
  );

  test(
    'metadata failure after partial upload retries only the missing file',
    () async {
      final repository = _FakeAttachmentRepository()..failOnceFor.add('b.pdf');
      var persistFailures = 1;
      final attempts = <List<String>>[];

      final error = await _captureAttachmentError(
        () => syncPendingAttachments(
          repository: repository,
          category: 'lendings',
          refId: 'lend-1',
          retainedAttachments: const [],
          pendingFiles: const [
            PendingAttachmentFile(path: '/tmp/a.pdf', name: 'a.pdf'),
            PendingAttachmentFile(path: '/tmp/b.pdf', name: 'b.pdf'),
          ],
          persistAttachments: (attachments) async {
            attempts.add(attachments.map((item) => item.path).toList());
            if (persistFailures > 0) {
              persistFailures -= 1;
              throw StateError('metadata failed');
            }
          },
          failureMessage: '附件未完成',
        ),
      );

      await error.retry!();

      expect(repository.uploadNames, ['a.pdf', 'b.pdf', 'b.pdf']);
      expect(repository.deletePaths, isEmpty);
      expect(attempts, [
        ['lendings/lend-1/a.pdf'],
        ['lendings/lend-1/a.pdf', 'lendings/lend-1/b.pdf'],
      ]);
    },
  );
}

Future<AttachmentAfterSaveException> _captureAttachmentError(
  Future<void> Function() action,
) async {
  try {
    await action();
  } on AttachmentAfterSaveException catch (error) {
    expect(error.retry, isNotNull);
    return error;
  }
  fail('expected AttachmentAfterSaveException');
}

class _FakeAttachmentRepository implements AttachmentRepository {
  final failOnceFor = <String>{};
  final uploadNames = <String>[];
  final deletePaths = <String>[];

  @override
  Future<LedgerAttachment> upload({
    required PendingAttachmentFile file,
    required String category,
    required String refId,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    uploadNames.add(file.name);
    if (failOnceFor.remove(file.name)) {
      throw StateError('upload failed');
    }
    return LedgerAttachment(
      path: '$category/$refId/${file.name}',
      filename: file.name,
    );
  }

  @override
  Future<void> delete(String path) async {
    deletePaths.add(path);
  }

  @override
  Future<void> download(String path, String savePath) async {}

  @override
  Future<List<int>> downloadBytes(String path) async => const [];

  @override
  Uri downloadUri(String path) => Uri.parse('https://example.test/$path');
}
