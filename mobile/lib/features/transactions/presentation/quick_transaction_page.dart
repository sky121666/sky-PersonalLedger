import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../attachments/data/attachment_cleanup.dart';
import '../../attachments/data/attachment_models.dart';
import '../../attachments/data/attachment_repository.dart';
import '../../attachments/presentation/attachment_picker_field.dart';
import '../../family/data/family_repository.dart';
import '../application/ledger_refresh.dart';
import '../data/transaction_models.dart';
import '../data/transaction_repository.dart';

class QuickTransactionPage extends ConsumerStatefulWidget {
  const QuickTransactionPage({
    this.editingTransaction,
    this.embedded = false,
    super.key,
  });

  final TransactionItem? editingTransaction;
  final bool embedded;

  @override
  ConsumerState<QuickTransactionPage> createState() =>
      _QuickTransactionPageState();
}

class _QuickTransactionPageState extends ConsumerState<QuickTransactionPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();
  final _customTagController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  DateTime _transactionDate = DateTime.now();
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  List<LedgerAccount> _accounts = const [];
  List<LedgerCategory> _categories = const [];
  List<LedgerTag> _tags = const [];
  List<FamilyMember> _familyMembers = const [];
  String? _memberId;
  List<LedgerAttachment> _attachments = const [];
  List<PendingAttachmentFile> _pendingAttachmentFiles = const [];
  List<AttachmentUploadProgress> _uploadProgress = const [];
  Set<String> _originalAttachmentPaths = const <String>{};
  final Set<String> _selectedTags = {};
  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.editingTransaction != null;

  String get _selectedAccountName {
    return _accounts
            .where((account) => account.id == _accountId)
            .map((account) => account.name)
            .firstOrNull ??
        '待选账户';
  }

  String get _selectedTargetName {
    if (_type == TransactionType.transfer) {
      return _accounts
              .where((account) => account.id == _toAccountId)
              .map((account) => account.name)
              .firstOrNull ??
          '待选转入';
    }
    return _categories
            .where((category) => category.id == _categoryId)
            .map((category) => category.name)
            .firstOrNull ??
        '待选分类';
  }

  String get _selectedFamilyMemberName {
    return _familyMembers
            .where((member) => member.id == _memberId)
            .map((member) => member.name)
            .firstOrNull ??
        (_familyMembers.isEmpty ? '个人记录' : '未指定成员');
  }

  /// 初始化交易表单基础数据。
  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  /// 释放交易表单资源。
  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    _customTagController.dispose();
    super.dispose();
  }

  /// 构建新增或编辑交易表单页面。
  @override
  Widget build(BuildContext context) {
    final themeSettings = ref.watch(themeControllerProvider);
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: widget.embedded,
              padding: EdgeInsets.zero,
              children: [
                if (_errorMessage != null) ...[
                  _buildErrorSurface(),
                  const SizedBox(height: 12),
                ],
                StaggeredEntrance(
                  index: 0,
                  child: PremiumSurface(
                    accentColor: _typeColor(context, _type),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuickTransactionHero(
                          type: _type,
                          amountController: _amountController,
                        ),
                        const SizedBox(height: 12),
                        _QuickEntryCommandStrip(
                          type: _type,
                          amountController: _amountController,
                          palette: themeSettings.palette,
                          accountName: _selectedAccountName,
                          targetName: _selectedTargetName,
                          familyName: _selectedFamilyMemberName,
                          tagCount: _selectedTags.length,
                          attachmentCount:
                              _attachments.length +
                              _pendingAttachmentFiles.length,
                        ),
                        const SizedBox(height: 12),
                        _QuickEntryReadinessPanel(
                          type: _type,
                          amountController: _amountController,
                          accountName: _selectedAccountName,
                          targetName: _selectedTargetName,
                          familyName: _selectedFamilyMemberName,
                          hasAccount: _accountId != null,
                          hasTarget: _type == TransactionType.transfer
                              ? _toAccountId != null
                              : _categoryId != null,
                          hasFamilyContext: _memberId != null,
                        ),
                        const SizedBox(height: 16),
                        _QuickEntryFlowPanel(
                          type: _type,
                          amountController: _amountController,
                          accountName: _selectedAccountName,
                          targetName: _selectedTargetName,
                          familyName: _selectedFamilyMemberName,
                          attachmentCount:
                              _attachments.length +
                              _pendingAttachmentFiles.length,
                        ),
                        const SizedBox(height: 16),
                        _TransactionTypeSelector(
                          selectedType: _type,
                          onSelected: (type) {
                            setState(() {
                              _type = type;
                              _categoryId = null;
                              _toAccountId = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _TransactionFlowHint(type: _type),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('transaction-amount'),
                          controller: _amountController,
                          autofocus: widget.embedded && !_isEditing,
                          decoration: InputDecoration(
                            labelText: '金额',
                            prefixText: '¥ ',
                            border: const OutlineInputBorder(),
                            prefixIcon: Icon(_typeIcon(_type)),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                          validator: _validateAmount,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                StaggeredEntrance(
                  index: 1,
                  child: PremiumSurface(
                    accentColor: AppTheme.financeColors(context).asset,
                    child: Column(
                      children: [
                        _buildAccountPicker(),
                        const SizedBox(height: 16),
                        if (_type == TransactionType.transfer)
                          _buildToAccountPicker()
                        else
                          _buildCategoryPicker(),
                        const SizedBox(height: 8),
                        _buildDateTimePicker(),
                        if (_familyMembers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildMemberPicker(),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                StaggeredEntrance(
                  index: 2,
                  child: PremiumSurface(
                    child: Column(
                      children: [
                        TextFormField(
                          key: const ValueKey('transaction-remark'),
                          controller: _remarkController,
                          decoration: const InputDecoration(
                            labelText: '备注',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 16),
                        _buildTagPicker(),
                        const SizedBox(height: 16),
                        AttachmentPickerField(
                          attachments: _attachments,
                          pendingFiles: _pendingAttachmentFiles,
                          uploadProgress: _uploadProgress,
                          enabled: !_submitting,
                          onAttachmentsChanged: (attachments) {
                            setState(() => _attachments = attachments);
                          },
                          onPendingFilesChanged: (files) {
                            setState(() => _pendingAttachmentFiles = files);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('transaction-save'),
                  onPressed: _submitting ? null : _submit,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_submitting)
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(_isEditing ? Icons.save_outlined : Icons.check),
                      const SizedBox(width: 8),
                      Text(_isEditing ? '保存修改' : '保存'),
                    ],
                  ),
                ),
              ],
            ),
          );

    if (widget.embedded) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? '编辑交易' : '记一笔',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                  ),
                ],
              ),
              Flexible(child: content),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '编辑交易' : '记一笔')),
      body: AdaptivePageContainer(child: content),
    );
  }

  Widget _buildErrorSurface() {
    return PremiumSurface(
      accentColor: Theme.of(context).colorScheme.error,
      child: Text(_errorMessage!),
    );
  }

  Widget _buildAccountPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _accountId,
      decoration: const InputDecoration(
        labelText: '账户',
        border: OutlineInputBorder(),
      ),
      items: _accounts
          .map(
            (account) =>
                DropdownMenuItem(value: account.id, child: Text(account.name)),
          )
          .toList(),
      validator: (value) => value == null || value.isEmpty ? '请选择账户' : null,
      onChanged: (value) => setState(() => _accountId = value),
    );
  }

  Widget _buildToAccountPicker() {
    final selectableAccounts = _accounts
        .where((account) => account.id != _accountId)
        .toList();
    return DropdownButtonFormField<String>(
      initialValue:
          selectableAccounts.any((account) => account.id == _toAccountId)
          ? _toAccountId
          : null,
      decoration: const InputDecoration(
        labelText: '转入账户',
        border: OutlineInputBorder(),
      ),
      items: selectableAccounts
          .map(
            (account) =>
                DropdownMenuItem(value: account.id, child: Text(account.name)),
          )
          .toList(),
      validator: (value) {
        if (_type != TransactionType.transfer) {
          return null;
        }
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

  Widget _buildCategoryPicker() {
    final selectableCategories = _categories
        .where((category) => category.type == _type.value)
        .toList();
    return DropdownButtonFormField<String>(
      initialValue:
          selectableCategories.any((category) => category.id == _categoryId)
          ? _categoryId
          : null,
      decoration: const InputDecoration(
        labelText: '分类',
        border: OutlineInputBorder(),
      ),
      items: selectableCategories
          .map(
            (category) => DropdownMenuItem(
              value: category.id,
              child: Text(category.name),
            ),
          )
          .toList(),
      validator: (value) {
        if (_type == TransactionType.transfer) {
          return null;
        }
        return value == null || value.isEmpty ? '请选择分类' : null;
      },
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }

  Widget _buildMemberPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _familyMembers.any((member) => member.id == _memberId)
          ? _memberId
          : null,
      decoration: const InputDecoration(
        labelText: '成员',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('不指定成员')),
        ..._familyMembers.map(
          (member) =>
              DropdownMenuItem(value: member.id, child: Text(member.name)),
        ),
      ],
      onChanged: (value) {
        setState(
          () => _memberId = value == null || value.isEmpty ? null : value,
        );
      },
    );
  }

  Widget _buildDateTimePicker() {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _typeColor(context, _type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _pickDateTime,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accentColor.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.14
                    : 0.08,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              IconBadge(
                icon: Icons.calendar_month_outlined,
                color: accentColor,
                size: 38,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '时间',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDateTime(_transactionDate),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('标签', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _tags)
              FilterChip(
                selected: _selectedTags.contains(tag.name),
                label: Text(tag.name),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedTags.add(tag.name);
                    } else {
                      _selectedTags.remove(tag.name);
                    }
                  });
                },
              ),
            for (final tagName in _selectedTags.where(
              (name) => !_tags.any((tag) => tag.name == name),
            ))
              InputChip(
                label: Text(tagName),
                onDeleted: () => setState(() => _selectedTags.remove(tagName)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('transaction-custom-tag'),
                controller: _customTagController,
                decoration: const InputDecoration(
                  labelText: '自定义标签',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addCustomTag(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _addCustomTag,
              icon: const Icon(Icons.add),
              tooltip: '添加标签',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _initializeForm() async {
    final transaction = widget.editingTransaction;
    if (transaction != null) {
      _type = transaction.type;
      _amountController.text = transaction.amount.toStringAsFixed(2);
      _remarkController.text = transaction.remark;
      _transactionDate = transaction.transactionDate;
      _accountId = transaction.accountId;
      _toAccountId = transaction.toAccountId;
      _categoryId = transaction.categoryId;
      _memberId = transaction.memberId;
      _selectedTags.addAll(transaction.tags);
      final attachmentPaths = decodeAttachmentPaths(transaction.images);
      _originalAttachmentPaths = attachmentPaths.toSet();
      _attachments = attachmentPaths.map(LedgerAttachment.fromPath).toList();
    }

    try {
      final repository = ref.read(transactionRepositoryProvider);
      final results = await Future.wait([
        repository.listAccounts(),
        repository.listCategories(),
        repository.listTags(),
      ]);
      final familyMembers = await _loadFamilyMembers();
      if (!mounted) {
        return;
      }
      setState(() {
        _accounts = results[0] as List<LedgerAccount>;
        _categories = results[1] as List<LedgerCategory>;
        _tags = results[2] as List<LedgerTag>;
        _familyMembers = familyMembers;
        _accountId ??= _accounts.isNotEmpty ? _accounts.first.id : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _loading = false;
      });
    }
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final formData = TransactionFormData(
      type: _type,
      amount: double.parse(_amountController.text),
      accountId: _accountId!,
      toAccountId: _type == TransactionType.transfer ? _toAccountId : null,
      categoryId: _type == TransactionType.transfer ? null : _categoryId,
      transactionDate: _transactionDate,
      remark: _remarkController.text,
      images: encodeAttachmentPaths(
        _attachments.map((item) => item.path).toList(),
      ),
      tags: _selectedTags.toList(),
      memberId: _memberId,
      paidByMemberId: _memberId,
    );

    try {
      final repository = ref.read(transactionRepositoryProvider);
      final savedTransaction = _isEditing
          ? await repository.update(widget.editingTransaction!.id, formData)
          : await repository.create(formData);
      final uploadedAttachments = await _uploadPendingAttachments(
        savedTransaction.id,
      );
      final allAttachments = [..._attachments, ...uploadedAttachments];
      if (_pendingAttachmentFiles.isNotEmpty ||
          encodeAttachmentPaths(
                allAttachments.map((item) => item.path).toList(),
              ) !=
              formData.images) {
        await repository.update(
          savedTransaction.id,
          TransactionFormData(
            type: _type,
            amount: double.parse(_amountController.text),
            accountId: _accountId!,
            toAccountId: _type == TransactionType.transfer
                ? _toAccountId
                : null,
            categoryId: _type == TransactionType.transfer ? null : _categoryId,
            transactionDate: _transactionDate,
            remark: _remarkController.text,
            images: encodeAttachmentPaths(
              allAttachments.map((item) => item.path).toList(),
            ),
            tags: _selectedTags.toList(),
            memberId: _memberId,
            paidByMemberId: _memberId,
          ),
        );
      }
      final failedCleanupPaths = await deleteRemovedAttachments(
        repository: ref.read(attachmentRepositoryProvider),
        originalPaths: _originalAttachmentPaths,
        retainedPaths: allAttachments.map((item) => item.path),
      );
      ref.invalidateLedgerMutationViews();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failedCleanupPaths.isEmpty
                  ? (_isEditing ? '交易已更新' : '交易已创建')
                  : '${_isEditing ? '交易已更新' : '交易已创建'}，但有 ${failedCleanupPaths.length} 个旧附件清理失败',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
          _submitting = false;
        });
      }
    }
  }

  Future<List<FamilyMember>> _loadFamilyMembers() async {
    try {
      return await ref.read(familyMembersProvider.future);
    } catch (_) {
      return const [];
    }
  }

  Future<List<LedgerAttachment>> _uploadPendingAttachments(
    String transactionId,
  ) async {
    if (_pendingAttachmentFiles.isEmpty) {
      return const [];
    }

    final repository = ref.read(attachmentRepositoryProvider);
    final uploadedAttachments = <LedgerAttachment>[];
    for (final file in _pendingAttachmentFiles) {
      if (mounted) {
        setState(() {
          _uploadProgress = [
            ..._uploadProgress.where((item) => item.fileName != file.name),
            AttachmentUploadProgress(fileName: file.name, progress: 0),
          ];
        });
      }
      final attachment = await repository.upload(
        file: file,
        category: 'transactions',
        refId: transactionId,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) {
            return;
          }
          setState(() {
            _uploadProgress = [
              ..._uploadProgress.where((item) => item.fileName != file.name),
              AttachmentUploadProgress(
                fileName: file.name,
                progress: sent / total,
              ),
            ];
          });
        },
      );
      uploadedAttachments.add(attachment);
      if (mounted) {
        setState(() {
          _uploadProgress = [
            ..._uploadProgress.where((item) => item.fileName != file.name),
            AttachmentUploadProgress(
              fileName: file.name,
              progress: 1,
              completed: true,
            ),
          ];
        });
      }
    }
    return uploadedAttachments;
  }

  String? _validateAmount(String? value) {
    final amount = double.tryParse(value ?? '');
    if (amount == null || amount <= 0) {
      return '请输入有效金额';
    }
    return null;
  }

  void _addCustomTag() {
    final tagName = _customTagController.text.trim();
    if (tagName.isEmpty) {
      return;
    }
    setState(() {
      _selectedTags.add(tagName);
      _customTagController.clear();
    });
  }
}

class _QuickTransactionHero extends StatelessWidget {
  const _QuickTransactionHero({
    required this.type,
    required this.amountController,
  });

  final TransactionType type;
  final TextEditingController amountController;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _typeColor(context, type);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accentColor.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.22
                    : 0.14,
              ),
              colorScheme.surface,
            ),
            Color.alphaBlend(
              colorScheme.primary.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.10
                    : 0.06,
              ),
              colorScheme.surface,
            ),
          ],
        ),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          IconBadge(
            icon: _typeIcon(type),
            color: accentColor,
            size: 48,
            iconSize: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type.label}金额',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedBuilder(
                  animation: amountController,
                  builder: (context, _) {
                    final amount = amountController.text.trim();
                    return Text(
                      amount.isEmpty ? '¥0.00' : '¥$amount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEntryCommandStrip extends StatelessWidget {
  const _QuickEntryCommandStrip({
    required this.type,
    required this.amountController,
    required this.palette,
    required this.accountName,
    required this.targetName,
    required this.familyName,
    required this.tagCount,
    required this.attachmentCount,
  });

  final TransactionType type;
  final TextEditingController amountController;
  final AppThemePalette palette;
  final String accountName;
  final String targetName;
  final String familyName;
  final int tagCount;
  final int attachmentCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final accentColor = _typeColor(context, type);
    final targetIcon = type == TransactionType.transfer
        ? Icons.swap_horiz_outlined
        : Icons.category_outlined;
    final targetLabel = type == TransactionType.transfer ? '流向' : '分类';

    return PremiumSurface(
      key: const ValueKey('quick-entry-command-strip'),
      accentColor: accentColor,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.tune_outlined,
                color: accentColor,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '记账指挥条',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedBuilder(
                      animation: amountController,
                      builder: (context, _) {
                        final amount = amountController.text.trim();
                        return Text(
                          amount.isEmpty
                              ? '${type.label} · 等待输入金额'
                              : '${type.label} · ¥$amount',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              _QuickEntrySignalPill(
                icon: Icons.palette_outlined,
                label: palette.label,
                color: palette.seedColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickEntrySignalPill(
                icon: Icons.account_balance_wallet_outlined,
                label: accountName,
                color: palette.assetColor,
              ),
              _QuickEntrySignalPill(
                icon: targetIcon,
                label: '$targetLabel $targetName',
                color: type == TransactionType.income
                    ? financeColors.income
                    : type == TransactionType.expense
                    ? financeColors.expense
                    : palette.assetColor,
              ),
              _QuickEntrySignalPill(
                icon: Icons.family_restroom_outlined,
                label: familyName,
                color: financeColors.asset,
              ),
              _QuickEntrySignalPill(
                icon: tagCount > 0
                    ? Icons.label_important_outline
                    : Icons.label_outline,
                label: tagCount > 0 ? '标签 $tagCount' : '无标签',
                color: colorScheme.secondary,
              ),
              _QuickEntrySignalPill(
                icon: attachmentCount > 0
                    ? Icons.attachment_outlined
                    : Icons.insert_drive_file_outlined,
                label: attachmentCount > 0 ? '附件 $attachmentCount' : '无附件',
                color: colorScheme.tertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickEntryReadinessPanel extends StatelessWidget {
  const _QuickEntryReadinessPanel({
    required this.type,
    required this.amountController,
    required this.accountName,
    required this.targetName,
    required this.familyName,
    required this.hasAccount,
    required this.hasTarget,
    required this.hasFamilyContext,
  });

  final TransactionType type;
  final TextEditingController amountController;
  final String accountName;
  final String targetName;
  final String familyName;
  final bool hasAccount;
  final bool hasTarget;
  final bool hasFamilyContext;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: amountController,
      builder: (context, _) {
        final amount = double.tryParse(amountController.text.trim()) ?? 0;
        final hasAmount = amount > 0;
        final readyCount = [
          hasAmount,
          hasAccount,
          hasTarget,
        ].where((item) => item).length;
        final progress = readyCount / 3;
        final accentColor = _typeColor(context, type);
        final colorScheme = Theme.of(context).colorScheme;
        final financeColors = AppTheme.financeColors(context);
        return AnimatedContainer(
          key: const ValueKey('quick-entry-readiness-panel'),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accentColor.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.16
                    : 0.08,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.rule_folder_outlined,
                    color: accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '录入质量层',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _QuickReadinessPill(
                    label: progress >= 1 ? '可保存' : '待补齐',
                    color: progress >= 1
                        ? financeColors.income
                        : financeColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: colorScheme.surfaceContainerHighest),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: ColoredBox(color: accentColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _QuickReadinessNode(
                      icon: Icons.payments_outlined,
                      label: '金额',
                      value: hasAmount ? '已输入' : '待输入',
                      color: hasAmount ? accentColor : colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickReadinessNode(
                      icon: Icons.account_balance_wallet_outlined,
                      label: '账户',
                      value: accountName,
                      color: hasAccount
                          ? AppTheme.financeColors(context).asset
                          : colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _QuickReadinessNode(
                      icon: type == TransactionType.transfer
                          ? Icons.swap_horiz_outlined
                          : Icons.category_outlined,
                      label: type == TransactionType.transfer ? '流向' : '分类',
                      value: targetName,
                      color: hasTarget ? accentColor : colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickReadinessNode(
                      icon: Icons.diversity_3_outlined,
                      label: '归属',
                      value: familyName,
                      color: hasFamilyContext
                          ? colorScheme.tertiary
                          : colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickReadinessNode extends StatelessWidget {
  const _QuickReadinessNode({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickReadinessPill extends StatelessWidget {
  const _QuickReadinessPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 30, maxWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QuickEntrySignalPill extends StatelessWidget {
  const _QuickEntrySignalPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 34, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.10,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickEntryFlowPanel extends StatelessWidget {
  const _QuickEntryFlowPanel({
    required this.type,
    required this.amountController,
    required this.accountName,
    required this.targetName,
    required this.familyName,
    required this.attachmentCount,
  });

  final TransactionType type;
  final TextEditingController amountController;
  final String accountName;
  final String targetName;
  final String familyName;
  final int attachmentCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: amountController,
      builder: (context, _) {
        final amount = amountController.text.trim();
        final hasAmount = (double.tryParse(amount) ?? 0) > 0;
        final accentColor = _typeColor(context, type);
        final colorScheme = Theme.of(context).colorScheme;
        final flowLabel = type == TransactionType.transfer ? '转账动线' : '记账动线';
        final targetLabel = type == TransactionType.transfer ? '转入' : '分类';
        return AnimatedContainer(
          key: const ValueKey('quick-entry-flow-panel'),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accentColor.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.14
                    : 0.07,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.route_outlined, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      flowLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _QuickReadinessPill(
                    label: hasAmount ? '金额就绪' : '等待金额',
                    color: hasAmount
                        ? AppTheme.financeColors(context).income
                        : AppTheme.financeColors(context).warning,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickEntryFlowNode(
                      icon: Icons.account_balance_wallet_outlined,
                      label: '账户',
                      value: accountName,
                      color: AppTheme.financeColors(context).asset,
                    ),
                  ),
                  _QuickFlowConnector(color: accentColor),
                  Expanded(
                    child: _QuickEntryFlowNode(
                      icon: type == TransactionType.transfer
                          ? Icons.swap_horiz_outlined
                          : Icons.category_outlined,
                      label: targetLabel,
                      value: targetName,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumn = constraints.maxWidth >= 390;
                  final gap = twoColumn ? 8.0 : 8.0;
                  final width = twoColumn
                      ? (constraints.maxWidth - gap) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: gap,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: width,
                        child: _QuickEntryFlowMeta(
                          icon: Icons.diversity_3_outlined,
                          label: '家庭归属',
                          value: familyName,
                          color: colorScheme.tertiary,
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _QuickEntryFlowMeta(
                          icon: attachmentCount > 0
                              ? Icons.attachment_outlined
                              : Icons.insert_drive_file_outlined,
                          label: '凭证状态',
                          value: attachmentCount > 0
                              ? '$attachmentCount 个附件'
                              : '无附件',
                          color: colorScheme.secondary,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickEntryFlowNode extends StatelessWidget {
  const _QuickEntryFlowNode({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickFlowConnector extends StatelessWidget {
  const _QuickFlowConnector({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: Center(
        child: Icon(Icons.arrow_forward_rounded, color: color, size: 20),
      ),
    );
  }
}

class _QuickEntryFlowMeta extends StatelessWidget {
  const _QuickEntryFlowMeta({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionFlowHint extends StatelessWidget {
  const _TransactionFlowHint({required this.type});

  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _typeColor(context, type);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accentColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(_typeHintIcon(type), color: accentColor, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeHintTitle(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _typeHintDescription(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTypeSelector extends StatelessWidget {
  const _TransactionTypeSelector({
    required this.selectedType,
    required this.onSelected,
  });

  final TransactionType selectedType;
  final ValueChanged<TransactionType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final type in TransactionType.values) ...[
          Expanded(
            child: _TransactionTypeCard(
              type: type,
              selected: selectedType == type,
              onTap: () => onSelected(type),
            ),
          ),
          if (type != TransactionType.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _TransactionTypeCard extends StatelessWidget {
  const _TransactionTypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final TransactionType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = _typeColor(context, type);
    return Semantics(
      button: true,
      selected: selected,
      label: type.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 74),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      accentColor.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.20
                            : 0.12,
                      ),
                      colorScheme.surface,
                    )
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? accentColor
                    : colorScheme.outlineVariant.withValues(alpha: 0.74),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _typeIcon(type),
                  color: selected ? accentColor : colorScheme.onSurfaceVariant,
                  size: 21,
                ),
                const SizedBox(height: 6),
                Text(
                  type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? accentColor
                        : colorScheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _typeColor(BuildContext context, TransactionType type) {
  final financeColors = AppTheme.financeColors(context);
  final colorScheme = Theme.of(context).colorScheme;
  return switch (type) {
    TransactionType.income => financeColors.income,
    TransactionType.expense => financeColors.expense,
    TransactionType.transfer => colorScheme.primary,
  };
}

IconData _typeIcon(TransactionType type) {
  return switch (type) {
    TransactionType.income => Icons.south_west,
    TransactionType.expense => Icons.north_east,
    TransactionType.transfer => Icons.swap_horiz,
  };
}

IconData _typeHintIcon(TransactionType type) {
  return switch (type) {
    TransactionType.income => Icons.account_balance_wallet_outlined,
    TransactionType.expense => Icons.category_outlined,
    TransactionType.transfer => Icons.compare_arrows_outlined,
  };
}

String _typeHintTitle(TransactionType type) {
  return switch (type) {
    TransactionType.income => '记录收入来源',
    TransactionType.expense => '选择支出分类',
    TransactionType.transfer => '确认转入账户',
  };
}

String _typeHintDescription(TransactionType type) {
  return switch (type) {
    TransactionType.income => '填写到账账户、收入分类和可选标签',
    TransactionType.expense => '金额、账户和分类是保存前的关键字段',
    TransactionType.transfer => '转出账户和转入账户不能相同',
  };
}

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}
