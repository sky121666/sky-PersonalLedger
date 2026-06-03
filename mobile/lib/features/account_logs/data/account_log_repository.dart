import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../accounts/data/account.dart';

final accountLogRepositoryProvider = Provider<AccountLogRepository>((ref) {
  return AccountLogRepository(ref.watch(apiClientProvider));
});

class AccountLogRepository {
  const AccountLogRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 获取流水分页列表。
  Future<AccountLogListResult> list({int page = 1, int pageSize = 50}) async {
    final result = await _apiClient.get<AccountLogListResult>(
      '/account-logs',
      queryParameters: {'page': page, 'page_size': pageSize},
      fromJsonT: AccountLogListResult.fromJson,
    );
    return result ?? AccountLogListResult.empty(page: page, pageSize: pageSize);
  }

  /// 获取单个账户的流水分页列表。
  Future<AccountLogListResult> listByAccountId(
    String accountId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final result = await _apiClient.get<AccountLogListResult>(
      '/account-logs/account/$accountId',
      queryParameters: {'page': page, 'page_size': pageSize},
      fromJsonT: AccountLogListResult.fromJson,
    );
    return result ?? AccountLogListResult.empty(page: page, pageSize: pageSize);
  }
}

class AccountLogListResult {
  const AccountLogListResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<AccountLogItem> list;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;

  factory AccountLogListResult.empty({int page = 1, int pageSize = 50}) {
    return AccountLogListResult(
      list: const [],
      total: 0,
      page: page,
      pageSize: pageSize,
    );
  }

  factory AccountLogListResult.fromJson(Object? json) {
    final map = json is Map ? json.cast<String, dynamic>() : const {};
    final rawList = map['list'];
    return AccountLogListResult(
      list: rawList is List
          ? rawList.map(AccountLogItem.fromJson).toList()
          : const [],
      total: _toInt(map['total']),
      page: _toInt(map['page'], fallback: 1),
      pageSize: _toInt(map['page_size'], fallback: 50),
    );
  }
}

class AccountLogItem {
  const AccountLogItem({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.createdAt,
    this.transactionId,
    this.reminderId,
    this.lendingId,
    this.remark = '',
    this.account,
  });

  final String id;
  final String accountId;
  final AccountLogType type;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final DateTime createdAt;
  final String? transactionId;
  final String? reminderId;
  final String? lendingId;
  final String remark;
  final Account? account;

  double get balanceChange => balanceAfter - balanceBefore;

  factory AccountLogItem.fromJson(Object? json) {
    final map = json is Map ? json.cast<String, dynamic>() : const {};
    return AccountLogItem(
      id: map['id'] as String? ?? '',
      accountId: map['account_id'] as String? ?? '',
      type: AccountLogType.fromJson(map['type']),
      amount: _toDouble(map['amount']),
      balanceBefore: _toDouble(map['balance_before']),
      balanceAfter: _toDouble(map['balance_after']),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      transactionId: map['transaction_id'] as String?,
      reminderId: map['reminder_id'] as String?,
      lendingId: map['lending_id'] as String?,
      remark: map['remark'] as String? ?? '',
      account: map['account'] is Map
          ? Account.fromJson((map['account'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

enum AccountLogType {
  income('income', '收入'),
  expense('expense', '支出'),
  transferIn('transfer_in', '转入'),
  transferOut('transfer_out', '转出'),
  rollback('rollback', '撤回'),
  adjustment('adjustment', '调整');

  const AccountLogType(this.value, this.label);

  final String value;
  final String label;

  static AccountLogType fromJson(Object? value) {
    return switch (value?.toString()) {
      'income' => AccountLogType.income,
      'transfer_in' => AccountLogType.transferIn,
      'transfer_out' => AccountLogType.transferOut,
      'rollback' => AccountLogType.rollback,
      'adjustment' => AccountLogType.adjustment,
      _ => AccountLogType.expense,
    };
  }
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _toInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
