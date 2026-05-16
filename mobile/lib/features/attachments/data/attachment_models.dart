import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class LedgerAttachment {
  const LedgerAttachment({
    required this.path,
    required this.filename,
    this.url = '',
    this.size = 0,
    this.mimeType = '',
  });

  final String path;
  final String filename;
  final String url;
  final int size;
  final String mimeType;

  factory LedgerAttachment.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    return LedgerAttachment(
      path: path,
      filename: json['filename'] as String? ?? _filenameFromPath(path),
      url: json['url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      mimeType: json['mime_type'] as String? ?? '',
    );
  }

  factory LedgerAttachment.fromPath(String path) {
    return LedgerAttachment(path: path, filename: _filenameFromPath(path));
  }

  bool get isImage {
    final extension = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
  }
}

class PendingAttachmentFile {
  const PendingAttachmentFile({
    required this.path,
    required this.name,
    this.size = 0,
    this.mimeType,
  });

  final String path;
  final String name;
  final int size;
  final String? mimeType;

  factory PendingAttachmentFile.fromPlatformFile(PlatformFile file) {
    return PendingAttachmentFile(
      path: file.path ?? '',
      name: file.name,
      size: file.size,
    );
  }

  factory PendingAttachmentFile.fromXFile(XFile file) {
    return PendingAttachmentFile(
      path: file.path,
      name: file.name,
      mimeType: file.mimeType,
    );
  }

  bool get isImage {
    final extension = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
  }
}

class AttachmentUploadProgress {
  const AttachmentUploadProgress({
    required this.fileName,
    required this.progress,
    this.completed = false,
  });

  final String fileName;
  final double progress;
  final bool completed;
}

List<String> decodeAttachmentPaths(String value) {
  if (value.trim().isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded.whereType<String>().toList();
    }
  } catch (_) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

String encodeAttachmentPaths(List<String> paths) {
  return jsonEncode(paths);
}

String _filenameFromPath(String path) {
  final normalizedPath = path.replaceAll('\\', '/');
  final segments = normalizedPath.split('/');
  return segments.isEmpty ? path : segments.last;
}
