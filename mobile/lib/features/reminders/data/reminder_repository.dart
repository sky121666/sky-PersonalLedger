import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../accounts/application/account_controller.dart';
import '../../accounts/data/account.dart';

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ReminderRepository(ref.watch(apiClientProvider));
});

final reminderDashboardProvider = FutureProvider.autoDispose<ReminderDashboard>(
  (ref) async {
    final results = await Future.wait<Object?>([
      ref.watch(reminderRepositoryProvider).listReminders(),
      ref.watch(reminderRepositoryProvider).getDebtSummary(),
      ref.watch(accountRepositoryProvider).list(includeArchived: false),
    ]);

    return ReminderDashboard(
      reminders: results[0] as List<ReminderItem>? ?? const [],
      summary: results[1] as DebtSummary? ?? const DebtSummary.empty(),
      accounts:
          (results[2] as AccountListResult?)?.accounts ?? const <Account>[],
    );
  },
);

class ReminderRepository {
  const ReminderRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ReminderItem>?> listReminders({String? accountId}) {
    return _apiClient.get<List<ReminderItem>>(
      '/reminders',
      queryParameters: accountId == null ? null : {'account_id': accountId},
      fromJsonT: (json) {
        if (json is! List) {
          throw const FormatException('提醒列表响应格式不正确');
        }
        return json.map(ReminderItem.fromJson).toList();
      },
    );
  }

  Future<DebtSummary?> getDebtSummary() {
    return _apiClient.get<DebtSummary>(
      '/debt/summary',
      fromJsonT: DebtSummary.fromJson,
    );
  }

  Future<ReminderItem?> toggleReminder(String id) {
    return _apiClient.patch<ReminderItem>(
      '/reminders/$id/toggle',
      fromJsonT: ReminderItem.fromJson,
    );
  }

  Future<void> deleteReminder(String id) async {
    await _apiClient.delete<void>('/reminders/$id');
  }

  Future<ReminderItem?> recordPayment(
    String id, {
    required double amount,
    String? accountId,
    double? principalAmount,
    double? interestAmount,
  }) {
    return _apiClient.post<ReminderItem>(
      '/reminders/$id/payment',
      data: {
        'amount': amount,
        if (accountId != null && accountId.isNotEmpty) 'account_id': accountId,
        if (principalAmount != null && principalAmount > 0)
          'principal_amount': principalAmount,
        if (interestAmount != null && interestAmount > 0)
          'interest_amount': interestAmount,
      },
      fromJsonT: ReminderItem.fromJson,
    );
  }
}

class ReminderDashboard {
  const ReminderDashboard({
    required this.reminders,
    required this.summary,
    required this.accounts,
  });

  final List<ReminderItem> reminders;
  final DebtSummary summary;
  final List<Account> accounts;

  List<ReminderItem> get activeReminders {
    return reminders
        .where((item) => item.isEnabled && item.paidOffAt == null)
        .toList();
  }

  List<ReminderItem> get inactiveReminders {
    return reminders
        .where((item) => !item.isEnabled && item.paidOffAt == null)
        .toList();
  }

  List<ReminderItem> get paidOffReminders {
    return reminders.where((item) => item.paidOffAt != null).toList();
  }

