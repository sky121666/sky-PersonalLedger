import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../data/notification_repository.dart';

class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(notificationSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知设置'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(notificationSettingsProvider),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新通知设置',
          ),
        ],
      ),
      body: settingsState.when(
        loading: () => const AppLoadingView(message: '正在加载通知设置...'),
        error: (error, _) => AppErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(notificationSettingsProvider),
        ),
        data: (settings) => _NotificationSettingsForm(settings: settings),
      ),
    );
  }
}

class _NotificationSettingsForm extends ConsumerStatefulWidget {
  const _NotificationSettingsForm({required this.settings});

  final NotificationSetting settings;

  @override
  ConsumerState<_NotificationSettingsForm> createState() =>
      _NotificationSettingsFormState();
}

class _NotificationSettingsFormState
    extends ConsumerState<_NotificationSettingsForm> {
  _NotificationChannel _channel = _NotificationChannel.wecom;
  String? _busyAction;
  String? _errorMessage;

  late bool _enabled;
  late bool _wecomEnabled;
  late bool _dingtalkEnabled;
  late bool _emailEnabled;
  late bool _webhookEnabled;
  late bool _notifyPaymentDue;
  late bool _notifyBudgetAlert;
  late bool _notifyLendingDue;
  late bool _notifyAnnualReport;
  late int _advanceDays;

  late final TextEditingController _wecomWebhookController;
  late final TextEditingController _dingtalkWebhookController;
  late final TextEditingController _dingtalkSecretController;
  late final TextEditingController _smtpHostController;
  late final TextEditingController _smtpPortController;
  late final TextEditingController _smtpUserController;
  late final TextEditingController _smtpPasswordController;
  late final TextEditingController _smtpFromController;
  late final TextEditingController _emailToController;
  late final TextEditingController _webhookUrlController;
  late final TextEditingController _webhookSecretController;

  bool get _isBusy => _busyAction != null;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _enabled = settings.enabled;
    _wecomEnabled = settings.wecomEnabled;
    _dingtalkEnabled = settings.dingtalkEnabled;
    _emailEnabled = settings.emailEnabled;
    _webhookEnabled = settings.webhookEnabled;
    _notifyPaymentDue = settings.notifyPaymentDue;
    _notifyBudgetAlert = settings.notifyBudgetAlert;
    _notifyLendingDue = settings.notifyLendingDue;
    _notifyAnnualReport = settings.notifyAnnualReport;
    _advanceDays = _normalizeAdvanceDays(settings.advanceDays);
    _wecomWebhookController = TextEditingController(
      text: settings.wecomWebhook,
    );
    _dingtalkWebhookController = TextEditingController(
      text: settings.dingtalkWebhook,
    );
    _dingtalkSecretController = TextEditingController(
      text: settings.dingtalkSecret,
    );
    _smtpHostController = TextEditingController(text: settings.smtpHost);
    _smtpPortController = TextEditingController(
      text: settings.smtpPort.toString(),
    );
    _smtpUserController = TextEditingController(text: settings.smtpUser);
    _smtpPasswordController = TextEditingController();
    _smtpFromController = TextEditingController(text: settings.smtpFrom);
    _emailToController = TextEditingController(text: settings.emailTo);
    _webhookUrlController = TextEditingController(text: settings.webhookUrl);
    _webhookSecretController = TextEditingController(
      text: settings.webhookSecret,
    );
  }

  @override
  void dispose() {
    _wecomWebhookController.dispose();
    _dingtalkWebhookController.dispose();
    _dingtalkSecretController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUserController.dispose();
    _smtpPasswordController.dispose();
    _smtpFromController.dispose();
    _emailToController.dispose();
    _webhookUrlController.dispose();
    _webhookSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final enabledAccent = _enabled
        ? financeColors.income
        : financeColors.warning;
    return AdaptivePageContainer(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (_errorMessage != null) ...[
            StaggeredEntrance(
              index: 0,
              child: _ErrorBanner(message: _errorMessage!),
            ),
            const SizedBox(height: 12),
          ],
          StaggeredEntrance(
            index: 1,
            child: PremiumSurface(
              accentColor: enabledAccent,
              child: _NotificationSwitchRow(
                icon: Icons.notifications_active_outlined,
                color: enabledAccent,
                title: '启用通知',
                value: _enabled,
                switchKey: const ValueKey('notification-enabled'),
                onChanged: _isBusy
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
            ),
          ),
          const SizedBox(height: 16),
          StaggeredEntrance(
            index: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_NotificationChannel>(
                segments: const [
                  ButtonSegment(
                    value: _NotificationChannel.wecom,
                    icon: Icon(Icons.chat_outlined),
                    label: Text('企业微信'),
                  ),
                  ButtonSegment(
                    value: _NotificationChannel.dingtalk,
                    icon: Icon(Icons.forum_outlined),
                    label: Text('钉钉'),
                  ),
                  ButtonSegment(
                    value: _NotificationChannel.email,
                    icon: Icon(Icons.mail_outline),
                    label: Text('邮箱'),
                  ),
                  ButtonSegment(
                    value: _NotificationChannel.webhook,
                    icon: Icon(Icons.webhook_outlined),
                    label: Text('Webhook'),
                  ),
                ],
                selected: {_channel},
                onSelectionChanged: _isBusy
                    ? null
                    : (value) => setState(() => _channel = value.single),
              ),
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(index: 3, child: _buildChannelCard()),
          const SizedBox(height: 16),
          StaggeredEntrance(
            index: 4,
            child: _OptionsCard(
              paymentDue: _notifyPaymentDue,
              budgetAlert: _notifyBudgetAlert,
              lendingDue: _notifyLendingDue,
              annualReport: _notifyAnnualReport,
              advanceDays: _advanceDays,
              enabled: !_isBusy,
              onPaymentDueChanged: (value) =>
                  setState(() => _notifyPaymentDue = value),
              onBudgetAlertChanged: (value) =>
                  setState(() => _notifyBudgetAlert = value),
              onLendingDueChanged: (value) =>
                  setState(() => _notifyLendingDue = value),
              onAnnualReportChanged: (value) =>
                  setState(() => _notifyAnnualReport = value),
              onAdvanceDaysChanged: (value) =>
                  setState(() => _advanceDays = value),
            ),
          ),
          const SizedBox(height: 16),
          StaggeredEntrance(
            index: 5,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _save,
              icon: _busyAction == 'save'
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('保存设置'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard() {
    return switch (_channel) {
      _NotificationChannel.wecom => _ChannelCard(
        title: '企业微信',
        enabled: _wecomEnabled,
        enabledLabel: '启用企业微信',
        onEnabledChanged: (value) => setState(() => _wecomEnabled = value),
        testButtonText: '发送测试消息',
        testing: _busyAction == 'test-wecom',
        onTest: _testWecom,
        children: [
          TextField(
            key: const ValueKey('notification-wecom-webhook'),
            controller: _wecomWebhookController,
            decoration: const InputDecoration(
              labelText: 'Webhook 地址',
              prefixIcon: Icon(Icons.link_outlined),
            ),
          ),
        ],
      ),
      _NotificationChannel.dingtalk => _ChannelCard(
        title: '钉钉',
        enabled: _dingtalkEnabled,
        enabledLabel: '启用钉钉',
        onEnabledChanged: (value) => setState(() => _dingtalkEnabled = value),
        testButtonText: '发送测试消息',
        testing: _busyAction == 'test-dingtalk',
        onTest: _testDingtalk,
        children: [
          TextField(
            controller: _dingtalkWebhookController,
            decoration: const InputDecoration(
              labelText: 'Webhook 地址',
              prefixIcon: Icon(Icons.link_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('notification-dingtalk-secret'),
            controller: _dingtalkSecretController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '加签密钥',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
        ],
      ),
      _NotificationChannel.email => _ChannelCard(
        title: '邮箱',
        enabled: _emailEnabled,
        enabledLabel: '启用邮箱',
        onEnabledChanged: (value) => setState(() => _emailEnabled = value),
        testButtonText: '发送测试邮件',
        testing: _busyAction == 'test-email',
        onTest: _testEmail,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _smtpHostController,
                  decoration: const InputDecoration(
                    labelText: 'SMTP 服务器',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _smtpPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '端口'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _smtpUserController,
            decoration: const InputDecoration(
              labelText: '邮箱账号',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _smtpPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码/授权码',
              prefixIcon: Icon(Icons.password_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _smtpFromController,
            decoration: const InputDecoration(
              labelText: '发件人',
              prefixIcon: Icon(Icons.outbox_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailToController,
            decoration: const InputDecoration(
              labelText: '收件人',
              prefixIcon: Icon(Icons.inbox_outlined),
            ),
          ),
        ],
      ),
      _NotificationChannel.webhook => _ChannelCard(
        title: 'Webhook',
        enabled: _webhookEnabled,
        enabledLabel: '启用 Webhook',
        onEnabledChanged: (value) => setState(() => _webhookEnabled = value),
        testButtonText: '发送测试请求',
        testing: _busyAction == 'test-webhook',
        onTest: _testWebhook,
        children: [
          TextField(
            controller: _webhookUrlController,
            decoration: const InputDecoration(
              labelText: 'Webhook URL',
              prefixIcon: Icon(Icons.link_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('notification-webhook-secret'),
            controller: _webhookSecretController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密钥',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
        ],
      ),
    };
  }

  Future<void> _save() async {
    await _runAction(
      action: 'save',
      request: () => ref
          .read(notificationRepositoryProvider)
          .updateSettings(_buildRequest())
          .then((_) => _clearSecretControllers()),
      successMessage: '通知设置已保存',
    );
    ref.invalidate(notificationSettingsProvider);
  }

  void _clearSecretControllers() {
    _dingtalkSecretController.clear();
    _smtpPasswordController.clear();
    _webhookSecretController.clear();
  }

  Future<void> _testWecom() async {
    final webhook = _wecomWebhookController.text.trim();
    if (webhook.isEmpty) {
      setState(() => _errorMessage = '请填写企业微信 Webhook 地址');
      return;
    }
    await _runTestAction(
      action: 'test-wecom',
      request: () =>
          ref.read(notificationRepositoryProvider).testWecom(webhook),
    );
  }

  Future<void> _testDingtalk() async {
    final webhook = _dingtalkWebhookController.text.trim();
    if (webhook.isEmpty) {
      setState(() => _errorMessage = '请填写钉钉 Webhook 地址');
      return;
    }
    await _runTestAction(
      action: 'test-dingtalk',
      request: () => ref
          .read(notificationRepositoryProvider)
          .testDingtalk(
            webhook: webhook,
            secret: _dingtalkSecretController.text.trim(),
          ),
    );
  }

  Future<void> _testEmail() async {
    final host = _smtpHostController.text.trim();
    final user = _smtpUserController.text.trim();
    if (host.isEmpty || user.isEmpty) {
      setState(() => _errorMessage = '请填写 SMTP 服务器和邮箱账号');
      return;
    }
    await _runTestAction(
      action: 'test-email',
      request: () => ref
          .read(notificationRepositoryProvider)
          .testEmail(
            smtpHost: host,
            smtpPort: _smtpPort,
            smtpUser: user,
            smtpPassword: _smtpPasswordController.text.trim(),
            smtpFrom: _smtpFromController.text.trim(),
            emailTo: _emailToController.text.trim(),
          ),
    );
  }

  Future<void> _testWebhook() async {
    final url = _webhookUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = '请填写 Webhook URL');
      return;
    }
    await _runTestAction(
      action: 'test-webhook',
      request: () => ref
          .read(notificationRepositoryProvider)
          .testWebhook(url: url, secret: _webhookSecretController.text.trim()),
    );
  }

  Future<void> _runTestAction({
    required String action,
    required Future<TestNotificationResult?> Function() request,
  }) async {
    await _runAction(
      action: action,
      request: () async {
        final result = await request();
        if (result != null && !result.success) {
          throw StateError(result.message.isEmpty ? '测试失败' : result.message);
        }
      },
      successMessage: '测试成功',
    );
  }

  Future<void> _runAction({
    required String action,
    required Future<void> Function() request,
    required String successMessage,
  }) async {
    setState(() {
      _busyAction = action;
      _errorMessage = null;
    });
    try {
      await request();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  NotificationSettingRequest _buildRequest() {
    return NotificationSettingRequest(
      enabled: _enabled,
      wecomEnabled: _wecomEnabled,
      wecomWebhook: _wecomWebhookController.text.trim(),
      dingtalkEnabled: _dingtalkEnabled,
      dingtalkWebhook: _dingtalkWebhookController.text.trim(),
      dingtalkSecret: _dingtalkSecretController.text.trim(),
      emailEnabled: _emailEnabled,
      smtpHost: _smtpHostController.text.trim(),
      smtpPort: _smtpPort,
      smtpUser: _smtpUserController.text.trim(),
      smtpPassword: _smtpPasswordController.text.trim(),
      smtpFrom: _smtpFromController.text.trim(),
      emailTo: _emailToController.text.trim(),
      webhookEnabled: _webhookEnabled,
      webhookUrl: _webhookUrlController.text.trim(),
      webhookSecret: _webhookSecretController.text.trim(),
      notifyPaymentDue: _notifyPaymentDue,
      notifyBudgetAlert: _notifyBudgetAlert,
      notifyLendingDue: _notifyLendingDue,
      notifyAnnualReport: _notifyAnnualReport,
      advanceDays: _advanceDays,
    );
  }

  int get _smtpPort {
    final value = int.tryParse(_smtpPortController.text.trim());
    if (value == null || value <= 0) {
      return 587;
    }
    return value;
  }
}

enum _NotificationChannel { wecom, dingtalk, email, webhook }

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.title,
    required this.enabled,
    required this.enabledLabel,
    required this.onEnabledChanged,
    required this.children,
    required this.testButtonText,
    required this.testing,
    required this.onTest,
  });

  final String title;
  final bool enabled;
  final String enabledLabel;
  final ValueChanged<bool> onEnabledChanged;
  final List<Widget> children;
  final String testButtonText;
  final bool testing;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final accentColor = enabled ? financeColors.income : financeColors.asset;
    return PremiumSurface(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NotificationSwitchRow(
            icon: _channelIcon(title),
            color: accentColor,
            title: title,
            subtitle: enabledLabel,
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: testing ? null : onTest,
            icon: testing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(testing ? '测试中...' : testButtonText),
          ),
        ],
      ),
    );
  }

  IconData _channelIcon(String title) {
    return switch (title) {
      '企业微信' => Icons.chat_outlined,
      '钉钉' => Icons.forum_outlined,
      '邮箱' => Icons.mail_outline,
      _ => Icons.webhook_outlined,
    };
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({
    required this.paymentDue,
    required this.budgetAlert,
    required this.lendingDue,
    required this.annualReport,
    required this.advanceDays,
    required this.enabled,
    required this.onPaymentDueChanged,
    required this.onBudgetAlertChanged,
    required this.onLendingDueChanged,
    required this.onAnnualReportChanged,
    required this.onAdvanceDaysChanged,
  });

  final bool paymentDue;
  final bool budgetAlert;
  final bool lendingDue;
  final bool annualReport;
  final int advanceDays;
  final bool enabled;
  final ValueChanged<bool> onPaymentDueChanged;
  final ValueChanged<bool> onBudgetAlertChanged;
  final ValueChanged<bool> onLendingDueChanged;
  final ValueChanged<bool> onAnnualReportChanged;
  final ValueChanged<int> onAdvanceDaysChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.warning,
      child: Column(
        children: [
          _NotificationPanelHeader(
            icon: Icons.tune_outlined,
            color: financeColors.warning,
            title: '通知选项',
          ),
          _NotificationOptionRow(
            icon: Icons.credit_card_outlined,
            color: financeColors.warning,
            title: '还款日提醒',
            value: paymentDue,
            onChanged: enabled ? onPaymentDueChanged : null,
          ),
          _OptionDivider(),
          _NotificationOptionRow(
            icon: Icons.savings_outlined,
            color: financeColors.expense,
            title: '预算超支提醒',
            value: budgetAlert,
            switchKey: const ValueKey('notification-budget-alert'),
            onChanged: enabled ? onBudgetAlertChanged : null,
          ),
          _OptionDivider(),
          _NotificationOptionRow(
            icon: Icons.handshake_outlined,
            color: financeColors.asset,
            title: '借款到期提醒',
            value: lendingDue,
            onChanged: enabled ? onLendingDueChanged : null,
          ),
          _OptionDivider(),
          _NotificationOptionRow(
            icon: Icons.summarize_outlined,
            color: financeColors.income,
            title: '年度报告通知',
            value: annualReport,
            onChanged: enabled ? onAnnualReportChanged : null,
          ),
          _OptionDivider(),
          _NotificationAdvanceRow(
            advanceDays: advanceDays,
            enabled: enabled,
            onAdvanceDaysChanged: onAdvanceDaysChanged,
          ),
        ],
      ),
    );
  }
}

class _OptionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 50,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

class _NotificationPanelHeader extends StatelessWidget {
  const _NotificationPanelHeader({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBadge(icon: icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotificationSwitchRow extends StatelessWidget {
  const _NotificationSwitchRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.switchKey,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: value ? 0.10 : 0.04),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: value ? 0.18 : 0.10)),
      ),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 38, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            key: ValueKey('notification-switch-semantics-$title'),
            label: title,
            toggled: value,
            enabled: onChanged != null,
            child: Switch(key: switchKey, value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _NotificationOptionRow extends StatelessWidget {
  const _NotificationOptionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
    this.switchKey,
  });

  final IconData icon;
  final Color color;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 34, iconSize: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            key: ValueKey('notification-switch-semantics-$title'),
            label: title,
            toggled: value,
            enabled: onChanged != null,
            child: Switch(key: switchKey, value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _NotificationAdvanceRow extends StatelessWidget {
  const _NotificationAdvanceRow({
    required this.advanceDays,
    required this.enabled,
    required this.onAdvanceDaysChanged,
  });

  final int advanceDays;
  final bool enabled;
  final ValueChanged<int> onAdvanceDaysChanged;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconBadge(
            icon: Icons.event_available_outlined,
            color: financeColors.asset,
            size: 34,
            iconSize: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '提前 $advanceDays 天提醒',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          DropdownButton<int>(
            value: advanceDays,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(12),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 天')),
              DropdownMenuItem(value: 2, child: Text('2 天')),
              DropdownMenuItem(value: 3, child: Text('3 天')),
              DropdownMenuItem(value: 5, child: Text('5 天')),
              DropdownMenuItem(value: 7, child: Text('7 天')),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) {
                      onAdvanceDaysChanged(value);
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _normalizeAdvanceDays(int value) {
  const allowed = {1, 2, 3, 5, 7};
  return allowed.contains(value) ? value : 3;
}
