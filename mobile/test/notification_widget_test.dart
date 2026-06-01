import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/notifications/data/notification_repository.dart';
import 'package:personal_ledger/features/notifications/presentation/notification_settings_page.dart';

void main() {
  group('NotificationSettingsPage', () {
    testWidgets('展示通知总开关、通道和提醒选项', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      expect(find.text('通知设置'), findsWidgets);
      expect(find.text('通知控制台'), findsNothing);
      expect(find.text('Active'), findsNothing);
      expect(find.text('推送中'), findsNothing);
      expect(find.text('通道覆盖率'), findsNothing);
      expect(find.text('25%'), findsNothing);
      expect(
        find.byKey(const ValueKey('notification-delivery-governance-rail')),
        findsNothing,
      );
      expect(find.text('通道覆盖 25%'), findsNothing);
      expect(find.text('可测试'), findsNothing);
      expect(find.text('通道类型'), findsNothing);
      expect(find.text('密钥策略'), findsNothing);
      expect(find.text('测试状态'), findsNothing);
      expect(
        find.byKey(const ValueKey('notification-channel-route-matrix')),
        findsNothing,
      );
      expect(find.text('通道路由矩阵'), findsNothing);
      expect(find.text('Webhook'), findsAtLeastNWidgets(1));
      expect(find.text('可发送'), findsNothing);
      expect(find.text('启用通知'), findsOneWidget);
      final notificationEnabledSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('notification-switch-semantics-启用通知')),
      );
      expect(notificationEnabledSemantics.properties.label, '启用通知');
      expect(find.text('企业微信'), findsWidgets);
      expect(find.text('推送'), findsNothing);
      expect(find.text('还款日提醒'), findsOneWidget);
      final reminderSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('notification-switch-semantics-还款日提醒')),
      );
      expect(reminderSemantics.properties.label, '还款日提醒');
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

    testWidgets('设置加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeNotificationRepository()..getSettingsErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('通知设置加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('启用通知'), findsOneWidget);
      expect(repository.getSettingsCalls, 2);
    });

    testWidgets('保存设置失败时展示错误信息', (tester) async {
      final repository = _FakeNotificationRepository()
        ..updateSettingsError = '保存失败';
      await _pumpPage(tester, repository);

      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(find.textContaining('保存失败'), findsOneWidget);
    });

    testWidgets('企业微信测试失败时展示错误信息', (tester) async {
      final repository = _FakeNotificationRepository()
        ..wecomTestResult = const TestNotificationResult(
          success: false,
          message: 'Webhook 不可用',
        );
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('notification-wecom-webhook')),
        'https://qyapi.example.com/send?key=broken',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送测试消息'));
      await tester.pumpAndSettle();

      expect(repository.wecomTestCalls, [
        'https://qyapi.example.com/send?key=broken',
      ]);
      expect(find.textContaining('Webhook 不可用'), findsOneWidget);
    });

    testWidgets('企业微信测试缺少 Webhook 时使用本地校验', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('notification-wecom-webhook')),
        '',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送测试消息'));
      await tester.pumpAndSettle();

      expect(repository.wecomTestCalls, isEmpty);
      expect(find.text('请填写企业微信 Webhook 地址'), findsOneWidget);
    });

    testWidgets('通知通道密钥输入框默认遮罩显示', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('钉钉'));
      await tester.pumpAndSettle();
      final dingtalkSecret = tester.widget<TextField>(
        find.byKey(const ValueKey('notification-dingtalk-secret')),
      );
      expect(dingtalkSecret.obscureText, isTrue);

      await tester.tap(find.text('Webhook').last);
      await tester.pumpAndSettle();
      final webhookSecret = tester.widget<TextField>(
        find.byKey(const ValueKey('notification-webhook-secret')),
      );
      expect(webhookSecret.obscureText, isTrue);
    });

    testWidgets('通知通道分段按钮可切换当前通道', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('邮箱'));
      await tester.pumpAndSettle();

      expect(find.text('启用邮箱'), findsOneWidget);
      expect(find.text('SMTP 服务器'), findsOneWidget);

      await tester.tap(find.text('Webhook').last);
      await tester.pumpAndSettle();

      expect(find.text('启用 Webhook'), findsOneWidget);
      expect(find.text('Webhook URL'), findsOneWidget);
    });

    testWidgets('通知设置页跟随主题色模板', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final surfaces = tester.widgetList<PremiumSurface>(
        find.byType(PremiumSurface),
      );
      expect(
        surfaces.any(
          (surface) =>
              surface.accentColor == AppThemePalette.graphite.warningColor,
        ),
        isTrue,
      );
    });

    testWidgets('通知设置页使用高级表面和分段入场动效', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository, physicalSize: const Size(1200, 2600));

      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(3));
      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(5));
    });

    test('空通知密钥不会进入更新请求 JSON', () {
      const request = NotificationSettingRequest(
        enabled: true,
        wecomEnabled: false,
        wecomWebhook: '',
        dingtalkEnabled: true,
        dingtalkWebhook: 'https://oapi.example.com/send',
        dingtalkSecret: '',
        emailEnabled: true,
        smtpHost: 'smtp.example.com',
        smtpPort: 587,
        smtpUser: 'user@example.com',
        smtpPassword: '',
        smtpFrom: '',
        emailTo: '',
        webhookEnabled: true,
        webhookUrl: 'https://example.com/webhook',
        webhookSecret: '',
        notifyPaymentDue: true,
        notifyBudgetAlert: true,
        notifyLendingDue: true,
        notifyAnnualReport: true,
        advanceDays: 3,
      );

      final payload = request.toJson();

      expect(payload, isNot(contains('dingtalk_secret')));
      expect(payload, isNot(contains('smtp_password')));
      expect(payload, isNot(contains('webhook_secret')));
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeNotificationRepository repository, {
  AppThemePalette palette = AppThemePalette.teal,
  Size physicalSize = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: const NotificationSettingsPage(),
      ),
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
  int getSettingsCalls = 0;
  int getSettingsErrors = 0;
  String? updateSettingsError;
  TestNotificationResult wecomTestResult = const TestNotificationResult(
    success: true,
    message: '发送成功',
  );

  @override
  Future<NotificationSetting?> getSettings() async {
    getSettingsCalls += 1;
    if (getSettingsErrors > 0) {
      getSettingsErrors -= 1;
      throw StateError('通知设置加载失败');
    }
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
    return wecomTestResult;
  }

  @override
  Future<NotificationSetting?> updateSettings(
    NotificationSettingRequest request,
  ) async {
    updateCalls.add(request);
    final error = updateSettingsError;
    if (error != null) {
      throw StateError(error);
    }
    settings = settings.copyWith(
      enabled: request.enabled,
      notifyBudgetAlert: request.notifyBudgetAlert,
      advanceDays: request.advanceDays,
    );
    return settings;
  }
}
