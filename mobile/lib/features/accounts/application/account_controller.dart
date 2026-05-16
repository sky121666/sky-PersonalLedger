import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/account.dart';
import '../data/account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(ref.watch(apiClientProvider));
});

final accountListControllerProvider =
    StateNotifierProvider<AccountListController, AsyncValue<AccountListResult>>(
      (ref) => AccountListController(ref)..load(),
    );

class AccountListController
    extends StateNotifier<AsyncValue<AccountListResult>> {
  AccountListController(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;

  /// 加载账户列表。
  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _ref.read(accountRepositoryProvider).list(),
    );
  }

  /// 创建账户并刷新列表。
  Future<void> create(CreateAccountRequest request) async {
    await _ref.read(accountRepositoryProvider).create(request);
    await load();
  }

  /// 更新账户并刷新列表。
  Future<void> update(String id, UpdateAccountRequest request) async {
    await _ref.read(accountRepositoryProvider).update(id, request);
    await load();
  }

  /// 切换账户归档状态并刷新列表。
  Future<void> archive(Account account) async {
    await _ref
        .read(accountRepositoryProvider)
        .archive(account.id, !account.isArchived);
    await load();
  }

  /// 删除账户并刷新列表。
  Future<void> delete(String id) async {
    await _ref.read(accountRepositoryProvider).delete(id);
    await load();
  }
}
