import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/core_providers.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider));
});

final notificationSettingsProvider =
    FutureProvider.autoDispose<NotificationSetting>((ref) async {
      return await ref.watch(notificationRepositoryProvider).getSettings() ??
          const NotificationSetting.defaults();
    });

class NotificationRepository {
  const NotificationRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<NotificationSetting?> getSettings() {
    return _apiClient.get<NotificationSetting>(
      '/notifications/settings',
      fromJsonT: NotificationSetting.fromJson,
    );
  }

  Future<NotificationSetting?> updateSettings(
    NotificationSettingRequest request,
  ) {
    return _apiClient.put<NotificationSetting>(
      '/notifications/settings',
      data: request.toJson(),
      fromJsonT: NotificationSetting.fromJson,
    );
  }

  Future<TestNotificationResult?> testWecom(String webhook) {
    return _apiClient.post<TestNotificationResult>(
      '/notifications/test/wecom',
      data: {'webhook': webhook},
      fromJsonT: TestNotificationResult.fromJson,
    );
  }

  Future<TestNotificationResult?> testDingtalk({
    required String webhook,
    String secret = '',
  }) {
    return _apiClient.post<TestNotificationResult>(
      '/notifications/test/dingtalk',
      data: {'webhook': webhook, 'secret': secret},
      fromJsonT: TestNotificationResult.fromJson,
    );
  }

  Future<TestNotificationResult?> testEmail({
    required String smtpHost,
    required int smtpPort,
    required String smtpUser,
    String smtpPassword = '',
    String smtpFrom = '',
    String emailTo = '',
  }) {
    return _apiClient.post<TestNotificationResult>(
      '/notifications/test/email',
      data: {
        'smtp_host': smtpHost,
        'smtp_port': smtpPort,
        'smtp_user': smtpUser,
        'smtp_password': smtpPassword,
        'smtp_from': smtpFrom,
        'email_to': emailTo,
      },
      fromJsonT: TestNotificationResult.fromJson,
    );
  }

  Future<TestNotificationResult?> testWebhook({
    required String url,
    String secret = '',
  }) {
    return _apiClient.post<TestNotificationResult>(
      '/notifications/test/webhook',
      data: {'url': url, 'secret': secret},
      fromJsonT: TestNotificationResult.fromJson,
    );
  }
}

class NotificationSetting {
  const NotificationSetting({
    required this.id,
    required this.userId,
    required this.enabled,
    required this.wecomEnabled,
    required this.wecomWebhook,
    required this.dingtalkEnabled,
    required this.dingtalkWebhook,
    required this.dingtalkSecret,
    required this.emailEnabled,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpFrom,
    required this.emailTo,
    required this.webhookEnabled,
    required this.webhookUrl,
    required this.webhookSecret,
    required this.notifyPaymentDue,
    required this.notifyBudgetAlert,
    required this.notifyLendingDue,
    required this.notifyAnnualReport,
    required this.advanceDays,
  });

  const NotificationSetting.defaults()
    : id = 0,
      userId = 0,
      enabled = false,
      wecomEnabled = false,
      wecomWebhook = '',
      dingtalkEnabled = false,
      dingtalkWebhook = '',
      dingtalkSecret = '',
      emailEnabled = false,
      smtpHost = '',
      smtpPort = 587,
      smtpUser = '',
      smtpFrom = '',
      emailTo = '',
      webhookEnabled = false,
      webhookUrl = '',
      webhookSecret = '',
      notifyPaymentDue = true,
      notifyBudgetAlert = true,
      notifyLendingDue = true,
      notifyAnnualReport = true,
      advanceDays = 3;

  final int id;
  final int userId;
  final bool enabled;
  final bool wecomEnabled;
  final String wecomWebhook;
  final bool dingtalkEnabled;
  final String dingtalkWebhook;
  final String dingtalkSecret;
  final bool emailEnabled;
  final String smtpHost;
  final int smtpPort;
  final String smtpUser;
  final String smtpFrom;
  final String emailTo;
  final bool webhookEnabled;
  final String webhookUrl;
  final String webhookSecret;
  final bool notifyPaymentDue;
  final bool notifyBudgetAlert;
  final bool notifyLendingDue;
  final bool notifyAnnualReport;
  final int advanceDays;

