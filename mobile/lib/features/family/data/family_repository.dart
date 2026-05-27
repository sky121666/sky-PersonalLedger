import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

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

  Future<FamilySummary> getSummary({String? month}) async {
    return await _apiClient.get<FamilySummary>(
          '/family/summary',
          queryParameters: month == null || month.isEmpty
              ? null
              : {'month': month},
          fromJsonT: (json) =>
              FamilySummary.fromJson(json as Map<String, dynamic>? ?? const {}),
        ) ??
        const FamilySummary(month: '', totalExpense: 0, members: []);
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
  });

  final String id;
  final String name;
  final String relationship;
  final String color;
  final bool isDefault;
  final bool isEnabled;

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      relationship: json['relationship'] as String? ?? '',
      color: json['color'] as String? ?? '',
      isDefault: json['is_default'] as bool? ?? false,
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }
}

class FamilySummary {
  const FamilySummary({
    required this.month,
    required this.totalExpense,
    required this.members,
  });

  final String month;
  final double totalExpense;
  final List<FamilyMemberSummary> members;

  factory FamilySummary.fromJson(Map<String, dynamic> json) {
    final members = json['members'] as List? ?? const [];
    return FamilySummary(
      month: json['month'] as String? ?? '',
      totalExpense: (json['total_expense'] as num?)?.toDouble() ?? 0,
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
      expenseTotal: (json['expense_total'] as num?)?.toDouble() ?? 0,
      count: json['count'] as int? ?? 0,
    );
  }
}
