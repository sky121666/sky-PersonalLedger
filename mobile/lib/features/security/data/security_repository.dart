import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

final securityRepositoryProvider = Provider<SecurityRepository>((ref) {
  return SecurityRepository(ref.watch(apiClientProvider));
});

class SecurityRepository {
  const SecurityRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _apiClient.post<void>(
      '/auth/change-password',
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
  }

  Future<SecurityEntryPath> getEntryPath() async {
    final result = await _apiClient.get<SecurityEntryPath>(
      '/system/entry-path',
      fromJsonT: SecurityEntryPath.fromJson,
    );
    return result ?? const SecurityEntryPath.disabled();
  }

  Future<SecurityEntryPath> setEntryPath(String entryPath) async {
    final result = await _apiClient.put<SecurityEntryPath>(
      '/system/entry-path',
      data: {'entry_path': entryPath},
      fromJsonT: SecurityEntryPath.fromJson,
    );
    return result ?? const SecurityEntryPath.disabled();
  }

  Future<SecurityEntryPath> generateEntryPath() async {
    final result = await _apiClient.post<SecurityEntryPath>(
      '/system/entry-path/generate',
      fromJsonT: SecurityEntryPath.fromJson,
    );
    return result ?? const SecurityEntryPath.disabled();
  }

  Future<SecurityEntryPath> disableEntryPath() async {
    final result = await _apiClient.delete<SecurityEntryPath>(
      '/system/entry-path',
      fromJsonT: SecurityEntryPath.fromJson,
    );
    return result ?? const SecurityEntryPath.disabled();
  }
}

class SecurityEntryPath {
  const SecurityEntryPath({
    required this.entryPath,
    required this.enabled,
    this.message,
  });

  const SecurityEntryPath.disabled()
    : entryPath = '',
      enabled = false,
      message = null;

  final String entryPath;
  final bool enabled;
  final String? message;

  String get displayPath => entryPath.isEmpty ? '未启用' : entryPath;

  factory SecurityEntryPath.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('安全入口响应格式不正确');
    }
    final map = json.cast<String, dynamic>();
    final path = map['entry_path'] as String? ?? '';
    return SecurityEntryPath(
      entryPath: path,
      enabled: map['enabled'] as bool? ?? path.isNotEmpty,
      message: map['message'] as String?,
    );
  }
}
