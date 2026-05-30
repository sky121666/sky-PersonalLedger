import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import 'attachment_models.dart';

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return AttachmentRepository(ref.watch(apiClientProvider));
});

class AttachmentRepository {
  const AttachmentRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<LedgerAttachment> upload({
    required PendingAttachmentFile file,
    required String category,
    required String refId,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.name),
      'category': category,
      'ref_id': refId,
    });

    final attachment = await _apiClient.postMultipart<LedgerAttachment>(
      '/upload',
      data: formData,
      onSendProgress: onSendProgress,
      fromJsonT: (json) =>
          LedgerAttachment.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (attachment == null) {
      throw const FormatException('上传响应为空');
    }
    return attachment;
  }

  Future<void> delete(String path) async {
    await _apiClient.delete<void>('/upload', queryParameters: {'path': path});
  }

  Future<void> download(String path, String savePath) async {
    await _apiClient.dio.download(downloadUri(path).toString(), savePath);
  }

  Future<List<int>> downloadBytes(String path) async {
    final response = await _apiClient.dio.get<List<int>>(
      '/upload/download',
      queryParameters: {'path': path},
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }

  Uri downloadUri(String path) {
    final baseUrl = _apiClient.dio.options.baseUrl;
    return Uri.parse(
      '$baseUrl/upload/download',
    ).replace(queryParameters: {'path': path});
  }
}
