class AttachmentAfterSaveException implements Exception {
  const AttachmentAfterSaveException(this.message, {this.recordId, this.retry});

  final String message;
  final String? recordId;
  final Future<void> Function()? retry;

  @override
  String toString() => message;
}
