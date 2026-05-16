import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

final dataManagementRepositoryProvider = Provider<DataManagementRepository>((
  ref,
) {
  return DataManagementRepository(ref.watch(apiClientProvider));
});

class DataManagementRepository {
  const DataManagementRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<DataFileResult> downloadBackup() async {
    final response = await _apiClient.dio.get<List<int>>(
      '/backup',
      options: Options(responseType: ResponseType.bytes),
    );
    final filename =
        _filenameFromDisposition(
          response.headers.value('content-disposition'),
        ) ??
        _timestampedFilename('backup', 'json');
    return _saveBytes(filename, response.data ?? const <int>[]);
  }

  Future<DataFileResult> exportTransactionsCsv() async {
    final response = await _apiClient.dio.get<List<int>>(
      '/export/transactions/csv',
      options: Options(responseType: ResponseType.bytes),
    );
    final filename =
        _filenameFromDisposition(
          response.headers.value('content-disposition'),
        ) ??
        _timestampedFilename('transactions', 'csv');
    return _saveBytes(filename, response.data ?? const <int>[]);
  }

  Future<void> restoreBackup(PlatformFile file) async {
    final filePath = file.path;
    if (filePath == null || filePath.isEmpty) {
      throw const FormatException('请选择可读取的备份文件');
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: file.name),
    });
    await _apiClient.postMultipart<void>('/restore', data: formData);
  }

  Future<DataFileResult> _saveBytes(String filename, List<int> bytes) async {
    if (bytes.isEmpty) {
      throw const FormatException('下载内容为空');
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return DataFileResult(
      filename: filename,
      path: file.path,
      size: bytes.length,
    );
  }
}

class DataFileResult {
  const DataFileResult({
    required this.filename,
    required this.path,
    required this.size,
  });

  final String filename;
  final String path;
  final int size;
}

String? _filenameFromDisposition(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final utf8Match = RegExp(
    "filename\\*=UTF-8''([^;]+)",
    caseSensitive: false,
  ).firstMatch(value);
  if (utf8Match != null) {
    return Uri.decodeComponent(utf8Match.group(1)!.replaceAll('"', '').trim());
  }

  final match = RegExp(
    'filename="?([^";]+)"?',
    caseSensitive: false,
  ).firstMatch(value);
  return match?.group(1)?.trim();
}

String _timestampedFilename(String prefix, String extension) {
  final now = DateTime.now();
  final date =
      '${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final time =
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
  return '${prefix}_${date}_$time.$extension';
}
