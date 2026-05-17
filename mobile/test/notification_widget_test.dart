import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/notifications/data/notification_repository.dart';
import 'package:personal_ledger/features/notifications/presentation/notification_settings_page.dart';

void main() {
  group('NotificationSettingsPage', () {
    testWidgets('展示通知总开关、通道和提醒选项', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      expect(find.text('通知设置'), findsOneWidget);
      expect(find.text('启用通知'), findsOneWidget);
      expect(find.text('企业微信'), findsWidgets);
      expect(find.text('还款日提醒'), findsOneWidget);
      expect(find.text('提前 3 天提醒'), findsOneWidget);
    });

    testWidgets('保存设置时提交当前开关和提醒选项', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const ValueKey('notification-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-budget-alert')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.enabled, isFalse);
      expect(repository.updateCalls.single.notifyBudgetAlert, isFalse);
      expect(repository.updateCalls.single.advanceDays, 3);
    });

    testWidgets('发送企业微信测试消息时使用当前 Webhook', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('notification-wecom-webhook')),
        'https://qyapi.example.com/send?key=test',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送测试消息'));
      await tester.pumpAndSettle();

      expect(repository.wecomTestCalls, [
        'https://qyapi.example.com/send?key=test',
      ]);
      expect(find.text('测试成功'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeNotificationRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: NotificationSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeNotificationRepository implements NotificationRepository {
  NotificationSetting settings = const NotificationSetting(
    id: 1,
    userId: 1,
    enabled: true,
    wecomEnabled: true,
    wecomWebhook: 'https://qyapi.example.com/send?key=old',
    dingtalkEnabled: false,
    dingtalkWebhook: '',
    dingtalkSecret: '',
    emailEnabled: false,
    smtpHost: '',
    smtpPort: 587,
    smtpUser: '',
    smtpFrom: '',
    emailTo: '',
    webhookEnabled: false,
    webhookUrl: '',
    webhookSecret: '',
    notifyPaymentDue: true,
    notifyBudgetAlert: true,
    notifyLendingDue: true,
    notifyAnnualReport: true,
    advanceDays: 3,
  );

  final List<NotificationSettingRequest> updateCalls = [];
  final List<String> wecomTestCalls = [];

  @override
  Future<NotificationSetting?> getSettings() async {
    return settings;
  }

  @override
  Future<TestNotificationResult?> testDingtalk({
    required String webhook,
    String secret = '',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<TestNotificationResult?> testEmail({
    required String smtpHost,
    required int smtpPort,
    required String smtpUser,
    String smtpPassword = '',
    String smtpFrom = '',
    String emailTo = '',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<TestNotificationResult?> testWebhook({
    required String url,
    String secret = '',
  }) {
    throw UnimplementedError();
  }

  @override
  Future<TestNotificationResult?> testWecom(String webhook) async {
    wecomTestCalls.add(webhook);
    return const TestNotificationResult(success: true, message: '发送成功');
  }

  @override
  Future<NotificationSetting?> updateSettings(
    NotificationSettingRequest request,
  ) async {
    updateCalls.add(request);
    settings = settings.copyWith(
      enabled: request.enabled,
      notifyBudgetAlert: request.notifyBudgetAlert,
      advanceDays: request.advanceDays,
    );
    return settings;
  }
}
