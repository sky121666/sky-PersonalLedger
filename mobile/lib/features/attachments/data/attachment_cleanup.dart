import 'attachment_repository.dart';

Future<List<String>> deleteRemovedAttachments({
  required AttachmentRepository repository,
  required Iterable<String> originalPaths,
  required Iterable<String> retainedPaths,
}) async {
  final retainedPathSet = retainedPaths
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toSet();
  final removedPaths = originalPaths
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty && !retainedPathSet.contains(path))
      .toSet();

  final failedPaths = <String>[];
  for (final path in removedPaths) {
    try {
      await repository.delete(path);
    } catch (_) {
      failedPaths.add(path);
    }
  }
  return failedPaths;
}
