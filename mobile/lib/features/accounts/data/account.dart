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
    this.paymentDay,
    this.billingDay,
    this.creditLimit,
    this.interestRate,
    this.totalPaid = 0,
    this.startDate,
    this.targetDate,
    this.paidOffAt,
    this.remark = '',
  });

  final String id;
  final String name;
  final String type;
  final String icon;
  final String color;
  final double initialBalance;
  final double currentBalance;
  final int? paymentDay;
  final int? billingDay;
  final double? creditLimit;
  final double? interestRate;
  final double totalPaid;
  final String? startDate;
  final String? targetDate;
  final String? paidOffAt;
  final String remark;
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
      paymentDay: _toInt(json['payment_day']),
      billingDay: _toInt(json['billing_day']),
      creditLimit: _toNullableDouble(json['credit_limit']),
      interestRate: _toNullableDouble(json['interest_rate']),
      totalPaid: _toDouble(json['total_paid']),
      startDate: _dateOnly(json['start_date']),
      targetDate: _dateOnly(json['target_date']),
      paidOffAt: _dateOnly(json['paid_off_at']),
      remark: json['remark'] as String? ?? '',
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

  static double? _toNullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  static int? _toInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static String? _dateOnly(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
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
    this.paymentDay,
    this.billingDay,
    this.creditLimit,
    this.interestRate,
    this.startDate,
    this.targetDate,
    this.remark = '',
  });

  final String name;
  final String type;
  final String icon;
  final String color;
  final double initialBalance;
  final int? paymentDay;
  final int? billingDay;
  final double? creditLimit;
  final double? interestRate;
  final String? startDate;
  final String? targetDate;
  final String remark;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'name': name,
      'type': type,
      'icon': icon,
      'color': color,
      'initial_balance': initialBalance,
    };
    if (paymentDay != null) {
      data['payment_day'] = paymentDay;
    }
    if (billingDay != null) {
      data['billing_day'] = billingDay;
    }
    if (creditLimit != null) {
      data['credit_limit'] = creditLimit;
    }
    if (interestRate != null) {
      data['interest_rate'] = interestRate;
    }
    if (startDate != null) {
      data['start_date'] = startDate;
    }
    if (targetDate != null) {
      data['target_date'] = targetDate;
    }
    if (remark.isNotEmpty) {
      data['remark'] = remark;
    }
    return data;
  }
}

class UpdateAccountRequest {
  const UpdateAccountRequest({
    required this.name,
    required this.icon,
    required this.color,
    this.paymentDay,
    this.billingDay,
    this.creditLimit,
    this.interestRate,
    this.startDate,
    this.targetDate,
    this.remark = '',
  });

  final String name;
  final String icon;
  final String color;
  final int? paymentDay;
  final int? billingDay;
  final double? creditLimit;
  final double? interestRate;
  final String? startDate;
  final String? targetDate;
  final String remark;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'name': name,
      'icon': icon,
      'color': color,
      'remark': remark,
    };
    if (paymentDay != null) {
      data['payment_day'] = paymentDay;
    }
    if (billingDay != null) {
      data['billing_day'] = billingDay;
    }
    if (creditLimit != null) {
      data['credit_limit'] = creditLimit;
    }
    if (interestRate != null) {
      data['interest_rate'] = interestRate;
    }
    if (startDate != null) {
      data['start_date'] = startDate;
    }
    if (targetDate != null) {
      data['target_date'] = targetDate;
    }
    return data;
  }
}
