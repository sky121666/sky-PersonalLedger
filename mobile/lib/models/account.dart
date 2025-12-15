class Account {
  final String id;
  final String name;
  final String type;
  final String icon;
  final double initialBalance;
  final double currentBalance;
  final int? paymentDay;
  final bool isArchived;
  final int sortOrder;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.initialBalance,
    required this.currentBalance,
    this.paymentDay,
    required this.isArchived,
    required this.sortOrder,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      icon: json['icon'] ?? '',
      initialBalance: (json['initial_balance'] ?? 0).toDouble(),
      currentBalance: (json['current_balance'] ?? 0).toDouble(),
      paymentDay: json['payment_day'],
      isArchived: json['is_archived'] ?? false,
      sortOrder: json['sort_order'] ?? 0,
    );
  }

  String get typeDisplay {
    const map = {
      'cash': '现金',
      'bank_card': '银行卡',
      'alipay': '支付宝',
      'wechat': '微信',
      'credit': '信用卡',
      'loan': '贷款',
      'receivable': '应收款',
      'payable': '应付款',
    };
    return map[type] ?? type;
  }

  String get iconEmoji {
    const map = {
      'cash': '💵',
      'bank_card': '🏦',
      'alipay': '📱',
      'wechat': '💬',
      'credit': '💳',
      'loan': '🏠',
      'receivable': '📥',
      'payable': '📤',
    };
    return map[type] ?? '💰';
  }

  bool get isLiability => ['credit', 'loan', 'payable'].contains(type);
}

class AccountListResponse {
  final List<Account> list;
  final double totalAssets;
  final double totalLiabilities;
  final double netAssets;

  AccountListResponse({
    required this.list,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netAssets,
  });

  factory AccountListResponse.fromJson(Map<String, dynamic> json) {
    return AccountListResponse(
      list: (json['list'] as List<dynamic>?)
          ?.map((e) => Account.fromJson(e))
          .toList() ?? [],
      totalAssets: (json['total_assets'] ?? 0).toDouble(),
      totalLiabilities: (json['total_liabilities'] ?? 0).toDouble(),
      netAssets: (json['net_assets'] ?? 0).toDouble(),
    );
  }
}
