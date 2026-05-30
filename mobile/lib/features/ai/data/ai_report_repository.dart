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

final aiReportScheduleProvider =
    FutureProvider.autoDispose<AIReportScheduleSettings>((ref) {
      return ref.watch(aiReportRepositoryProvider).getScheduleSettings();
    });

final aiProviderSetupProvider = FutureProvider.autoDispose<AIProviderSetupData>(
  (ref) async {
    final repository = ref.watch(aiReportRepositoryProvider);
    final presets = await repository.listProviderPresets();
    final providers = await repository.listProviders();
    return AIProviderSetupData(presets: presets, providers: providers);
  },
);

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

  Future<AIReportScheduleSettings> getScheduleSettings() async {
    final settings = await _apiClient.get<AIReportScheduleSettings>(
      '/ai/schedule/settings',
      fromJsonT: (json) => AIReportScheduleSettings.fromJson(
        json as Map<String, dynamic>? ?? const {},
      ),
    );
    return settings ?? const AIReportScheduleSettings();
  }

  Future<AIReportScheduleSettings> updateScheduleSettings(
    AIReportScheduleSettings settings,
  ) async {
    final saved = await _apiClient.put<AIReportScheduleSettings>(
      '/ai/schedule/settings',
      data: settings.toJson(),
      fromJsonT: (json) => AIReportScheduleSettings.fromJson(
        json as Map<String, dynamic>? ?? const {},
      ),
    );
    return saved ?? settings;
  }

  Future<List<AIReportScheduleRunResult>> triggerSchedule() async {
    final results = await _apiClient.post<List<AIReportScheduleRunResult>>(
      '/ai/schedule/trigger',
      fromJsonT: (json) {
        final payload = json as Map<String, dynamic>? ?? const {};
        final list = payload['results'] as List? ?? const [];
        return list
            .whereType<Map<String, dynamic>>()
            .map(AIReportScheduleRunResult.fromJson)
            .toList();
      },
    );
    return results ?? const [];
  }

  Future<List<AIProviderPreset>> listProviderPresets() async {
    return await _apiClient.get<List<AIProviderPreset>>(
          '/ai/providers/presets',
          fromJsonT: (json) {
            final list = json as List? ?? const [];
            return list
                .whereType<Map<String, dynamic>>()
                .map(AIProviderPreset.fromJson)
                .toList();
          },
        ) ??
        const [];
  }

  Future<List<AIProviderSummary>> listProviders() async {
    return await _apiClient.get<List<AIProviderSummary>>(
          '/ai/providers',
          fromJsonT: (json) {
            final list = json as List? ?? const [];
            return list
                .whereType<Map<String, dynamic>>()
                .map(AIProviderSummary.fromJson)
                .toList();
          },
        ) ??
        const [];
  }

  Future<AIProviderSummary> createProvider(
    SaveAIProviderRequest request,
  ) async {
    final provider = await _apiClient.post<AIProviderSummary>(
      '/ai/providers',
      data: request.toJson(),
      fromJsonT: (json) =>
          AIProviderSummary.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (provider == null) {
      throw StateError('Provider 响应为空');
    }
    return provider;
  }

  Future<AIProviderSummary> updateProvider(
    String id,
    SaveAIProviderRequest request,
  ) async {
    final provider = await _apiClient.put<AIProviderSummary>(
      '/ai/providers/$id',
      data: request.toJson(),
      fromJsonT: (json) =>
          AIProviderSummary.fromJson(json as Map<String, dynamic>? ?? const {}),
    );
    if (provider == null) {
      throw StateError('Provider 响应为空');
    }
    return provider;
  }

  Future<void> deleteProvider(String id) async {
    await _apiClient.delete<void>('/ai/providers/$id');
  }

  Future<void> testProvider(String id) async {
    await _apiClient.post<void>('/ai/providers/$id/test');
  }
}

class AIProviderSetupData {
  const AIProviderSetupData({required this.presets, required this.providers});

  final List<AIProviderPreset> presets;
  final List<AIProviderSummary> providers;
}

class AIProviderPreset {
  const AIProviderPreset({
    required this.id,
    required this.name,
    required this.providerType,
    required this.baseUrl,
    required this.model,
    required this.models,
  });

  final String id;
  final String name;
  final String providerType;
  final String baseUrl;
  final String model;
  final List<String> models;

  factory AIProviderPreset.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'] as List? ?? const [];
    return AIProviderPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      providerType: json['provider_type'] as String? ?? 'openai_compatible',
      baseUrl: json['base_url'] as String? ?? '',
      model: json['model'] as String? ?? '',
      models: rawModels.map((item) => '$item').toList(),
    );
  }
}

