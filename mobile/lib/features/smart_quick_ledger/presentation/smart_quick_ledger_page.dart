import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../transactions/data/transaction_models.dart';
import '../../transactions/presentation/widgets/quick_transaction_pickers.dart';
import '../data/quick_ledger_draft.dart';
import '../data/quick_ledger_repository.dart';

class SmartQuickLedgerPage extends ConsumerStatefulWidget {
  const SmartQuickLedgerPage({super.key});

  @override
  ConsumerState<SmartQuickLedgerPage> createState() =>
      _SmartQuickLedgerPageState();
}

class _SmartQuickLedgerPageState extends ConsumerState<SmartQuickLedgerPage>
    with WidgetsBindingObserver {
  final Set<String> _enabledSources = {'wechat', 'alipay', 'bank'};
  String? _busyDraftId;
  bool? _notificationListenerEnabled;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlatformState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadPlatformState());
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(quickLedgerDraftsProvider);
    final rows = [
      _SmartLedgerRow(
        _CapabilityCard(
          isAndroid: _isAndroid,
          isIOS: _isIOS,
          notificationListenerEnabled: _notificationListenerEnabled,
          onOpenNotificationSettings: _openNotificationSettings,
        ),
      ),
      if (_isAndroid)
        _SmartLedgerRow(
          _SourceSettingsCard(
            enabledSources: _enabledSources,
            onChanged: _toggleSource,
          ),
        ),
      _SmartLedgerRow(
        _PendingDraftsCard(
          drafts: drafts,
          busyDraftId: _busyDraftId,
          onConfirm: _confirmDraft,
          onDismiss: _dismissDraft,
        ),
      ),
      _SmartLedgerRow(_ManualImportCard(onImport: _openTextImport), 0),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('智能快记')),
      body: AdaptivePageContainer(
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
      ),
    );
  }

  Future<void> _loadPlatformState() async {
    final controller = ref.read(quickLedgerDraftsProvider.notifier);
    final notificationEnabled = await controller
        .isNotificationListenerEnabled();
    final enabledSources = await controller.getEnabledSources();
    await controller.loadFromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationListenerEnabled = notificationEnabled;
      _enabledSources
        ..clear()
        ..addAll(enabledSources);
    });
  }

  void _toggleSource(String id, bool enabled) {
    setState(() {
      if (enabled) {
        _enabledSources.add(id);
      } else {
        _enabledSources.remove(id);
      }
    });
    unawaited(
      ref
          .read(quickLedgerDraftsProvider.notifier)
          .setEnabledSources(_enabledSources),
    );
  }

  Future<void> _openNotificationSettings() async {
    await ref
        .read(quickLedgerDraftsProvider.notifier)
        .openNotificationListenerSettings();
  }

  Future<void> _confirmDraft(QuickLedgerDraft draft) async {
    if (_busyDraftId != null) {
      return;
    }
    setState(() => _busyDraftId = draft.id);
    try {
      final controller = ref.read(quickLedgerDraftsProvider.notifier);
      final options = await controller.loadConfirmationOptions();
      if (!mounted) {
        return;
      }
      setState(() => _busyDraftId = null);
      final formData = await showModalBottomSheet<TransactionFormData>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) =>
            _DraftConfirmationSheet(draft: draft, options: options),
      );
      if (!mounted || formData == null) {
        return;
      }
      setState(() => _busyDraftId = draft.id);
      await controller.confirm(draft.id, formData);
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('已记入账本')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(_confirmationError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _busyDraftId = null);
      }
    }
  }

  void _dismissDraft(QuickLedgerDraft draft) {
    unawaited(ref.read(quickLedgerDraftsProvider.notifier).dismiss(draft.id));
  }

  Future<void> _openTextImport() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => const _ManualImportSheet(),
    );
    if (!mounted || text == null || text.isEmpty) {
      return;
    }
    try {
      ref.read(quickLedgerDraftsProvider.notifier).importText(text);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已生成待确认候选')));
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }
}

String _confirmationError(Object error) {
  if (error is FormatException) {
    return error.message.toString();
  }
  return '确认未完成，请稍后重试';
}

