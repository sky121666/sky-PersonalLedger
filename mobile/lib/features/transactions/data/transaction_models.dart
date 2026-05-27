import 'dart:convert';

class LedgerAccount {
  const LedgerAccount({
    required this.id,
    required this.name,
    required this.type,
    this.icon = '',
    this.color = '',
    this.currentBalance = 0,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final String type;
  final String icon;
  final String color;
  final double currentBalance;
  final bool isArchived;

  /// 从账户接口 JSON 构建账户模型。
  factory LedgerAccount.fromJson(Map<String, dynamic> json) {
    return LedgerAccount(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      color: json['color'] as String? ?? '',
      currentBalance: _toDouble(json['current_balance']),
      isArchived: json['is_archived'] as bool? ?? false,
    );
  }
}

class LedgerCategory {
  const LedgerCategory({
    required this.id,
    required this.name,
    required this.type,
    this.icon = '',
    this.color = '',
  });

  final String id;
  final String name;
  final String type;
  final String icon;
  final String color;

  /// 从分类接口 JSON 构建分类模型。
  factory LedgerCategory.fromJson(Map<String, dynamic> json) {
    return LedgerCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      color: json['color'] as String? ?? '',
    );
  }
}

class LedgerTag {
  const LedgerTag({required this.id, required this.name, this.color = ''});

  final String id;
  final String name;
  final String color;

  /// 从标签接口 JSON 构建标签模型。
  factory LedgerTag.fromJson(Map<String, dynamic> json) {
    return LedgerTag(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as String? ?? '',
    );
  }
}

enum TransactionType {
  expense,
  income,
  transfer;

  String get value => name;

  String get label {
    return switch (this) {
      TransactionType.expense => '支出',
      TransactionType.income => '收入',
      TransactionType.transfer => '转账',
    };
  }

  /// 将后端交易类型字符串转换为枚举。
  static TransactionType fromValue(String value) {
    return switch (value) {
      'income' => TransactionType.income,
      'transfer' => TransactionType.transfer,
      _ => TransactionType.expense,
    };
  }
}

class TransactionItem {
  const TransactionItem({
    required this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    required this.transactionDate,
    this.categoryId,
    this.remark = '',
    this.images = '',
    this.tags = const [],
    this.toAccountId,
    this.memberId,
    this.paidByMemberId,
    this.account,
    this.toAccount,
    this.category,
  });

  final String id;
  final TransactionType type;
  final double amount;
  final String accountId;
  final String? categoryId;
  final DateTime transactionDate;
  final String remark;
  final String images;
  final List<String> tags;
  final String? toAccountId;
  final String? memberId;
  final String? paidByMemberId;
  final LedgerAccount? account;
  final LedgerAccount? toAccount;
  final LedgerCategory? category;

  String get typeLabel => type.label;

  String get displayTitle {
    if (type == TransactionType.transfer) {
      final from = account?.name ?? '转出账户';
      final to = toAccount?.name ?? '转入账户';
      return '$from → $to';
    }
    return category?.name ?? type.label;
  }

  /// 从交易接口 JSON 构建交易模型。
  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: json['id'] as String? ?? '',
      type: TransactionType.fromValue(json['type'] as String? ?? 'expense'),
      amount: _toDouble(json['amount']),
      accountId: json['account_id'] as String? ?? '',
      categoryId: json['category_id'] as String?,
      transactionDate: _parseDateTime(json['transaction_date']),
      remark: json['remark'] as String? ?? '',
      images: json['images'] as String? ?? '',
      tags: _parseTags(json['tags']),
      toAccountId: json['to_account_id'] as String?,
      memberId: json['member_id'] as String?,
      paidByMemberId: json['paid_by_member_id'] as String?,
      account: json['account'] is Map<String, dynamic>
          ? LedgerAccount.fromJson(json['account'] as Map<String, dynamic>)
          : null,
      toAccount: json['to_account'] is Map<String, dynamic>
          ? LedgerAccount.fromJson(json['to_account'] as Map<String, dynamic>)
          : null,
      category: json['category'] is Map<String, dynamic>
          ? LedgerCategory.fromJson(json['category'] as Map<String, dynamic>)
          : null,
    );
  }
}

class TransactionListResult {
  const TransactionListResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<TransactionItem> list;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;

  /// 从交易列表接口 JSON 构建分页结果。
  factory TransactionListResult.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'];
    return TransactionListResult(
      list: rawList is List
          ? rawList
                .whereType<Map<String, dynamic>>()
                .map(TransactionItem.fromJson)
                .toList()
          : const [],
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 20,
    );
  }
}

class TransactionListQuery {
  const TransactionListQuery({
    this.page = 1,
    this.pageSize = 20,
    this.type,
    this.accountId,
    this.categoryId,
    this.keyword,
    this.startDate,
    this.endDate,
  });

  final int page;
  final int pageSize;
  final TransactionType? type;
  final String? accountId;
  final String? categoryId;
  final String? keyword;
  final DateTime? startDate;
  final DateTime? endDate;

  /// 转换为交易列表接口查询参数。
  Map<String, dynamic> toQueryParameters() {
    return {
      'page': page,
      'page_size': pageSize,
      if (type != null) 'type': type!.value,
      if (accountId != null && accountId!.isNotEmpty) 'account_id': accountId,
      if (categoryId != null && categoryId!.isNotEmpty)
        'category_id': categoryId,
      if (keyword != null && keyword!.trim().isNotEmpty)
        'keyword': keyword!.trim(),
      if (startDate != null) 'start_date': _formatDate(startDate!),
      if (endDate != null) 'end_date': _formatDate(endDate!),
    };
  }
}

class TransactionFormData {
  const TransactionFormData({
    required this.type,
    required this.amount,
    required this.accountId,
    required this.transactionDate,
    this.toAccountId,
    this.categoryId,
    this.remark = '',
    this.images = '',
    this.tags = const [],
    this.memberId,
    this.paidByMemberId,
  });

  final TransactionType type;
  final double amount;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final DateTime transactionDate;
  final String remark;
  final String images;
  final List<String> tags;
  final String? memberId;
  final String? paidByMemberId;

  /// 转换为新增或编辑交易接口请求体。
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'amount': amount,
      'account_id': accountId,
      'transaction_date': transactionDate.toIso8601String(),
      'remark': remark.trim(),
      'images': images,
      'tags': jsonEncode(tags),
      if (memberId != null && memberId!.isNotEmpty) 'member_id': memberId,
      if (paidByMemberId != null && paidByMemberId!.isNotEmpty)
        'paid_by_member_id': paidByMemberId,
      if (type == TransactionType.transfer) 'to_account_id': toAccountId,
      if (type != TransactionType.transfer) 'category_id': categoryId,
    };
  }

  /// 从已有交易构建表单数据。
  factory TransactionFormData.fromTransaction(TransactionItem item) {
    return TransactionFormData(
      type: item.type,
      amount: item.amount,
      accountId: item.accountId,
      toAccountId: item.toAccountId,
      categoryId: item.categoryId,
      transactionDate: item.transactionDate,
      remark: item.remark,
      images: item.images,
      tags: item.tags,
      memberId: item.memberId,
      paidByMemberId: item.paidByMemberId,
    );
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

DateTime _parseDateTime(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed?.toLocal() ?? DateTime.now();
}

List<String> _parseTags(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
  }
  return const [];
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
