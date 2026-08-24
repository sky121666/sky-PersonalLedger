import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
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
      expect(find.text('Webhook'), findsNothing);
      expect(find.text('其他通道'), findsOneWidget);
      expect(find.text('邮件服务器'), findsNothing);
      expect(find.text('发送地址'), findsNothing);
      expect(find.text('通知地址'), findsWidgets);
      expect(find.text('可发送'), findsNothing);
      expect(find.text('启用通知'), findsOneWidget);
      final notificationEnabledSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('notification-switch-semantics-启用通知')),
      );
      expect(notificationEnabledSemantics.properties.label, '启用通知');
      expect(find.text('企业微信'), findsWidgets);
      final writeOnlyEndpoint = tester.widget<TextField>(
        find.byKey(const ValueKey('notification-wecom-webhook')),
      );
      expect(writeOnlyEndpoint.controller?.text, isEmpty);
      expect(find.text('推送'), findsNothing);
      expect(find.text('提醒规则'), findsOneWidget);
      expect(find.text('4 项开启 · 提前 3 天'), findsOneWidget);
      expect(find.text('还款日提醒'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('notification-reminder-settings')),
      );
      await tester.pumpAndSettle();
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
      await tester.tap(
        find.byKey(const ValueKey('notification-reminder-settings')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notification-budget-alert')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
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

    testWidgets('试发企业微信时使用当前通知地址', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('notification-wecom-webhook')),
        'https://qyapi.example.com/send?key=test',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('试发'));
      await tester.pumpAndSettle();

      expect(repository.wecomTestCalls, [
        'https://qyapi.example.com/send?key=test',
      ]);
      expect(find.text('试发成功'), findsOneWidget);
      expect(find.text('发送检查通过'), findsNothing);
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

    testWidgets('企业微信试发失败时展示错误信息', (tester) async {
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
      await tester.tap(find.text('试发'));
      await tester.pumpAndSettle();

      expect(repository.wecomTestCalls, [
        'https://qyapi.example.com/send?key=broken',
      ]);
      expect(find.textContaining('其他通道 不可用'), findsOneWidget);
      expect(find.textContaining('Webhook 不可用'), findsNothing);
    });

    testWidgets('企业微信试发地址留空时复用已保存配置', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('notification-wecom-webhook')),
        '',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('试发'));
      await tester.pumpAndSettle();

      expect(repository.wecomTestCalls, ['']);
      expect(find.text('试发成功'), findsOneWidget);
    });

    testWidgets('钉钉地址留空时仍传递本次新密钥', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey('notification-channel-dingtalk')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('notification-switch-semantics-启用钉钉')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('notification-dingtalk-secret')),
        'new-signing-secret',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('试发'));
      await tester.pumpAndSettle();

      expect(repository.dingtalkTestCalls, [
        (webhook: '', secret: 'new-signing-secret'),
      ]);
      expect(find.text('试发成功'), findsOneWidget);
    });

    testWidgets('保存成功后清空不回显的通知凭据输入', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('notification-wecom-webhook')),
        'https://qyapi.example.com/send?key=new',
      );
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls.single.wecomWebhook, contains('key=new'));
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('notification-wecom-webhook')),
      );
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('通知通道密钥输入框默认遮罩显示', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey('notification-channel-dingtalk')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('notification-switch-semantics-启用钉钉')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      final dingtalkSecret = tester.widget<TextField>(
        find.byKey(const ValueKey('notification-dingtalk-secret')),
      );
      expect(dingtalkSecret.obscureText, isTrue);
      expect(
        dingtalkSecret.decoration?.helperText,
        '地址留空或不变时，密钥留空会保留；更换地址时留空会清除旧密钥',
      );

      await tester.tap(
        find.byKey(const ValueKey('notification-channel-webhook')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('notification-switch-semantics-启用其他通道'),
          ),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      final webhookSecret = tester.widget<TextField>(
        find.byKey(const ValueKey('notification-webhook-secret')),
      );
      expect(webhookSecret.obscureText, isTrue);
      expect(
        webhookSecret.decoration?.helperText,
        '地址留空或不变时，密钥留空会保留；更换地址时留空会清除旧密钥',
      );
    });

    testWidgets('通知通道分段按钮可切换当前通道', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository);

      await tester.tap(
        find.byKey(const ValueKey('notification-channel-email')),
      );
      await tester.pumpAndSettle();

      expect(find.text('启用邮箱'), findsOneWidget);
      expect(find.text('邮件服务器'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('notification-switch-semantics-启用邮箱')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('邮箱地址'), findsOneWidget);
      expect(find.text('邮箱服务'), findsNothing);
      expect(find.text('连接端口'), findsNothing);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('邮箱密码'), findsOneWidget);
      expect(find.text('邮件服务器'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('notification-channel-webhook')),
      );
      await tester.pumpAndSettle();

      expect(find.text('启用其他通道'), findsOneWidget);
      expect(find.text('发送地址'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey('notification-switch-semantics-启用其他通道'),
          ),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('发送地址'), findsNothing);
      expect(find.text('通知地址'), findsOneWidget);
      expect(find.text('密钥'), findsOneWidget);
      expect(find.text('安全密钥'), findsNothing);
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

    testWidgets('通知设置页使用高级表面和清晰操作层级', (tester) async {
      final repository = _FakeNotificationRepository();
      await _pumpPage(tester, repository, physicalSize: const Size(1200, 2600));

      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(3));
      expect(find.text('启用通知'), findsOneWidget);
      expect(find.text('企业微信'), findsOneWidget);
      expect(find.text('提醒规则'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('notification-budget-alert')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('notification-reminder-settings')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('notification-budget-alert')),
        findsOneWidget,
      );
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
  final List<({String webhook, String secret})> dingtalkTestCalls = [];
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
  }) async {
    dingtalkTestCalls.add((webhook: webhook, secret: secret));
    return const TestNotificationResult(success: true, message: 'ok');
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