  List<Account> get paymentAccounts {
    return accounts
        .where(
          (account) =>
              !account.isArchived && !_debtAccountTypes.contains(account.type),
        )
        .toList();
  }
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.name,
    required this.accountId,
    required this.accountName,
    required this.loanType,
    required this.paymentDay,
    required this.billingDay,
    required this.advanceDays,
    required this.amount,
    required this.principal,
    required this.currentBalance,
    required this.interestRate,
    required this.totalInterest,
    required this.totalPaid,
    required this.interestPaid,
    required this.startDate,
    required this.targetDate,
    required this.paidOffAt,
    required this.color,
    required this.remark,
    required this.isEnabled,
  });

  final String id;
  final String name;
  final String? accountId;
  final String accountName;
  final String loanType;
  final int paymentDay;
  final int? billingDay;
  final int advanceDays;
  final double? amount;
  final double? principal;
  final double? currentBalance;
  final double? interestRate;
  final double? totalInterest;
  final double totalPaid;
  final double interestPaid;
  final String? startDate;
  final String? targetDate;
  final String? paidOffAt;
  final String color;
  final String remark;
  final bool isEnabled;

  String get displayName {
    if (name.trim().isNotEmpty) {
      return name;
    }
    return loanTypeLabel;
  }

  String get loanTypeLabel {
    return switch (loanType) {
      'credit_card' => '信用卡',
      'mortgage' => '房贷',
      'car_loan' => '车贷',
      'consumer_loan' => '消费贷',
      _ => '其他负债',
    };
  }

  double get progress {
    final principalValue = principal ?? 0;
    final balanceValue = currentBalance ?? 0;
    if (principalValue <= 0) {
      return 0;
    }
    return (((principalValue - balanceValue) / principalValue) * 100)
        .clamp(0, 100)
        .toDouble();
  }

  int daysUntilPayment(DateTime now) {
    final today = now.day;
    if (paymentDay >= today) {
      return paymentDay - today;
    }
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return daysInMonth - today + paymentDay;
  }

  factory ReminderItem.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('提醒响应格式不正确');
    }

    final account = json['account'];
    final accountMap = account is Map<String, dynamic> ? account : null;
    return ReminderItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      accountId: json['account_id'] as String?,
      accountName: accountMap?['name'] as String? ?? '',
      loanType: json['loan_type'] as String? ?? 'other',
      paymentDay: _toInt(json['payment_day'], fallback: 1).clamp(1, 31),
      billingDay: _nullableInt(json['billing_day']),
      advanceDays: _toInt(json['advance_days'], fallback: 3),
      amount: _nullableDouble(json['amount']),
      principal: _nullableDouble(json['principal']),
      currentBalance: _nullableDouble(json['current_balance']),
      interestRate: _nullableDouble(json['interest_rate']),
      totalInterest: _nullableDouble(json['total_interest']),
      totalPaid: _toDouble(json['total_paid']),
      interestPaid: _toDouble(json['interest_paid']),
      startDate: json['start_date'] as String?,
      targetDate: json['target_date'] as String?,
      paidOffAt: json['paid_off_at'] as String?,
      color: json['color'] as String? ?? '#3B82F6',
      remark: json['remark'] as String? ?? '',
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }
}

class DebtSummary {
  const DebtSummary({
    required this.totalDebt,
    required this.totalPaid,
    required this.totalPrincipal,
    required this.progress,
    required this.activeLoans,
    required this.paidOffLoans,
    required this.nextPaymentDay,
    required this.nextPaymentName,
    required this.daysUntilNext,
  });

  const DebtSummary.empty()
    : totalDebt = 0,
      totalPaid = 0,
      totalPrincipal = 0,
      progress = 0,
      activeLoans = 0,
      paidOffLoans = 0,
      nextPaymentDay = 0,
      nextPaymentName = '',
      daysUntilNext = 0;

  final double totalDebt;
  final double totalPaid;
  final double totalPrincipal;
  final double progress;
  final int activeLoans;
  final int paidOffLoans;
  final int nextPaymentDay;
  final String nextPaymentName;
  final int daysUntilNext;

  factory DebtSummary.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('负债摘要响应格式不正确');
    }

    return DebtSummary(
      totalDebt: _toDouble(json['total_debt']),
      totalPaid: _toDouble(json['total_paid']),
      totalPrincipal: _toDouble(json['total_principal']),
      progress: _toDouble(json['progress']),
      activeLoans: _toInt(json['active_loans']),
      paidOffLoans: _toInt(json['paid_off_loans']),
      nextPaymentDay: _toInt(json['next_payment_day']),
      nextPaymentName: json['next_payment_name'] as String? ?? '',
      daysUntilNext: _toInt(json['days_until_next']),
    );
  }
}

const _debtAccountTypes = <String>{
  'credit',
  'loan',
  'mortgage',
  'car_loan',
  'consumer_loan',
  'huabei',
  'baitiao',
  'other_debt',
};

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

double? _nullableDouble(Object? value) {
  if (value == null) {
    return null;
  }
  return _toDouble(value);
}

int _toInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  return _toInt(value);
}
