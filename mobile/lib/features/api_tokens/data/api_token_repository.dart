import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

final apiTokenRepositoryProvider = Provider<ApiTokenRepository>((ref) {
  return ApiTokenRepository(ref.watch(apiClientProvider));
});

class ApiTokenRepository {
  const ApiTokenRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 获取当前用户的 API Token 列表。
  Future<List<ApiTokenItem>> list() async {
    final result = await _apiClient.get<List<ApiTokenItem>>(
      '/api-tokens',
      fromJsonT: (json) {
        final map = json is Map ? json.cast<String, dynamic>() : const {};
        final list = map['list'];
        if (list is! List) {
          return const <ApiTokenItem>[];
        }
        return list.map(ApiTokenItem.fromJson).toList();
      },
    );
    return result ?? const [];
  }

  /// 创建新 API Token。完整 token 只会在本次响应中返回。
  Future<ApiTokenCreateResult> create(ApiTokenCreateRequest request) async {
    final result = await _apiClient.post<ApiTokenCreateResult>(
      '/api-tokens',
      data: request.toJson(),
      fromJsonT: ApiTokenCreateResult.fromJson,
    );
    if (result == null) {
      throw const FormatException('创建令牌响应为空');
    }
    return result;
  }

  /// 删除指定 API Token。
  Future<void> delete(int id) async {
    await _apiClient.delete<void>('/api-tokens/$id');
  }
}

class ApiTokenItem {
  const ApiTokenItem({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  final int id;
  final String name;
  final String tokenPrefix;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  bool get neverExpires => expiresAt == null;

  factory ApiTokenItem.fromJson(Object? json) {
    final map = json is Map ? json.cast<String, dynamic>() : const {};
    return ApiTokenItem(
      id: _toInt(map['id']),
      name: map['name'] as String? ?? '',
      tokenPrefix: map['token_prefix'] as String? ?? '',
      createdAt:
          _toDateTime(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastUsedAt: _toDateTime(map['last_used_at']),
      expiresAt: _toDateTime(map['expires_at']),
    );
  }
}

class ApiTokenCreateResult extends ApiTokenItem {
  const ApiTokenCreateResult({
    required super.id,
    required super.name,
    required super.tokenPrefix,
    required super.createdAt,
    required this.token,
    super.lastUsedAt,
    super.expiresAt,
  });

  final String token;

  factory ApiTokenCreateResult.fromJson(Object? json) {
    final map = json is Map ? json.cast<String, dynamic>() : const {};
    return ApiTokenCreateResult(
      id: _toInt(map['id']),
      name: map['name'] as String? ?? '',
      token: map['token'] as String? ?? '',
      tokenPrefix: map['token_prefix'] as String? ?? '',
      createdAt:
          _toDateTime(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastUsedAt: _toDateTime(map['last_used_at']),
      expiresAt: _toDateTime(map['expires_at']),
    );
  }
}

class ApiTokenCreateRequest {
  const ApiTokenCreateRequest({
    required this.name,
    required this.expiresInDays,
  });

  final String name;
  final int expiresInDays;

  Map<String, dynamic> toJson() {
    return {'name': name, 'expires_in_days': expiresInDays};
  }
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _toDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
