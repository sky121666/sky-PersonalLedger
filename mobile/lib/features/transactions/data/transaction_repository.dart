import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import 'transaction_models.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(ref.watch(apiClientProvider));
});

class TransactionRepository {
  const TransactionRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 获取交易分页列表。
  Future<TransactionListResult> list(TransactionListQuery query) async {
    final data = await _apiClient.get<TransactionListResult>(
      '/transactions',
      queryParameters: query.toQueryParameters(),
      fromJsonT: (json) => TransactionListResult.fromJson(
        json as Map<String, dynamic>? ?? const {},
      ),
    );
    return data ??
        const TransactionListResult(list: [], total: 0, page: 1, pageSize: 20);
  }

  /// 获取交易详情。
  Future<TransactionItem> getById(String id) async {
    final data = await _apiClient.get<TransactionItem>(
      '/transactions/$id',
      fromJsonT: (json) =>
          TransactionItem.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (data == null) {
      throw const FormatException('交易详情响应为空');
    }
    return data;
  }

  /// 创建交易。
  Future<TransactionItem> create(TransactionFormData formData) async {
    final data = await _apiClient.post<TransactionItem>(
      '/transactions',
      data: formData.toJson(),
      fromJsonT: (json) =>
          TransactionItem.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (data == null) {
      throw const FormatException('创建交易响应为空');
    }
    return data;
  }

  /// 更新交易。
  Future<TransactionItem> update(
    String id,
    TransactionFormData formData,
  ) async {
    final data = await _apiClient.put<TransactionItem>(
      '/transactions/$id',
      data: formData.toJson(),
      fromJsonT: (json) =>
          TransactionItem.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (data == null) {
      throw const FormatException('更新交易响应为空');
    }
    return data;
  }

  /// 删除交易。
  Future<void> delete(String id) async {
    await _apiClient.delete<void>('/transactions/$id');
  }

  /// 获取账户列表。
  Future<List<LedgerAccount>> listAccounts() async {
    final data = await _apiClient.get<List<LedgerAccount>>(
      '/accounts',
      queryParameters: const {'include_archived': 'false'},
      fromJsonT: (json) {
        final map = json as Map<String, dynamic>? ?? const {};
        final list = map['list'];
        if (list is! List) {
          return const <LedgerAccount>[];
        }
        return list
            .whereType<Map<String, dynamic>>()
            .map(LedgerAccount.fromJson)
            .toList();
      },
    );
    return data ?? const [];
  }

  /// 获取分类列表。
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    final data = await _apiClient.get<List<LedgerCategory>>(
      '/categories',
      queryParameters: type == null ? null : {'type': type},
      fromJsonT: (json) {
        final map = json as Map<String, dynamic>? ?? const {};
        final list = map['list'];
        if (list is! List) {
          return const <LedgerCategory>[];
        }
        return list
            .whereType<Map<String, dynamic>>()
            .map(LedgerCategory.fromJson)
            .toList();
      },
    );
    return data ?? const [];
  }

  /// 获取标签列表。
  Future<List<LedgerTag>> listTags() async {
    final data = await _apiClient.get<List<LedgerTag>>(
      '/tags',
      fromJsonT: (json) {
        if (json is! List) {
          return const <LedgerTag>[];
        }
        return json
            .whereType<Map<String, dynamic>>()
            .map(LedgerTag.fromJson)
            .toList();
      },
    );
    return data ?? const [];
  }
}