class _DraftConfirmationSheet extends StatefulWidget {
  const _DraftConfirmationSheet({required this.draft, required this.options});

  final QuickLedgerDraft draft;
  final QuickLedgerConfirmationOptions options;

  @override
  State<_DraftConfirmationSheet> createState() =>
      _DraftConfirmationSheetState();
}

class _DraftConfirmationSheetState extends State<_DraftConfirmationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _remarkController;
  late TransactionType _type;
  late DateTime _transactionDate;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _type = draft.type;
    _transactionDate = draft.occurredAt;
    _amountController = TextEditingController(
      text: draft.amount.toStringAsFixed(2),
    );
    _remarkController = TextEditingController(text: draft.merchant);
    _accountId = _validSuggestedAccountId(draft.suggestedAccountId);
    _categoryId = _validSuggestedCategoryId(
      draft.suggestedCategoryId,
      draft.type,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '确认候选',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '核对并修正后再记入账本。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _buildTypeSelector(),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('smart-ledger-confirm-amount'),
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: '金额',
                  prefixText: '¥ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final amount = _parseAmount(value);
                  return amount == null || !amount.isFinite || amount <= 0
                      ? '请输入有效金额'
                      : null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('smart-ledger-confirm-remark'),
                controller: _remarkController,
                decoration: const InputDecoration(labelText: '商户 / 备注'),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              QuickTransactionDropdownField(
                key: const ValueKey('smart-ledger-confirm-account'),
                value: _accountId,
                label: _type == TransactionType.transfer ? '转出账户' : '账户',
                icon: Icons.account_balance_wallet_outlined,
                items: widget.options.accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    )
                    .toList(),
                validator: (value) => value == null || value.isEmpty
                    ? (_type == TransactionType.transfer ? '请选择转出账户' : '请选择账户')
                    : null,
                onChanged: (value) => setState(() {
                  _accountId = value;
                  if (_toAccountId == value) {
                    _toAccountId = null;
                  }
                }),
              ),
              const SizedBox(height: 8),
              if (_type == TransactionType.transfer)
                _buildToAccountPicker()
              else
                _buildCategoryPicker(),
              const SizedBox(height: 8),
              _buildDateTimePicker(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('smart-ledger-confirm-submit'),
                      onPressed: _submit,
                      child: const Text('确认记账'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: [
        for (final type in TransactionType.values) ...[
          Expanded(
            child: ChoiceChip(
              key: ValueKey('smart-ledger-confirm-type-${type.value}'),
              label: SizedBox(
                width: double.infinity,
                child: Text(type.label, textAlign: TextAlign.center),
              ),
              selected: _type == type,
              onSelected: (_) => setState(() {
                _type = type;
                _categoryId = null;
                _toAccountId = null;
              }),
            ),
          ),
          if (type != TransactionType.values.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildCategoryPicker() {
    final categories = widget.options.categories
        .where((category) => category.type == _type.value)
        .toList();
    return QuickTransactionDropdownField(
      key: ValueKey('smart-ledger-confirm-category-${_type.value}'),
      value: categories.any((category) => category.id == _categoryId)
          ? _categoryId
          : null,
      label: '分类',
      icon: Icons.category_outlined,
      items: categories
          .map(
            (category) => DropdownMenuItem<String>(
              value: category.id,
              child: Text(category.name),
            ),
          )
          .toList(),
      validator: (value) => value == null || value.isEmpty ? '请选择分类' : null,
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }

  Widget _buildToAccountPicker() {
    final accounts = widget.options.accounts
        .where((account) => account.id != _accountId)
        .toList();
    return QuickTransactionDropdownField(
      key: ValueKey('smart-ledger-confirm-to-account-${_accountId ?? ''}'),
      value: accounts.any((account) => account.id == _toAccountId)
          ? _toAccountId
          : null,
      label: '转入账户',
      icon: Icons.move_down_outlined,
      items: accounts
          .map(
            (account) => DropdownMenuItem<String>(
              value: account.id,
              child: Text(account.name),
            ),
          )
          .toList(),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '请选择转入账户';
        }
        if (value == _accountId) {
          return '转出和转入账户不能相同';
        }
        return null;
      },
      onChanged: (value) => setState(() => _toAccountId = value),
    );
  }

  Widget _buildDateTimePicker() {
    return OutlinedButton.icon(
      key: const ValueKey('smart-ledger-confirm-date'),
      onPressed: _pickDateTime,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text('日期 ${_formatDateTime(_transactionDate)}'),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_transactionDate),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _transactionDate = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _transactionDate.hour,
        time?.minute ?? _transactionDate.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      TransactionFormData(
        type: _type,
        amount: _parseAmount(_amountController.text)!,
        accountId: _accountId!,
        toAccountId: _type == TransactionType.transfer ? _toAccountId : null,
        categoryId: _type == TransactionType.transfer ? null : _categoryId,
        transactionDate: _transactionDate,
        remark: _remarkController.text.trim(),
        tags: [widget.draft.source.label],
      ),
    );
  }

  String? _validSuggestedAccountId(String? id) {
    if (id == null) {
      return null;
    }
    return widget.options.accounts.any((account) => account.id == id)
        ? id
        : null;
  }

  String? _validSuggestedCategoryId(String? id, TransactionType type) {
    if (id == null) {
      return null;
    }
    return widget.options.categories.any(
          (category) => category.id == id && category.type == type.value,
        )
        ? id
        : null;
  }

  static double? _parseAmount(String? value) {
    return double.tryParse((value ?? '').replaceAll(',', '').trim());
  }
}

class _ManualImportSheet extends StatefulWidget {
  const _ManualImportSheet();

  @override
  State<_ManualImportSheet> createState() => _ManualImportSheetState();
}

class _ManualImportSheetState extends State<_ManualImportSheet> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '粘贴支付通知',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '仅在本机解析；确认候选前不会写入账本。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('smart-ledger-import-text-field'),
              controller: _textController,
              minLines: 4,
              maxLines: 7,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '通知文本',
                hintText: '例如：微信支付 向瑞幸咖啡付款 38.90 元',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('smart-ledger-paste-clipboard'),
                    onPressed: _pasteClipboard,
                    icon: const Icon(Icons.content_paste_outlined),
                    label: const Text('粘贴'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('smart-ledger-create-candidate'),
                    onPressed: () =>
                        Navigator.of(context).pop(_textController.text.trim()),
                    child: const Text('生成候选'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pasteClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) {
      return;
    }
    _textController.text = clipboard?.text?.trim() ?? '';
  }
}

class _SmartLedgerRow {
  const _SmartLedgerRow(this.child, [this.bottomSpacing = 12]);

  final Widget child;
  final double bottomSpacing;
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.isAndroid,
    required this.isIOS,
    required this.notificationListenerEnabled,
    required this.onOpenNotificationSettings,
  });

  final bool isAndroid;
  final bool isIOS;
  final bool? notificationListenerEnabled;
  final VoidCallback onOpenNotificationSettings;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      key: const ValueKey('smart-ledger-capability-card'),
      accentColor: financeColors.asset,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.auto_awesome_outlined,
                color: financeColors.asset,
                size: 42,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '智能候选记账',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '本地解析 · 确认后入账',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CapabilityLine(
            icon: Icons.android_outlined,
            title: 'Android',
            value: _androidStatus,
            active: isAndroid,
            onTap: isAndroid ? onOpenNotificationSettings : null,
          ),
          const SizedBox(height: 8),
          _CapabilityLine(
            icon: Icons.phone_iphone_outlined,
            title: 'iOS',
            value: isIOS ? '粘贴导入可用' : '不读取通知',
            active: isIOS,
          ),
        ],
      ),
    );
  }

  String get _androidStatus {
    if (!isAndroid) {
      return '仅 Android 可用';
    }
    return notificationListenerEnabled == true ? '已开启' : '待授权';
  }
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine({
    required this.icon,
    required this.title,
    required this.value,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = active ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: 0.06),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color, size: 34, iconSize: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceSettingsCard extends StatelessWidget {
  const _SourceSettingsCard({
    required this.enabledSources,
    required this.onChanged,
  });

  final Set<String> enabledSources;
  final void Function(String id, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final sources = [
      _SourceConfig('wechat', '微信支付', Icons.chat_outlined),
      _SourceConfig('alipay', '支付宝', Icons.account_balance_wallet_outlined),
      _SourceConfig('bank', '银行提醒', Icons.account_balance),
      _SourceConfig('unionpay', '云闪付', Icons.credit_card_outlined),
    ];
    return PremiumSurface(
      key: const ValueKey('smart-ledger-source-card'),
      accentColor: AppTheme.financeColors(context).income,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '通知来源',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final source in sources)
            _SourceSwitchTile(
              source: source,
              enabled: enabledSources.contains(source.id),
              onChanged: (enabled) => onChanged(source.id, enabled),
            ),
        ],
      ),
    );
  }
}

