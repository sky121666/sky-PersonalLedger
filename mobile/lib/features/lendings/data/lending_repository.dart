import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../accounts/application/account_controller.dart';
import '../../accounts/data/account.dart';

final lendingRepositoryProvider = Provider<LendingRepository>((ref) {
  return LendingRepository(ref.watch(apiClientProvider));
});

final lendingDashboardProvider = FutureProvider.autoDispose<LendingDashboard>((
  ref,
) async {
  final results = await Future.wait<Object?>([
    ref.watch(lendingRepositoryProvider).list(includeSettled: true),
    ref.watch(lendingRepositoryProvider).summaryOverview(),
    ref.watch(accountRepositoryProvider).list(includeArchived: false),
  ]);

  return LendingDashboard(
    lendings: results[0] as List<LendingItem>? ?? const [],
    summary: results[1] as LendingSummary? ?? const LendingSummary.empty(),
    accounts: (results[2] as AccountListResult?)?.accounts ?? const <Account>[],
  );
});

class LendingRepository {
  const LendingRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<LendingItem>?> list({bool includeSettled = false}) {
    return _apiClient.get<List<LendingItem>>(
      '/lendings',
      queryParameters: {'include_settled': includeSettled},
      fromJsonT: (json) {
        if (json is! List) {
          throw const FormatException('借贷列表响应格式不正确');
        }
        return json.map(LendingItem.fromJson).toList();
      },
    );
  }

  Future<LendingSummary?> summaryOverview() {
    return _apiClient.get<LendingSummary>(
      '/lendings/summary',
      fromJsonT: LendingSummary.fromJson,
    );
  }

  Future<LendingItem?> create(CreateLendingRequest request) {
    return _apiClient.post<LendingItem>(
      '/lendings',
      data: request.toJson(),
      fromJsonT: LendingItem.fromJson,
    );
  }

  Future<LendingItem?> update(String id, UpdateLendingRequest request) {
    return _apiClient.patch<LendingItem>(
      '/lendings/$id',
      data: request.toJson(),
      fromJsonT: LendingItem.fromJson,
    );
  }

  Future<LendingItem?> updateAttachments(String id, String evidence) {
    return _apiClient.patch<LendingItem>(
      '/lendings/$id',
      data: {'evidence': evidence},
      fromJsonT: LendingItem.fromJson,
    );
  }

  Future<void> delete(String id) async {
    await _apiClient.delete<void>('/lendings/$id');
  }

  Future<LendingItem?> recordRepayment(
    String id,
    RecordRepaymentRequest request,
  ) {
    return _apiClient.post<LendingItem>(
      '/lendings/$id/repay',
      data: request.toJson(),
      fromJsonT: LendingItem.fromJson,
    );
  }

  Future<List<LendingRecordItem>?> records(String id) {
    return _apiClient.get<List<LendingRecordItem>>(
      '/lendings/$id/records',
      fromJsonT: (json) {
        if (json is! List) {
          throw const FormatException('还款记录响应格式不正确');
        }
        return json.map(LendingRecordItem.fromJson).toList();
      },
    );
  }
}

class LendingDashboard {
  const LendingDashboard({
    required this.lendings,
    required this.summary,
    required this.accounts,
  });

  final List<LendingItem> lendings;
  final LendingSummary summary;
  final List<Account> accounts;

  List<LendingItem> get activeLendOut {
    return lendings
        .where((item) => item.type == LendingType.lendOut && !item.isSettled)
        .toList();
  }

  List<LendingItem> get activeBorrowIn {
    return lendings
        .where((item) => item.type == LendingType.borrowIn && !item.isSettled)
        .toList();
  }

  List<LendingItem> get settled {
    return lendings.where((item) => item.isSettled).toList();
  }

  List<Account> get activeAccounts {
    return accounts.where((account) => !account.isArchived).toList();
  }
}

enum LendingType {
  lendOut,
  borrowIn;

  String get value {
    return switch (this) {
      LendingType.lendOut => 'lend_out',
      LendingType.borrowIn => 'borrow_in',
    };
  }

  String get label {
    return switch (this) {
      LendingType.lendOut => '借出',
      LendingType.borrowIn => '借入',
    };
  }

  static LendingType fromJson(Object? value) {
    return switch (value) {
      'borrow_in' => LendingType.borrowIn,
      _ => LendingType.lendOut,
    };
  }
}

