import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../statistics/data/statistics_models.dart';

final familyRepositoryProvider = Provider<FamilyRepository>((ref) {
  return FamilyRepository(ref.watch(apiClientProvider));
});

final familyMembersProvider = FutureProvider.autoDispose<List<FamilyMember>>((
  ref,
) {
  return ref.watch(familyRepositoryProvider).listMembers();
});

final familySummaryProvider = FutureProvider.autoDispose<FamilySummary>((ref) {
  return ref.watch(familyRepositoryProvider).getSummary();
});

final familyStatisticsProvider = FutureProvider.autoDispose<FamilyStatistics>((
  ref,
) {
  return ref.watch(familyRepositoryProvider).getStatistics();
});

final familySummaryByPeriodProvider = FutureProvider.autoDispose
    .family<FamilySummary, FamilyPeriodQuery>((ref, query) {
      return ref.watch(familyRepositoryProvider).getSummary(query: query);
    });

final familyStatisticsByPeriodProvider = FutureProvider.autoDispose
    .family<FamilyStatistics, FamilyPeriodQuery>((ref, query) {
      return ref.watch(familyRepositoryProvider).getStatistics(query: query);
    });

class FamilyPeriodQuery {
  const FamilyPeriodQuery({
    required this.month,
    this.period = StatisticsPeriod.month,
  });

  final String month;
  final StatisticsPeriod period;

  @override
  bool operator ==(Object other) {
    return other is FamilyPeriodQuery &&
        other.month == month &&
        other.period == period;
  }

  @override
  int get hashCode => Object.hash(month, period);
}

class FamilyRepository {
  const FamilyRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<FamilyMember>> listMembers() async {
    return await _apiClient.get<List<FamilyMember>>(
          '/family/members',
          fromJsonT: (json) {
            final list = json as List? ?? const [];
            return list
                .whereType<Map<String, dynamic>>()
                .map(FamilyMember.fromJson)
                .toList();
          },
        ) ??
        const [];
  }

  Future<FamilyMember> createMember(FamilyMemberRequest request) async {
    final result = await _apiClient.post<FamilyMember>(
      '/family/members',
      data: request.toJson(),
      fromJsonT: (json) =>
          FamilyMember.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (result == null) {
      throw const FormatException('创建家庭成员响应为空');
    }
    return result;
  }

  Future<FamilyMember> updateMember(
    String id,
    FamilyMemberRequest request,
  ) async {
    final result = await _apiClient.put<FamilyMember>(
      '/family/members/$id',
      data: request.toJson(),
      fromJsonT: (json) =>
          FamilyMember.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (result == null) {
      throw const FormatException('更新家庭成员响应为空');
    }
    return result;
  }

  Future<void> deleteMember(String id) async {
    await _apiClient.delete<void>('/family/members/$id');
  }

  Future<FamilySummary> getSummary({
    String? month,
    FamilyPeriodQuery? query,
  }) async {
    return await _apiClient.get<FamilySummary>(
          '/family/summary',
          queryParameters: _familyPeriodParameters(month: month, query: query),
          fromJsonT: (json) =>
              FamilySummary.fromJson(json as Map<String, dynamic>? ?? const {}),
        ) ??
        const FamilySummary(month: '', totalExpense: 0, members: []);
  }

  Future<FamilyStatistics> getStatistics({
    String? month,
    FamilyPeriodQuery? query,
  }) async {
    return await _apiClient.get<FamilyStatistics>(
          '/family/statistics',
          queryParameters: _familyPeriodParameters(month: month, query: query),
          fromJsonT: (json) => FamilyStatistics.fromJson(
            json as Map<String, dynamic>? ?? const {},
          ),
        ) ??
        const FamilyStatistics(month: '', totalExpense: 0, members: []);
  }
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.relationship,
    required this.color,
    required this.isDefault,
    required this.isEnabled,
    this.avatar = '',
  });

  final String id;
  final String name;
  final String relationship;
  final String avatar;
  final String color;
  final bool isDefault;
  final bool isEnabled;

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      color: json['color'] as String? ?? '',
      isDefault: json['is_default'] as bool? ?? false,
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }
}

class FamilyMemberRequest {
  const FamilyMemberRequest({
    required this.name,
    this.relationship = '',
    this.avatar = '',
    this.color = '#2563EB',
    this.sortOrder,
    this.isDefault = false,
    this.isEnabled = true,
  });

