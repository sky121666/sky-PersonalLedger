import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

final aiReportRepositoryProvider = Provider<AIReportRepository>((ref) {
  return AIReportRepository(ref.watch(apiClientProvider));
});

final aiReportsProvider = FutureProvider.autoDispose<List<AIReportSummary>>((
  ref,
) {
  return ref.watch(aiReportRepositoryProvider).listReports();
});

class AIReportRepository {
  const AIReportRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<AIReportSummary>> listReports() async {
    return await _apiClient.get<List<AIReportSummary>>(
          '/ai/reports',
          fromJsonT: (json) {
            final list = json as List? ?? const [];
            return list
                .whereType<Map<String, dynamic>>()
                .map(AIReportSummary.fromJson)
                .toList();
          },
        ) ??
        const [];
  }

  Future<AIReportSummary> generateReport(
    GenerateAIReportRequest request,
  ) async {
    final report = await _apiClient.post<AIReportSummary>(
      '/ai/reports/generate',
      data: request.toJson(),
      fromJsonT: (json) =>
          AIReportSummary.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (report == null) {
      throw StateError('AI 报告响应为空');
    }
    return report;
  }
}

class GenerateAIReportRequest {
  const GenerateAIReportRequest({
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    this.providerId,
  });

  final String reportType;
  final String periodStart;
  final String periodEnd;
  final String? providerId;

  Map<String, dynamic> toJson() {
    return {
      'report_type': reportType,
      'period_start': periodStart,
      'period_end': periodEnd,
      if (providerId != null && providerId!.isNotEmpty)
        'provider_id': providerId,
    };
  }
}

class AIReportSummary {
  const AIReportSummary({
    required this.id,
    required this.reportType,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    required this.providerName,
    required this.model,
    this.contentJson = '',
    this.errorMessage = '',
  });

  final String id;
  final String reportType;
  final String status;
  final String periodStart;
  final String periodEnd;
  final String providerName;
  final String model;
  final String contentJson;
  final String errorMessage;

  factory AIReportSummary.fromJson(Map<String, dynamic> json) {
    return AIReportSummary(
      id: json['id'] as String? ?? '',
      reportType: json['report_type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      periodStart: json['period_start'] as String? ?? '',
      periodEnd: json['period_end'] as String? ?? '',
      providerName: json['provider_name'] as String? ?? '',
      model: json['model'] as String? ?? '',
      contentJson: json['content_json'] as String? ?? '',
      errorMessage: json['error_message'] as String? ?? '',
    );
  }
}