class _SourceConfig {
  const _SourceConfig(this.id, this.title, this.icon);

  final String id;
  final String title;
  final IconData icon;
}

class _SourceSwitchTile extends StatelessWidget {
  const _SourceSwitchTile({
    required this.source,
    required this.enabled,
    required this.onChanged,
  });

  final _SourceConfig source;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('smart-ledger-source-${source.id}'),
      label: source.title,
      toggled: enabled,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(!enabled),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                IconBadge(
                  icon: source.icon,
                  color: enabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 34,
                  iconSize: 17,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    source.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Switch.adaptive(value: enabled, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingDraftsCard extends StatelessWidget {
  const _PendingDraftsCard({
    required this.drafts,
    required this.busyDraftId,
    required this.onConfirm,
    required this.onDismiss,
  });

  final List<QuickLedgerDraft> drafts;
  final String? busyDraftId;
  final ValueChanged<QuickLedgerDraft> onConfirm;
  final ValueChanged<QuickLedgerDraft> onDismiss;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      key: const ValueKey('smart-ledger-pending-card'),
      accentColor: AppTheme.financeColors(context).warning,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '待确认',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${drafts.length} 条',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (drafts.isEmpty)
            Row(
              children: [
                IconBadge(
                  icon: Icons.inbox_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 34,
                  iconSize: 17,
                ),
                const SizedBox(width: 10),
                Text(
                  '暂无候选',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else
            for (final draft in drafts.indexed) ...[
              _DraftTile(
                draft: draft.$2,
                busy: busyDraftId == draft.$2.id,
                onConfirm: () => onConfirm(draft.$2),
                onDismiss: () => onDismiss(draft.$2),
              ),
              if (draft.$1 != drafts.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.busy,
    required this.onConfirm,
    required this.onDismiss,
  });

  final QuickLedgerDraft draft;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final amountColor = draft.type == TransactionType.income
        ? financeColors.income
        : financeColors.expense;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          amountColor.withValues(alpha: 0.045),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: draft.source == QuickLedgerDraftSource.androidNotification
                    ? Icons.notifications_active_outlined
                    : Icons.bolt_outlined,
                color: amountColor,
                size: 38,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.sourceName} · ${draft.suggestedCategoryName.isEmpty ? draft.typeLabel : draft.suggestedCategoryName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatSignedMoney(draft.amount, draft.type),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ConfidencePill(value: draft.confidence),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onDismiss,
                child: const Text('忽略'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                key: ValueKey('smart-ledger-confirm-${draft.id}'),
                onPressed: busy ? null : onConfirm,
                child: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('确认'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round().clamp(0, 100);
    return Text(
      '$percent%',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ManualImportCard extends StatelessWidget {
  const _ManualImportCard({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      key: const ValueKey('smart-ledger-manual-import-card'),
      accentColor: Theme.of(context).colorScheme.tertiary,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconBadge(
            icon: Icons.content_paste_go_outlined,
            color: Theme.of(context).colorScheme.tertiary,
            size: 42,
            iconSize: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '文本导入',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '粘贴支付通知，本机解析后进入待确认。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const ValueKey('smart-ledger-open-import'),
            onPressed: onImport,
            child: const Text('粘贴'),
          ),
        ],
      ),
    );
  }
}

String _formatSignedMoney(double amount, TransactionType type) {
  final sign = type == TransactionType.income ? '+' : '-';
  return '$sign¥${amount.toStringAsFixed(2)}';
}

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}
