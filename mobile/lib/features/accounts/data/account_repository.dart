import '../../../core/network/api_client.dart';
import 'account.dart';

class AccountRepository {
  const AccountRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 获取账户列表和资产汇总。
  Future<AccountListResult> list({bool includeArchived = true}) async {
    final result = await _apiClient.get<AccountListResult>(
      '/accounts',
      queryParameters: {'include_archived': includeArchived},
      fromJsonT: (json) =>
          AccountListResult.fromJson((json as Map).cast<String, dynamic>()),
    );
    return result ??
        const AccountListResult(
          accounts: [],
          totalAssets: 0,
          totalLiabilities: 0,
          netAssets: 0,
        );
  }

  /// 获取账户详情。
  Future<Account> getById(String id) async {
    final result = await _apiClient.get<Account>(
      '/accounts/$id',
      fromJsonT: (json) =>
          Account.fromJson((json as Map).cast<String, dynamic>()),
    );
    return result!;
  }

  /// 创建账户。
  Future<Account> create(CreateAccountRequest request) async {
    final result = await _apiClient.post<Account>(
      '/accounts',
      data: request.toJson(),
      fromJsonT: (json) =>
          Account.fromJson((json as Map).cast<String, dynamic>()),
    );
    return result!;
  }

  /// 更新账户基础信息。
  Future<Account> update(String id, UpdateAccountRequest request) async {
    final result = await _apiClient.put<Account>(
      '/accounts/$id',
      data: request.toJson(),
      fromJsonT: (json) =>
          Account.fromJson((json as Map).cast<String, dynamic>()),
    );
    return result!;
  }

  /// 设置账户归档状态。
  Future<void> archive(String id, bool isArchived) async {
    await _apiClient.patch<void>(
      '/accounts/$id/archive',
      data: {'is_archived': isArchived},
    );
  }

  /// 删除账户。
  Future<void> delete(String id) async {
    await _apiClient.delete<void>('/accounts/$id');
  }

  /// 更新账户排序。
  Future<void> updateSort(List<String> ids) async {
    await _apiClient.put<void>('/accounts/sort', data: {'ids': ids});
  }
}