class LendingItem {
  const LendingItem({
    required this.id,
    required this.type,
    required this.contactName,
    required this.principal,
    required this.currentBalance,
    required this.totalRepaid,
    required this.lendDate,
    this.contactPhone = '',
    this.contactRemark = '',
    this.interestRate,
    this.dueDate,
    this.settledAt,
    this.accountId,
    this.accountName,
    this.remark = '',
    this.evidence = '',
    this.isSettled = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final LendingType type;
  final String contactName;
  final String contactPhone;
  final String contactRemark;
  final double principal;
  final double? interestRate;
  final double currentBalance;
  final double totalRepaid;
  final DateTime lendDate;
  final DateTime? dueDate;
  final DateTime? settledAt;
  final String? accountId;
  final String? accountName;
  final String remark;
  final String evidence;
  final bool isSettled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get typeLabel => type.label;

  double get progress {
    if (principal <= 0) {
      return 0;
    }
    final value = totalRepaid / principal * 100;
    return value.clamp(0, 100).toDouble();
  }

  bool get isOverdue {
    final due = dueDate;
    if (due == null || isSettled) {
      return false;
    }
    return due.isBefore(DateTime.now());
  }

  factory LendingItem.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('借贷记录响应格式不正确');
    }

    final account = json['account'];
    return LendingItem(
      id: json['id'] as String? ?? '',
      type: LendingType.fromJson(json['type']),
      contactName: json['contact_name'] as String? ?? '',
      contactPhone: json['contact_phone'] as String? ?? '',
      contactRemark: json['contact_remark'] as String? ?? '',
      principal: _toDouble(json['principal']),
      interestRate: _toNullableDouble(json['interest_rate']),
      currentBalance: _toDouble(json['current_balance']),
      totalRepaid: _toDouble(json['total_repaid']),
      lendDate: _toDate(json['lend_date']) ?? DateTime.now(),
      dueDate: _toDate(json['due_date']),
      settledAt: _toDate(json['settled_at']),
      accountId: json['account_id'] as String?,
      accountName: account is Map ? account['name'] as String? : null,
      remark: json['remark'] as String? ?? '',
      evidence: json['evidence'] as String? ?? '',
      isSettled: json['is_settled'] as bool? ?? false,
      createdAt: _toDate(json['created_at']),
      updatedAt: _toDate(json['updated_at']),
    );
  }
}

enum LendingRecordType {
  repay,
  additional;

  String get label {
    return switch (this) {
      LendingRecordType.repay => '还款',
      LendingRecordType.additional => '追加',
    };
  }

  static LendingRecordType fromJson(Object? value) {
    return switch (value) {
      'additional' => LendingRecordType.additional,
      _ => LendingRecordType.repay,
    };
  }
}

class LendingRecordItem {
  const LendingRecordItem({
    required this.id,
    required this.lendingId,
    required this.type,
    required this.amount,
    required this.recordDate,
    this.accountId,
    this.accountName,
    this.transactionId,
    this.remark = '',
    this.evidence = '',
  });

  final String id;
  final String lendingId;
  final LendingRecordType type;
  final double amount;
  final DateTime recordDate;
  final String? accountId;
  final String? accountName;
  final String? transactionId;
  final String remark;
  final String evidence;

  factory LendingRecordItem.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('还款记录响应格式不正确');
    }

    final account = json['account'];
    final accountMap = account is Map<String, dynamic> ? account : null;
    return LendingRecordItem(
      id: json['id'] as String? ?? '',
      lendingId: json['lending_id'] as String? ?? '',
      type: LendingRecordType.fromJson(json['type']),
      amount: _toDouble(json['amount']),
      recordDate: _toDate(json['record_date']) ?? DateTime.now(),
      accountId: json['account_id'] as String?,
      accountName: accountMap?['name'] as String?,
      transactionId: json['transaction_id'] as String?,
      remark: json['remark'] as String? ?? '',
      evidence: json['evidence'] as String? ?? '',
    );
  }
}

class LendingSummary {
  const LendingSummary({
    required this.totalLendOut,
    required this.totalBorrowIn,
    required this.activeLendOut,
    required this.activeBorrowIn,
    required this.settledLendOut,
    required this.settledBorrowIn,
    required this.totalReceivable,
    required this.totalPayable,
    required this.netLending,
  });

