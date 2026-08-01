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

  Future<TransactionImportPreview> previewTransactionImport(
    PlatformFile file,
  ) async {
    final extension = (file.extension ?? '').toLowerCase();
    if (extension != 'csv' && extension != 'json') {
      throw const FormatException('请选择 CSV 或 JSON 交易文件');
    }
    if (file.size > transactionImportMaxFileBytes) {
      throw const FormatException('交易文件不能超过 5 MB');
    }
    final multipartFile = await _platformMultipartFile(file);
    final result = await _apiClient.postMultipart<TransactionImportPreview>(
      '/imports/transactions/preview',
      data: FormData.fromMap({'file': multipartFile}),
      fromJsonT: TransactionImportPreview.fromJson,
    );
    if (result == null) {
      throw const FormatException('交易导入预览响应为空');
    }
    return result;
  }

  Future<TransactionImportPreview?> getRecentTransactionImport() {
    return _apiClient.get<TransactionImportPreview?>(
      '/imports/transactions/recent',
      fromJsonT: (json) =>
          json == null ? null : TransactionImportPreview.fromJson(json),
    );
  }

  Future<List<TransactionImportPreview>> listRecentTransactionImports() async {
    final result = await _apiClient.get<List<TransactionImportPreview>>(
      '/imports/transactions',
      queryParameters: const {'limit': 64},
      fromJsonT: (json) {
        final map = json is Map ? json.cast<String, dynamic>() : const {};
        final list = map['list'];
        if (list is! List) {
          return const <TransactionImportPreview>[];
        }
        return list
            .map(TransactionImportPreview.fromJson)
            .toList(growable: false);
      },
    );
    return result ?? const [];
  }

  Future<TransactionImportPreview> getTransactionImport(String id) async {
    final result = await _apiClient.get<TransactionImportPreview>(
      '/imports/transactions/$id',
      fromJsonT: TransactionImportPreview.fromJson,
    );
    if (result == null) {
      throw const FormatException('交易导入状态响应为空');
    }
    return result;
  }

  Future<TransactionImportPreview> validateTransactionImport(String id) {
    return _transactionImportAction(id, 'validate');
  }

  Future<TransactionImportPreview> commitTransactionImport(String id) {
    return _transactionImportAction(id, 'commit');
  }

  Future<TransactionImportPreview> rollbackTransactionImport(String id) {
    return _transactionImportAction(id, 'rollback');
  }

  Future<TransactionImportPreview> _transactionImportAction(
    String id,
    String action,
  ) async {
    final result = await _apiClient.post<TransactionImportPreview>(
      '/imports/transactions/$id/$action',
      fromJsonT: TransactionImportPreview.fromJson,
    );
    if (result == null) {
      throw const FormatException('交易导入响应为空');
    }
    return result;
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

const transactionImportMaxFileBytes = 5 * 1024 * 1024;

Future<MultipartFile> _platformMultipartFile(PlatformFile file) async {
  final path = file.path;
  if (path != null && path.isNotEmpty) {
    return MultipartFile.fromFile(path, filename: file.name);
  }
  final bytes = file.bytes;
  if (bytes != null && bytes.isNotEmpty) {
    return MultipartFile.fromBytes(bytes, filename: file.name);
  }
  throw const FormatException('请选择可读取的交易文件');
}

class TransactionImportPreview {
  const TransactionImportPreview({
    required this.id,
    required this.filename,
    required this.format,
    required this.status,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.createdRows,
    required this.rolledBackRows,
    required this.rows,
    required this.rowsTruncated,
    required this.createdAt,
    required this.expiresAt,
    this.committedAt,
    this.rolledBackAt,
  });

  final String id;
  final String filename;
  final String format;
  final String status;
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int createdRows;
  final int rolledBackRows;
  final List<TransactionImportRow> rows;
  final bool rowsTruncated;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? committedAt;
  final DateTime? rolledBackAt;

  bool get canCommit =>
      (status == 'previewed' || status == 'validated') && invalidRows == 0;
  bool get canRollback => status == 'committed';
  int get importableRows => (validRows - duplicateRows).clamp(0, totalRows);

  factory TransactionImportPreview.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('交易导入响应格式不正确');
    }
    final map = json.cast<String, dynamic>();
    final rawRows = map['rows'];
    return TransactionImportPreview(
      id: map['id'] as String? ?? '',
      filename: map['filename'] as String? ?? '',
      format: map['format'] as String? ?? '',
      status: map['status'] as String? ?? 'previewed',
      totalRows: _toInt(map['total_rows']),
      validRows: _toInt(map['valid_rows']),
      invalidRows: _toInt(map['invalid_rows']),
      duplicateRows: _toInt(map['duplicate_rows']),
      createdRows: _toInt(map['created_rows']),
      rolledBackRows: _toInt(map['rolled_back_rows']),
      rows: rawRows is List
          ? rawRows.map(TransactionImportRow.fromJson).toList(growable: false)
          : const [],
      rowsTruncated: map['rows_truncated'] as bool? ?? false,
      createdAt:
          _toDateTime(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt:
          _toDateTime(map['expires_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      committedAt: _toDateTime(map['committed_at']),
      rolledBackAt: _toDateTime(map['rolled_back_at']),
    );
  }
}

class TransactionImportRow {
  const TransactionImportRow({
    required this.row,
    required this.type,
    required this.amount,
    required this.transactionDate,
    required this.account,
    required this.category,
    required this.valid,
    required this.duplicate,
    required this.errors,
    required this.warnings,
  });

  final int row;
  final String type;
  final double amount;
  final String transactionDate;
  final String account;
  final String category;
  final bool valid;
  final bool duplicate;
  final List<String> errors;
  final List<String> warnings;

  factory TransactionImportRow.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('交易导入行格式不正确');
    }
    final map = json.cast<String, dynamic>();
    return TransactionImportRow(
      row: _toInt(map['row']),
      type: map['type'] as String? ?? '',
      amount: _toDouble(map['amount']),
      transactionDate: map['transaction_date'] as String? ?? '',
      account: map['account'] as String? ?? '',
      category: map['category'] as String? ?? '',
      valid: map['valid'] as bool? ?? false,
      duplicate: map['duplicate'] as bool? ?? false,
      errors: _toStringList(map['errors']),
      warnings: _toStringList(map['warnings']),
    );
  }
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _toDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

List<String> _toStringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => item.toString()).toList(growable: false);
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
