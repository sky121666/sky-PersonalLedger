import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/premium_surface.dart';
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
  bool _showMoreOptions = false;
  bool _showCustomTagInput = false;
  bool _secondaryDataLoaded = false;
  bool _loadingSecondaryData = false;
  String? _errorMessage;

  bool get _isEditing => widget.editingTransaction != null;
  bool get _isEmbedded => widget.embedded;

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
    final formRows = _loading ? const <Widget>[] : _quickTransactionRows;
    final content = _loading
        ? SizedBox(
            height: _isEmbedded ? 220 : 320,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.6)),
          )
        : Form(
            key: _formKey,
            child: ListView.builder(
              shrinkWrap: widget.embedded,
              physics: widget.embedded
                  ? const ClampingScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: widget.embedded ? 8 : 24),
              itemCount: formRows.length,
              itemBuilder: (context, index) => formRows[index],
            ),
          );

    if (widget.embedded) {
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 6),
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
                    tooltip: _isEditing ? '关闭编辑交易表单' : '关闭记一笔表单',
                  ),
                ],
              ),
              const SizedBox(height: 4),
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

  List<Widget> get _quickTransactionRows {
    return [
      if (_errorMessage != null) ...[
        _buildErrorSurface(),
        const SizedBox(height: 12),
      ],
      _buildPrimaryAmountSection(),
      const SizedBox(height: 8),
      _buildRequiredPickersSection(),
      const SizedBox(height: 8),
      _buildOptionalFieldsSection(),
      const SizedBox(height: 12),
      _buildSaveButton(),
    ];
  }

  Widget _buildPrimaryAmountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('transaction-amount'),
          controller: _amountController,
          autofocus: false,
          decoration: _fieldDecoration(
            labelText: '金额',
            icon: _typeIcon(_type),
          ).copyWith(prefixText: '¥ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          validator: _validateAmount,
        ),
      ],
    );
  }

  Widget _buildRequiredPickersSection() {
    return Column(
      children: [
        _buildAccountPicker(),
        const SizedBox(height: 8),
        if (_type == TransactionType.transfer)
          _buildToAccountPicker()
        else
          _buildCategoryPicker(),
        const SizedBox(height: 8),
        _buildDateTimePicker(),
      ],
    );
  }

  Widget _buildOptionalFieldsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton.filledTonal(
            key: const ValueKey('transaction-more-options'),
            onPressed: () {
              final next = !_showMoreOptions;
              setState(() => _showMoreOptions = next);
              if (next) {
                _ensureSecondaryDataLoaded();
              }
            },
            icon: Icon(_showMoreOptions ? Icons.close : Icons.add),
            iconSize: 20,
            tooltip: _showMoreOptions ? '收起备注和附件' : '添加可选信息',
          ),
        ),
        if (_showMoreOptions) ...[
          const SizedBox(height: 6),
          PremiumSurface(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                if (_loadingSecondaryData)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                TextFormField(
                  key: const ValueKey('transaction-remark'),
                  controller: _remarkController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                if (_familyMembers.isNotEmpty) ...[
                  _buildMemberPicker(),
                  const SizedBox(height: 8),
                ],
                _buildTagPicker(),
                const SizedBox(height: 8),
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
        ],
      ],
    );
  }

  Widget _buildSaveButton() {
    return FilledButton(
      key: const ValueKey('transaction-save'),
      onPressed: _submitting ? null : _submit,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
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
          Text(_isEditing ? '保存修改' : '记一笔'),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w800,
      ),
      filled: true,
      fillColor: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.035),
        colorScheme.surface,
      ),
      prefixIcon: Icon(icon, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
      ),
    );
  }

  Widget _buildAccountPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _accountId,
      decoration: _fieldDecoration(
        labelText: '账户',
        icon: Icons.account_balance_wallet_outlined,
      ),
      menuMaxHeight: 360,
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
      decoration: _fieldDecoration(
        labelText: '转入账户',
        icon: Icons.move_down_outlined,
      ),
      menuMaxHeight: 360,
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
      decoration: _fieldDecoration(
        labelText: '分类',
        icon: Icons.category_outlined,
      ),
      menuMaxHeight: 360,
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
      decoration: _fieldDecoration(labelText: '成员', icon: Icons.group_outlined),
      menuMaxHeight: 360,
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              Icon(Icons.calendar_month_outlined, color: accentColor, size: 20),
              const SizedBox(width: 10),
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
        Row(
          children: [
            Expanded(
              child: Text('标签', style: Theme.of(context).textTheme.titleSmall),
            ),
            Tooltip(
              message: '添加标签',
              child: TextButton(
                onPressed: () {
                  if (_showCustomTagInput) {
                    _addCustomTag();
                    return;
                  }
                  setState(() => _showCustomTagInput = true);
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(68, 30),
                ),
                child: Text(_showCustomTagInput ? '保存' : '添加标签'),
              ),
            ),
          ],
        ),
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
        if (_showCustomTagInput) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('transaction-custom-tag'),
            controller: _customTagController,
            decoration: _fieldDecoration(
              labelText: '新标签',
              icon: Icons.sell_outlined,
            ),
            onSubmitted: (_) => _addCustomTag(),
          ),
        ],
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
      _showMoreOptions =
          transaction.remark.trim().isNotEmpty ||
          transaction.memberId != null ||
          transaction.tags.isNotEmpty ||
          attachmentPaths.isNotEmpty;
    }

    try {
      final repository = ref.read(transactionRepositoryProvider);
      final results = await Future.wait([
        repository.listAccounts(),
        repository.listCategories(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _accounts = results[0] as List<LedgerAccount>;
        _categories = results[1] as List<LedgerCategory>;
        _accountId ??= _accounts.isNotEmpty ? _accounts.first.id : null;
        _loading = false;
      });
      if (_showMoreOptions) {
        _ensureSecondaryDataLoaded();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '记账信息加载失败';
        _loading = false;
      });
    }
  }

  void _ensureSecondaryDataLoaded() {
    if (_secondaryDataLoaded || _loadingSecondaryData) {
      return;
    }
    unawaited(_loadSecondaryFormData());
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
                  : '${_isEditing ? '交易已更新' : '交易已创建'}，附件稍后处理',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = _isEditing ? '交易保存失败' : '记账失败';
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

  Future<void> _loadSecondaryFormData() async {
    if (_secondaryDataLoaded || _loadingSecondaryData) {
      return;
    }
    setState(() {
      _loadingSecondaryData = true;
    });
    try {
      final repository = ref.read(transactionRepositoryProvider);
      final results = await Future.wait([
        repository.listTags(),
        _loadFamilyMembers(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _tags = results[0] as List<LedgerTag>;
        _familyMembers = results[1] as List<FamilyMember>;
      });
    } catch (_) {
      // Optional fields should not block the primary transaction form.
    } finally {
      if (mounted) {
        setState(() {
          _secondaryDataLoaded = true;
          _loadingSecondaryData = false;
        });
      }
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
      _showCustomTagInput = false;
    });
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
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _typeIcon(type),
                  color: selected ? accentColor : colorScheme.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 6),
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

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}