  NotificationSetting copyWith({
    bool? enabled,
    bool? wecomEnabled,
    String? wecomWebhook,
    bool? dingtalkEnabled,
    String? dingtalkWebhook,
    String? dingtalkSecret,
    bool? emailEnabled,
    String? smtpHost,
    int? smtpPort,
    String? smtpUser,
    String? smtpFrom,
    String? emailTo,
    bool? webhookEnabled,
    String? webhookUrl,
    String? webhookSecret,
    bool? notifyPaymentDue,
    bool? notifyBudgetAlert,
    bool? notifyLendingDue,
    bool? notifyAnnualReport,
    int? advanceDays,
  }) {
    return NotificationSetting(
      id: id,
      userId: userId,
      enabled: enabled ?? this.enabled,
      wecomEnabled: wecomEnabled ?? this.wecomEnabled,
      wecomWebhook: wecomWebhook ?? this.wecomWebhook,
      dingtalkEnabled: dingtalkEnabled ?? this.dingtalkEnabled,
      dingtalkWebhook: dingtalkWebhook ?? this.dingtalkWebhook,
      dingtalkSecret: dingtalkSecret ?? this.dingtalkSecret,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpUser: smtpUser ?? this.smtpUser,
      smtpFrom: smtpFrom ?? this.smtpFrom,
      emailTo: emailTo ?? this.emailTo,
      webhookEnabled: webhookEnabled ?? this.webhookEnabled,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      webhookSecret: webhookSecret ?? this.webhookSecret,
      notifyPaymentDue: notifyPaymentDue ?? this.notifyPaymentDue,
      notifyBudgetAlert: notifyBudgetAlert ?? this.notifyBudgetAlert,
      notifyLendingDue: notifyLendingDue ?? this.notifyLendingDue,
      notifyAnnualReport: notifyAnnualReport ?? this.notifyAnnualReport,
      advanceDays: advanceDays ?? this.advanceDays,
    );
  }

  factory NotificationSetting.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('通知设置响应格式不正确');
    }
    return NotificationSetting(
      id: _toInt(json['id']),
      userId: _toInt(json['user_id']),
      enabled: json['enabled'] as bool? ?? false,
      wecomEnabled: json['wecom_enabled'] as bool? ?? false,
      wecomWebhook: json['wecom_webhook'] as String? ?? '',
      dingtalkEnabled: json['dingtalk_enabled'] as bool? ?? false,
      dingtalkWebhook: json['dingtalk_webhook'] as String? ?? '',
      dingtalkSecret: json['dingtalk_secret'] as String? ?? '',
      emailEnabled: json['email_enabled'] as bool? ?? false,
      smtpHost: json['smtp_host'] as String? ?? '',
      smtpPort: _toInt(json['smtp_port'], fallback: 587),
      smtpUser: json['smtp_user'] as String? ?? '',
      smtpFrom: json['smtp_from'] as String? ?? '',
      emailTo: json['email_to'] as String? ?? '',
      webhookEnabled: json['webhook_enabled'] as bool? ?? false,
      webhookUrl: json['webhook_url'] as String? ?? '',
      webhookSecret: json['webhook_secret'] as String? ?? '',
      notifyPaymentDue: json['notify_payment_due'] as bool? ?? true,
      notifyBudgetAlert: json['notify_budget_alert'] as bool? ?? true,
      notifyLendingDue: json['notify_lending_due'] as bool? ?? true,
      notifyAnnualReport: json['notify_annual_report'] as bool? ?? true,
      advanceDays: _toInt(json['advance_days'], fallback: 3),
    );
  }
}

class NotificationSettingRequest {
  const NotificationSettingRequest({
    required this.enabled,
    required this.wecomEnabled,
    required this.wecomWebhook,
    required this.dingtalkEnabled,
    required this.dingtalkWebhook,
    required this.dingtalkSecret,
    required this.emailEnabled,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPassword,
    required this.smtpFrom,
    required this.emailTo,
    required this.webhookEnabled,
    required this.webhookUrl,
    required this.webhookSecret,
    required this.notifyPaymentDue,
    required this.notifyBudgetAlert,
    required this.notifyLendingDue,
    required this.notifyAnnualReport,
    required this.advanceDays,
  });

  final bool enabled;
  final bool wecomEnabled;
  final String wecomWebhook;
  final bool dingtalkEnabled;
  final String dingtalkWebhook;
  final String dingtalkSecret;
  final bool emailEnabled;
  final String smtpHost;
  final int smtpPort;
  final String smtpUser;
  final String smtpPassword;
  final String smtpFrom;
  final String emailTo;
  final bool webhookEnabled;
  final String webhookUrl;
  final String webhookSecret;
  final bool notifyPaymentDue;
  final bool notifyBudgetAlert;
  final bool notifyLendingDue;
  final bool notifyAnnualReport;
  final int advanceDays;

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'wecom_enabled': wecomEnabled,
      'wecom_webhook': wecomWebhook,
      'dingtalk_enabled': dingtalkEnabled,
      'dingtalk_webhook': dingtalkWebhook,
      'dingtalk_secret': dingtalkSecret,
      'email_enabled': emailEnabled,
      'smtp_host': smtpHost,
      'smtp_port': smtpPort,
      'smtp_user': smtpUser,
      if (smtpPassword.isNotEmpty) 'smtp_password': smtpPassword,
      'smtp_from': smtpFrom,
      'email_to': emailTo,
      'webhook_enabled': webhookEnabled,
      'webhook_url': webhookUrl,
      'webhook_secret': webhookSecret,
      'notify_payment_due': notifyPaymentDue,
      'notify_budget_alert': notifyBudgetAlert,
      'notify_lending_due': notifyLendingDue,
      'notify_annual_report': notifyAnnualReport,
      'advance_days': advanceDays,
    };
  }
}

class TestNotificationResult {
  const TestNotificationResult({required this.success, required this.message});

  final bool success;
  final String message;

  factory TestNotificationResult.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('通知测试响应格式不正确');
    }
    return TestNotificationResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }
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
