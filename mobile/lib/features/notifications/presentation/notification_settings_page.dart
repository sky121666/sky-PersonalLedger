import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../data/notification_repository.dart';

class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(notificationSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: settingsState.when(
        loading: () => const AppLoadingView(message: '正在加载通知设置...'),
        error: (error, _) => AppErrorView(
          message: '通知设置加载失败',
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
    final rows = [
      if (_errorMessage != null)
        _NotificationRow(_ErrorBanner(message: _errorMessage!)),
      _NotificationRow(
        PremiumSurface(
          accentColor: enabledAccent,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
      _NotificationRow(
        SingleChildScrollView(
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
                label: Text('其他通道'),
              ),
            ],
            selected: {_channel},
            onSelectionChanged: _isBusy
                ? null
                : (value) => setState(() => _channel = value.single),
          ),
        ),
        10,
      ),
      _NotificationRow(_buildChannelCard()),
      _NotificationRow(
        _ReminderSummaryCard(
          enabledCount: _enabledReminderCount,
          advanceDays: _advanceDays,
          enabled: !_isBusy,
          onTap: _openReminderSheet,
        ),
      ),
      _NotificationRow(
        SizedBox(
          width: double.infinity,
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
        0,
      ),
    ];

    return AdaptivePageContainer(
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == rows.length - 1 ? 0 : row.bottomSpacing,
            ),
            child: row.child,
          );
        },
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
        testButtonText: '试发',
        testing: _busyAction == 'test-wecom',
        onTest: _testWecom,
        children: [
          TextField(
            key: const ValueKey('notification-wecom-webhook'),
            controller: _wecomWebhookController,
            decoration: const InputDecoration(
              labelText: '通知地址',
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
        testButtonText: '试发',
        testing: _busyAction == 'test-dingtalk',
        onTest: _testDingtalk,
        children: [
          TextField(
            controller: _dingtalkWebhookController,
            decoration: const InputDecoration(
              labelText: '通知地址',
              prefixIcon: Icon(Icons.link_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('notification-dingtalk-secret'),
            controller: _dingtalkSecretController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密钥',
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
        testButtonText: '试发',
        testing: _busyAction == 'test-email',
        onTest: _testEmail,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _smtpHostController,
                  decoration: const InputDecoration(
                    labelText: '邮箱地址',
                    prefixIcon: Icon(Icons.mail_outline),
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
              labelText: '邮箱密码',
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
        title: '其他通道',
        enabled: _webhookEnabled,
        enabledLabel: '启用其他通道',
        onEnabledChanged: (value) => setState(() => _webhookEnabled = value),
        testButtonText: '试发',
        testing: _busyAction == 'test-webhook',
        onTest: _testWebhook,
        children: [
          TextField(
            controller: _webhookUrlController,
            decoration: const InputDecoration(
              labelText: '通知地址',
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

  int get _enabledReminderCount {
    return [
      _notifyPaymentDue,
      _notifyBudgetAlert,
      _notifyLendingDue,
      _notifyAnnualReport,
    ].where((enabled) => enabled).length;
  }

  Future<void> _openReminderSheet() async {
    if (_isBusy) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateSheet(VoidCallback update) {
              setState(update);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: _OptionsCard(
                  paymentDue: _notifyPaymentDue,
                  budgetAlert: _notifyBudgetAlert,
                  lendingDue: _notifyLendingDue,
                  annualReport: _notifyAnnualReport,
                  advanceDays: _advanceDays,
                  enabled: !_isBusy,
                  onPaymentDueChanged: (value) =>
                      updateSheet(() => _notifyPaymentDue = value),
                  onBudgetAlertChanged: (value) =>
                      updateSheet(() => _notifyBudgetAlert = value),
                  onLendingDueChanged: (value) =>
                      updateSheet(() => _notifyLendingDue = value),
                  onAnnualReportChanged: (value) =>
                      updateSheet(() => _notifyAnnualReport = value),
                  onAdvanceDaysChanged: (value) =>
                      updateSheet(() => _advanceDays = value),
                ),
              ),
            );
          },
        );
      },
    );
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
      setState(() => _errorMessage = '请填写企业微信地址');
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
      setState(() => _errorMessage = '请填写钉钉地址');
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
      setState(() => _errorMessage = '请填写邮箱地址和邮箱账号');
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
      setState(() => _errorMessage = '请填写通知地址');
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
          throw StateError(result.message.isEmpty ? '试发失败' : result.message);
        }
      },
      successMessage: '试发成功',
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
      setState(() => _errorMessage = _cleanNotificationError(error));
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  String _cleanNotificationError(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceAll('Webhook', '其他通道')
        .replaceAll('webhook', '其他通道');
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

class _NotificationRow {
  const _NotificationRow(this.child, [this.bottomSpacing = 12]);

  final Widget child;
  final double bottomSpacing;
}

enum _NotificationChannel { wecom, dingtalk, email, webhook }

class _ReminderSummaryCard extends StatelessWidget {
  const _ReminderSummaryCard({
    required this.enabledCount,
    required this.advanceDays,
    required this.enabled,
    required this.onTap,
  });

  final int enabledCount;
  final int advanceDays;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: financeColors.warning,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '提醒规则',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '$enabledCount 项开启 · 提前 $advanceDays 天',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            key: const ValueKey('notification-reminder-settings'),
            onPressed: enabled ? onTap : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('设置'),
          ),
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NotificationSwitchRow(
            icon: _channelIcon(title),
            color: accentColor,
            title: enabledLabel,
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            ...children,
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: testing ? null : onTest,
                icon: testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(testing ? '试发中' : testButtonText),
              ),
            ),
          ],
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          _NotificationPanelHeader(
            icon: Icons.tune_outlined,
            color: financeColors.warning,
            title: '提醒',
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
      indent: 18,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Icon(icon, size: 18, color: color),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
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
              const SizedBox(height: 2),
              Text(
                value ? '当前已开启' : '当前未开启',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Semantics(
          key: ValueKey('notification-switch-semantics-$title'),
          label: title,
          toggled: value,
          enabled: onChanged != null,
          child: Switch(key: switchKey, value: value, onChanged: onChanged),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '提前 $advanceDays 天提醒',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.event_available_outlined,
            size: 16,
            color: financeColors.asset,
          ),
          const SizedBox(width: 8),
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
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
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