  final String name;
  final String relationship;
  final String avatar;
  final String color;
  final int? sortOrder;
  final bool isDefault;
  final bool isEnabled;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (relationship.isNotEmpty) 'relationship': relationship,
      if (avatar.isNotEmpty) 'avatar': avatar,
      if (color.isNotEmpty) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      'is_default': isDefault,
      'is_enabled': isEnabled,
    };
  }
}

class FamilySummary {
  const FamilySummary({
    required this.month,
    this.period = StatisticsPeriod.month,
    this.label = '',
    required this.totalExpense,
    required this.members,
  });

  final String month;
  final StatisticsPeriod period;
  final String label;
  final double totalExpense;
  final List<FamilyMemberSummary> members;

  factory FamilySummary.fromJson(Map<String, dynamic> json) {
    final members = json['members'] as List? ?? const [];
    return FamilySummary(
      month: json['month'] as String? ?? '',
      period: _parseStatisticsPeriod(json['period']),
      label: json['label'] as String? ?? '',
      totalExpense: _toDouble(json['total_expense']),
      members: members
          .whereType<Map<String, dynamic>>()
          .map(FamilyMemberSummary.fromJson)
          .toList(),
    );
  }
}

class FamilyMemberSummary {
  const FamilyMemberSummary({
    required this.memberId,
    required this.name,
    required this.relationship,
    required this.color,
    required this.expenseTotal,
    required this.count,
  });

  final String memberId;
  final String name;
  final String relationship;
  final String color;
  final double expenseTotal;
  final int count;

  factory FamilyMemberSummary.fromJson(Map<String, dynamic> json) {
    return FamilyMemberSummary(
      memberId: json['member_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      color: json['color'] as String? ?? '',
      expenseTotal: _toDouble(json['expense_total']),
      count: _toInt(json['count']),
    );
  }
}

class FamilyStatistics {
  const FamilyStatistics({
    required this.month,
    this.period = StatisticsPeriod.month,
    this.label = '',
    required this.totalExpense,
    required this.members,
  });

  final String month;
  final StatisticsPeriod period;
  final String label;
  final double totalExpense;
  final List<FamilyStatisticsMember> members;

  factory FamilyStatistics.fromJson(Map<String, dynamic> json) {
    final members = json['members'] as List? ?? const [];
    return FamilyStatistics(
      month: json['month'] as String? ?? '',
      period: _parseStatisticsPeriod(json['period']),
      label: json['label'] as String? ?? '',
      totalExpense: _toDouble(json['total_expense']),
      members: members
          .whereType<Map<String, dynamic>>()
          .map(FamilyStatisticsMember.fromJson)
          .toList(),
    );
  }
}

class FamilyStatisticsMember {
  const FamilyStatisticsMember({
    required this.memberId,
    required this.name,
    required this.relationship,
    required this.color,
    required this.expenseTotal,
    required this.count,
    required this.categories,
  });

  final String memberId;
  final String name;
  final String relationship;
  final String color;
  final double expenseTotal;
  final int count;
  final List<FamilyStatisticsCategory> categories;

  factory FamilyStatisticsMember.fromJson(Map<String, dynamic> json) {
    final categories = json['categories'] as List? ?? const [];
    return FamilyStatisticsMember(
      memberId: json['member_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      color: json['color'] as String? ?? '',
      expenseTotal: _toDouble(json['expense_total']),
      count: _toInt(json['count']),
      categories: categories
          .whereType<Map<String, dynamic>>()
          .map(FamilyStatisticsCategory.fromJson)
          .toList(),
    );
  }
}

class FamilyStatisticsCategory {
  const FamilyStatisticsCategory({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.amount,
    required this.count,
  });

  final String categoryId;
  final String name;
  final String color;
  final double amount;
  final int count;

  factory FamilyStatisticsCategory.fromJson(Map<String, dynamic> json) {
    return FamilyStatisticsCategory(
      categoryId: json['category_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as String? ?? '',
      amount: _toDouble(json['amount']),
      count: _toInt(json['count']),
    );
  }
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? 0;
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value') ?? 0;
}

Map<String, String>? _familyPeriodParameters({
  String? month,
  FamilyPeriodQuery? query,
}) {
  if (query != null) {
    return {'month': query.month, 'period': query.period.apiValue};
  }
  if (month == null || month.isEmpty) {
    return null;
  }
  return {'month': month};
}

StatisticsPeriod _parseStatisticsPeriod(Object? value) {
  final text = value?.toString();
  return StatisticsPeriod.values.firstWhere(
    (period) => period.apiValue == text,
    orElse: () => StatisticsPeriod.month,
  );
}
