class Transaction {
  final String id;
  final String type;
  final double amount;
  final String accountId;
  final String accountName;
  final String? categoryId;
  final String categoryName;
  final String categoryIcon;
  final String categoryColor;
  final String transactionDate;
  final String remark;
  final String? toAccountId;

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    required this.accountName,
    this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.transactionDate,
    required this.remark,
    this.toAccountId,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      accountId: json['account_id'] ?? '',
      accountName: json['account_name'] ?? '',
      categoryId: json['category_id'],
      categoryName: json['category_name'] ?? '',
      categoryIcon: json['category_icon'] ?? '',
      categoryColor: json['category_color'] ?? '#007AFF',
      transactionDate: json['transaction_date'] ?? '',
      remark: json['remark'] ?? '',
      toAccountId: json['to_account_id'],
    );
  }

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';
  bool get isTransfer => type == 'transfer';

  String get categoryEmoji {
    const map = {
      '餐饮': '🍽️',
      '交通': '🚗',
      '购物': '🛍️',
      '娱乐': '🎮',
      '居住': '🏠',
      '医疗': '💊',
      '教育': '📚',
      '工资': '💰',
      '奖金': '🎁',
      '理财': '📈',
    };
    return map[categoryName] ?? '💳';
  }
}

class TransactionListResponse {
  final List<Transaction> list;
  final int total;
  final int page;
  final int pageSize;

  TransactionListResponse({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory TransactionListResponse.fromJson(Map<String, dynamic> json) {
    return TransactionListResponse(
      list: (json['list'] as List<dynamic>?)
          ?.map((e) => Transaction.fromJson(e))
          .toList() ?? [],
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      pageSize: json['page_size'] ?? 20,
    );
  }

  bool get hasMore => list.length >= pageSize;
}
