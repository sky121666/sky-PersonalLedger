import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../transactions/data/transaction_models.dart';

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(ref.watch(apiClientProvider));
});

class TemplateRepository {
  const TemplateRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<QuickTemplateItem>> list() async {
    final result = await _apiClient.get<List<QuickTemplateItem>>(
      '/templates',
      fromJsonT: (json) {
        final map = json is Map ? json.cast<String, dynamic>() : const {};
        final list = map['list'];
        if (list is! List) {
          return const <QuickTemplateItem>[];
        }
        return list.map(QuickTemplateItem.fromJson).toList();
      },
    );
    return result ?? const [];
  }

  Future<QuickTemplateItem> create(QuickTemplateRequest request) async {
    final result = await _apiClient.post<QuickTemplateItem>(
      '/templates',
      data: request.toJson(),
      fromJsonT: QuickTemplateItem.fromJson,
    );
    if (result == null) {
      throw const FormatException('创建模板响应为空');
    }
    return result;
  }

  Future<void> delete(String id) async {
    await _apiClient.delete<void>('/templates/$id');
  }

  Future<TransactionItem> apply(String id, ApplyTemplateRequest request) async {
    final result = await _apiClient.post<TransactionItem>(
      '/templates/$id/apply',
      data: request.toJson(),
      fromJsonT: (json) =>
          TransactionItem.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (result == null) {
      throw const FormatException('应用模板响应为空');
    }
    return result;
  }

  Future<List<LedgerAccount>> listAccounts() async {
    final result = await _apiClient.get<List<LedgerAccount>>(
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
    return result ?? const [];
  }

  Future<List<LedgerCategory>> listCategories() async {
    final result = await _apiClient.get<List<LedgerCategory>>(
      '/categories',
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
    return result ?? const [];
  }
}

class QuickTemplateItem {
  const QuickTemplateItem({
    required this.id,
    required this.name,
    required this.type,
    required this.amount,
    required this.accountId,
    this.userId = 0,
    this.categoryId,
    this.remark = '',
    this.usedCount = 0,
    this.lastUsedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final int userId;
  final String name;
  final TransactionType type;
  final double amount;
  final String accountId;
  final String? categoryId;
  final String remark;
  final int usedCount;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get typeLabel => type.label;

  factory QuickTemplateItem.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('模板响应格式不正确');
    }
    final map = json.cast<String, dynamic>();
    return QuickTemplateItem(
      id: map['id'] as String? ?? '',
      userId: _toInt(map['user_id']),
      name: map['name'] as String? ?? '',
      type: TransactionType.fromValue(map['type'] as String? ?? 'expense'),
      amount: _toDouble(map['amount']),
      accountId: map['account_id'] as String? ?? '',
      categoryId: map['category_id'] as String?,
      remark: map['remark'] as String? ?? '',
      usedCount: _toInt(map['used_count']),
      lastUsedAt: _toDateTime(map['last_used_at']),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }
}

class QuickTemplateRequest {
  const QuickTemplateRequest({
    required this.name,
    required this.type,
    required this.amount,
    required this.accountId,
    required this.categoryId,
    this.remark = '',
  });

  final String name;
  final TransactionType type;
  final double amount;
  final String accountId;
  final String categoryId;
  final String remark;

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'type': type.value,
      'amount': amount,
      'account_id': accountId,
      'category_id': categoryId,
      'remark': remark.trim(),
    };
  }
}

class ApplyTemplateRequest {
  const ApplyTemplateRequest({this.transactionDate, this.amount});

  final DateTime? transactionDate;
  final double? amount;

  Map<String, dynamic> toJson() {
    return {
      if (transactionDate != null)
        'transaction_date': _formatDate(transactionDate!),
      if (amount != null) 'amount': amount,
    };
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

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

DateTime? _toDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
