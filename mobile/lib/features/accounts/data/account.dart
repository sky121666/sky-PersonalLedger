class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.initialBalance,
    required this.currentBalance,
    required this.isArchived,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String type;
  final String icon;
  final String color;
  final double initialBalance;
  final double currentBalance;
  final bool isArchived;
  final int sortOrder;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'cash',
      icon: json['icon'] as String? ?? '💰',
      color: json['color'] as String? ?? '#3B82F6',
      initialBalance: _toDouble(json['initial_balance']),
      currentBalance: _toDouble(json['current_balance']),
      isArchived: json['is_archived'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class AccountListResult {
  const AccountListResult({
    required this.accounts,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netAssets,
  });

  final List<Account> accounts;
  final double totalAssets;
  final double totalLiabilities;
  final double netAssets;

  factory AccountListResult.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'];
    return AccountListResult(
      accounts: rawList is List
          ? rawList
                .whereType<Map<String, dynamic>>()
                .map(Account.fromJson)
                .toList()
          : const [],
      totalAssets: Account._toDouble(json['total_assets']),
      totalLiabilities: Account._toDouble(json['total_liabilities']),
      netAssets: Account._toDouble(json['net_assets']),
    );
  }
}

class CreateAccountRequest {
  const CreateAccountRequest({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.initialBalance,
  });

  final String name;
  final String type;
  final String icon;
  final String color;
  final double initialBalance;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'icon': icon,
      'color': color,
      'initial_balance': initialBalance,
    };
  }
}

class UpdateAccountRequest {
  const UpdateAccountRequest({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final String icon;
  final String color;

  Map<String, dynamic> toJson() {
    return {'name': name, 'icon': icon, 'color': color};
  }
}
