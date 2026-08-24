import 'attachment_after_save_exception.dart';
import 'attachment_models.dart';
import 'attachment_repository.dart';

Future<void> syncPendingAttachments({
  required AttachmentRepository repository,
  required String category,
  required String refId,
  required List<LedgerAttachment> retainedAttachments,
  required List<PendingAttachmentFile> pendingFiles,
  required Future<void> Function(List<LedgerAttachment> attachments)
  persistAttachments,
  required String failureMessage,
}) async {
  final uploaded =
      <({PendingAttachmentFile file, LedgerAttachment attachment})>[];
  final failedFiles = <PendingAttachmentFile>[];

  for (final file in pendingFiles) {
    try {
      final attachment = await repository.upload(
        file: file,
        category: category,
        refId: refId,
      );
      uploaded.add((file: file, attachment: attachment));
    } catch (_) {
      failedFiles.add(file);
    }
  }

  final nextAttachments = [
    ...retainedAttachments,
    ...uploaded.map((item) => item.attachment),
  ];
  try {
    await persistAttachments(nextAttachments);
  } catch (_) {
    // The metadata request may have committed even when its response was
    // lost. Keep every successfully uploaded path and retry the idempotent
    // target metadata instead of issuing a compensating DELETE that could
    // turn an already-committed reference into a broken one. If metadata was
    // not committed and the user abandons the retry, upload GC can safely
    // remove the unreferenced file after its grace period.
    throw AttachmentAfterSaveException(
      failureMessage,
      recordId: refId,
      retry: () => syncPendingAttachments(
        repository: repository,
        category: category,
        refId: refId,
        retainedAttachments: nextAttachments,
        pendingFiles: failedFiles,
        persistAttachments: persistAttachments,
        failureMessage: failureMessage,
      ),
    );
  }

  if (failedFiles.isNotEmpty) {
    throw AttachmentAfterSaveException(
      failureMessage,
      recordId: refId,
      retry: () => syncPendingAttachments(
        repository: repository,
        category: category,
        refId: refId,
        retainedAttachments: nextAttachments,
        pendingFiles: failedFiles,
        persistAttachments: persistAttachments,
        failureMessage: failureMessage,
      ),
    );
  }
}
