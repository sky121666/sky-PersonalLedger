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
    final filename = safeDownloadFilename(
      _filenameFromDisposition(response.headers.value('content-disposition')),
      fallback: _timestampedFilename('backup', 'json'),
    );
    return _saveBytes(filename, response.data ?? const <int>[]);
  }

  Future<DataFileResult> exportTransactionsCsv({
    ExportTransactionsFilter? filter,
  }) async {
    final response = await _apiClient.dio.get<List<int>>(
      '/export/transactions/csv',
      queryParameters: filter?.toQueryParameters(),
      options: Options(responseType: ResponseType.bytes),
    );
    final filename = safeDownloadFilename(
      _filenameFromDisposition(response.headers.value('content-disposition')),
      fallback: _timestampedFilename('transactions', 'csv'),
    );
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

  Future<AutoBackupOverview> getAutoBackupOverview() async {
    final results = await Future.wait<Object?>([
      getAutoBackupSettings(),
      listAutoBackupFiles(),
    ]);

    return AutoBackupOverview(
      settings:
          results[0] as AutoBackupSettings? ??
          const AutoBackupSettings(
            enabled: false,
            frequency: 'daily',
            hour: 3,
            maxBackups: 10,
          ),
      files: results[1] as List<AutoBackupFile>? ?? const [],
    );
  }

  Future<AutoBackupSettings?> getAutoBackupSettings() {
    return _apiClient.get<AutoBackupSettings>(
      '/backup/auto/settings',
      fromJsonT: AutoBackupSettings.fromJson,
    );
  }

  Future<AutoBackupSettings?> saveAutoBackupSettings(
    AutoBackupSettings settings,
  ) {
    return _apiClient.put<AutoBackupSettings>(
      '/backup/auto/settings',
      data: settings.toJson(),
      fromJsonT: AutoBackupSettings.fromJson,
    );
  }

  Future<void> triggerAutoBackup() async {
    await _apiClient.post<void>('/backup/auto/trigger');
  }

  Future<List<AutoBackupFile>?> listAutoBackupFiles() {
    return _apiClient.get<List<AutoBackupFile>>(
      '/backup/auto/list',
      fromJsonT: (json) {
        final map = json as Map<String, dynamic>? ?? const {};
        final files = map['files'];
        if (files is! List) {
          return const <AutoBackupFile>[];
        }
        return files.map(AutoBackupFile.fromJson).toList();
      },
    );
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

class ExportTransactionsFilter {
  const ExportTransactionsFilter({
    this.startDate,
    this.endDate,
    this.type,
    this.accountId,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final String? type;
  final String? accountId;

  Map<String, dynamic> toQueryParameters() {
    return {
      if (startDate != null) 'start_date': _formatDate(startDate!),
      if (endDate != null) 'end_date': _formatDate(endDate!),
      if (type != null && type!.isNotEmpty) 'type': type,
      if (accountId != null && accountId!.isNotEmpty) 'account_id': accountId,
    };
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

class AutoBackupOverview {
  const AutoBackupOverview({required this.settings, required this.files});

  final AutoBackupSettings settings;
  final List<AutoBackupFile> files;
}

class AutoBackupSettings {
  const AutoBackupSettings({
    required this.enabled,
    required this.frequency,
    required this.hour,
    required this.maxBackups,
    this.lastBackup,
  });

  final bool enabled;
  final String frequency;
  final int hour;
  final int maxBackups;
  final String? lastBackup;

  AutoBackupSettings copyWith({
    bool? enabled,
    String? frequency,
    int? hour,
    int? maxBackups,
    String? lastBackup,
  }) {
    return AutoBackupSettings(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      hour: hour ?? this.hour,
      maxBackups: maxBackups ?? this.maxBackups,
      lastBackup: lastBackup ?? this.lastBackup,
    );
  }

  factory AutoBackupSettings.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('自动备份设置响应格式不正确');
    }

    return AutoBackupSettings(
      enabled: json['enabled'] as bool? ?? false,
      frequency: json['frequency'] as String? ?? 'daily',
      hour: _clampInt(_toInt(json['hour'], fallback: 3), min: 0, max: 23),
      maxBackups: _clampInt(
        _toInt(json['max_backups'], fallback: 10),
        min: 1,
        max: 100,
      ),
      lastBackup: json['last_backup'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'frequency': frequency,
      'hour': hour,
      'max_backups': maxBackups,
    };
  }
}

class AutoBackupFile {
  const AutoBackupFile({
    required this.filename,
    required this.size,
    required this.createdAt,
  });

  final String filename;
  final int size;
  final String createdAt;

  factory AutoBackupFile.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('自动备份文件响应格式不正确');
    }

    return AutoBackupFile(
      filename: json['filename'] as String? ?? '',
      size: _toInt(json['size']),
      createdAt: json['created_at'] as String? ?? '',
    );
  }
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

String safeDownloadFilename(String? candidate, {required String fallback}) {
  final value = candidate?.trim();
  if (value == null || value.isEmpty) {
    return fallback;
  }
  final withoutPath = value.split(RegExp(r'[/\\]+')).last.trim();
  if (withoutPath.isEmpty ||
      withoutPath == '.' ||
      withoutPath == '..' ||
      withoutPath.contains('\u0000')) {
    return fallback;
  }
  return withoutPath;
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

int _toInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

int _clampInt(int value, {required int min, required int max}) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