class AIProviderSummary {
  const AIProviderSummary({
    required this.id,
    required this.name,
    required this.providerType,
    required this.baseUrl,
    required this.model,
    required this.enabled,
  });

  final String id;
  final String name;
  final String providerType;
  final String baseUrl;
  final String model;
  final bool enabled;

  factory AIProviderSummary.fromJson(Map<String, dynamic> json) {
    return AIProviderSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      providerType: json['provider_type'] as String? ?? 'openai_compatible',
      baseUrl: json['base_url'] as String? ?? '',
      model: json['model'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}

class SaveAIProviderRequest {
  const SaveAIProviderRequest({
    required this.name,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.providerType = 'openai_compatible',
    this.enabled = true,
  });

  final String name;
  final String providerType;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool enabled;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'provider_type': providerType,
      'base_url': baseUrl,
      'api_key': apiKey,
      'model': model,
      'enabled': enabled,
    };
  }
}

class GenerateAIReportRequest {
  const GenerateAIReportRequest({
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    this.providerId,
    this.maskNames = true,
  });

  final String reportType;
  final String periodStart;
  final String periodEnd;
  final String? providerId;
  final bool maskNames;

  Map<String, dynamic> toJson() {
    return {
      'report_type': reportType,
      'period_start': periodStart,
      'period_end': periodEnd,
      'mask_names': maskNames,
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
    this.snapshotJson = '',
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
  final String snapshotJson;
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
      snapshotJson: json['snapshot_json'] as String? ?? '',
      errorMessage: json['error_message'] as String? ?? '',
    );
  }
}

class AIReportScheduleSettings {
  const AIReportScheduleSettings({
    this.enabled = false,
    this.weeklyEnabled = true,
    this.monthlyEnabled = true,
    this.hour = 8,
    this.lastWeeklyRun = '',
    this.lastMonthlyRun = '',
  });

  final bool enabled;
  final bool weeklyEnabled;
  final bool monthlyEnabled;
  final int hour;
  final String lastWeeklyRun;
  final String lastMonthlyRun;

  AIReportScheduleSettings copyWith({
    bool? enabled,
    bool? weeklyEnabled,
    bool? monthlyEnabled,
    int? hour,
    String? lastWeeklyRun,
    String? lastMonthlyRun,
  }) {
    return AIReportScheduleSettings(
      enabled: enabled ?? this.enabled,
      weeklyEnabled: weeklyEnabled ?? this.weeklyEnabled,
      monthlyEnabled: monthlyEnabled ?? this.monthlyEnabled,
      hour: hour ?? this.hour,
      lastWeeklyRun: lastWeeklyRun ?? this.lastWeeklyRun,
      lastMonthlyRun: lastMonthlyRun ?? this.lastMonthlyRun,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'weekly_enabled': weeklyEnabled,
      'monthly_enabled': monthlyEnabled,
      'hour': hour,
      if (lastWeeklyRun.isNotEmpty) 'last_weekly_run': lastWeeklyRun,
      if (lastMonthlyRun.isNotEmpty) 'last_monthly_run': lastMonthlyRun,
    };
  }

  factory AIReportScheduleSettings.fromJson(Map<String, dynamic> json) {
    return AIReportScheduleSettings(
      enabled: json['enabled'] as bool? ?? false,
      weeklyEnabled: json['weekly_enabled'] as bool? ?? true,
      monthlyEnabled: json['monthly_enabled'] as bool? ?? true,
      hour: json['hour'] as int? ?? 8,
      lastWeeklyRun: json['last_weekly_run'] as String? ?? '',
      lastMonthlyRun: json['last_monthly_run'] as String? ?? '',
    );
  }
}

class AIReportScheduleRunResult {
  const AIReportScheduleRunResult({
    required this.reportType,
    required this.periodStart,
    required this.periodEnd,
    this.attempted = 0,
    this.succeeded = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  final String reportType;
  final String periodStart;
  final String periodEnd;
  final int attempted;
  final int succeeded;
  final int skipped;
  final int failed;

  factory AIReportScheduleRunResult.fromJson(Map<String, dynamic> json) {
    return AIReportScheduleRunResult(
      reportType: json['report_type'] as String? ?? '',
      periodStart: json['period_start'] as String? ?? '',
      periodEnd: json['period_end'] as String? ?? '',
      attempted: json['attempted'] as int? ?? 0,
      succeeded: json['succeeded'] as int? ?? 0,
      skipped: json['skipped'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
    );
  }
}