  const LendingSummary.empty()
    : totalLendOut = 0,
      totalBorrowIn = 0,
      activeLendOut = 0,
      activeBorrowIn = 0,
      settledLendOut = 0,
      settledBorrowIn = 0,
      totalReceivable = 0,
      totalPayable = 0,
      netLending = 0;

  final double totalLendOut;
  final double totalBorrowIn;
  final int activeLendOut;
  final int activeBorrowIn;
  final int settledLendOut;
  final int settledBorrowIn;
  final double totalReceivable;
  final double totalPayable;
  final double netLending;

  factory LendingSummary.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('借贷汇总响应格式不正确');
    }
    return LendingSummary(
      totalLendOut: _toDouble(json['total_lend_out']),
      totalBorrowIn: _toDouble(json['total_borrow_in']),
      activeLendOut: _toInt(json['active_lend_out']),
      activeBorrowIn: _toInt(json['active_borrow_in']),
      settledLendOut: _toInt(json['settled_lend_out']),
      settledBorrowIn: _toInt(json['settled_borrow_in']),
      totalReceivable: _toDouble(json['total_receivable']),
      totalPayable: _toDouble(json['total_payable']),
      netLending: _toDouble(json['net_lending']),
    );
  }
}

class CreateLendingRequest {
  const CreateLendingRequest({
    required this.type,
    required this.contactName,
    required this.principal,
    required this.lendDate,
    this.contactPhone = '',
    this.contactRemark = '',
    this.interestRate,
    this.dueDate,
    this.accountId,
    this.remark = '',
    this.evidence = '',
    this.createTransaction = false,
  });

  final LendingType type;
  final String contactName;
  final String contactPhone;
  final String contactRemark;
  final double principal;
  final double? interestRate;
  final String lendDate;
  final String? dueDate;
  final String? accountId;
  final String remark;
  final String evidence;
  final bool createTransaction;

  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'contact_name': contactName,
      'principal': principal,
      'lend_date': lendDate,
      'create_transaction': createTransaction,
      if (contactPhone.isNotEmpty) 'contact_phone': contactPhone,
      if (contactRemark.isNotEmpty) 'contact_remark': contactRemark,
      if (interestRate != null) 'interest_rate': interestRate,
      if (dueDate != null && dueDate!.isNotEmpty) 'due_date': dueDate,
      if (accountId != null && accountId!.isNotEmpty) 'account_id': accountId,
      if (remark.isNotEmpty) 'remark': remark,
      if (evidence.isNotEmpty) 'evidence': evidence,
    };
  }
}

class UpdateLendingRequest {
  const UpdateLendingRequest({
    required this.contactName,
    this.contactPhone = '',
    this.contactRemark = '',
    this.interestRate,
    this.dueDate,
    this.remark = '',
    this.evidence = '',
  });

  final String contactName;
  final String contactPhone;
  final String contactRemark;
  final double? interestRate;
  final String? dueDate;
  final String remark;
  final String evidence;

  Map<String, dynamic> toJson() {
    return {
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'contact_remark': contactRemark,
      'interest_rate': interestRate,
      'due_date': dueDate,
      'remark': remark,
      'evidence': evidence,
    };
  }

  factory UpdateLendingRequest.fromItem(LendingItem item) {
    return UpdateLendingRequest(
      contactName: item.contactName,
      contactPhone: item.contactPhone,
      contactRemark: item.contactRemark,
      interestRate: item.interestRate,
      dueDate: item.dueDate == null
          ? null
          : _formatRequestDateTime(item.dueDate!),
      remark: item.remark,
      evidence: item.evidence,
    );
  }
}

class RecordRepaymentRequest {
  const RecordRepaymentRequest({
    required this.amount,
    required this.recordDate,
    this.accountId,
    this.remark = '',
    this.evidence = '',
    this.createTransaction = false,
  });

  final double amount;
  final String recordDate;
  final String? accountId;
  final String remark;
  final String evidence;
  final bool createTransaction;

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'record_date': recordDate,
      'create_transaction': createTransaction,
      if (accountId != null && accountId!.isNotEmpty) 'account_id': accountId,
      if (remark.isNotEmpty) 'remark': remark,
      if (evidence.isNotEmpty) 'evidence': evidence,
    };
  }
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

double? _toNullableDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String && value.isNotEmpty) {
    return double.tryParse(value);
  }
  return null;
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

DateTime? _toDate(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

String _formatRequestDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}T'
      '${two(value.hour)}:${two(value.minute)}';
}
