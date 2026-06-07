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
import 'widgets/quick_transaction_pickers.dart';

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
  bool _showTagList = false;
  bool _secondaryDataLoaded = false;
  bool _loadingSecondaryData = false;
  String? _errorMessage;

  static List<LedgerAccount> _accountCache = const [];
  static List<LedgerCategory> _categoryCache = const [];
  static List<LedgerTag> _tagCache = const [];
  static List<FamilyMember> _familyMemberCache = const [];
  static bool _primaryDataLoaded = false;
  static bool _secondaryDataLoadedCache = false;

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
            top: 2,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? '编辑交易' : '记一笔',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _buildMoreOptionsAction(),
                ],
              ),
              const SizedBox(height: 2),
              Flexible(child: content),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑交易' : '记一笔'),
        actions: [_buildMoreOptionsAction()],
      ),
      body: AdaptivePageContainer(child: content),
    );
  }

  Widget _buildMoreOptionsAction() {
    return SizedBox(
      key: const ValueKey('transaction-more-options'),
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: _toggleMoreOptions,
        visualDensity: VisualDensity.standard,
        padding: EdgeInsets.zero,
        iconSize: 18,
        tooltip: null,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          fixedSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: Icon(
          _showMoreOptions
              ? Icons.keyboard_arrow_up_rounded
              : Icons.add_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTagToggleButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      key: key,
      onPressed: onPressed,
      tooltip: null,
      padding: EdgeInsets.zero,
      iconSize: 20,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        fixedSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: Icon(icon),
      color: Theme.of(context).colorScheme.primary,
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
        if (_showMoreOptions) ...[
          if (_loadingSecondaryData) ...[
            const SizedBox(
              height: 44,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            const SizedBox(height: 8),
          ],
          if (_familyMembers.isNotEmpty) ...[
            _buildMemberPicker(),
            const SizedBox(height: 8),
          ],
          TextFormField(
            key: const ValueKey('transaction-remark'),
            controller: _remarkController,
            decoration: _fieldDecoration(
              labelText: '备注',
              icon: Icons.notes_outlined,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
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
      ],
    );
  }

  Widget _buildSaveButton() {
    return FilledButton(
      key: const ValueKey('transaction-save'),
      onPressed: _submitting ? null : _submit,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        colorScheme.primary.withValues(alpha: 0.02),
        colorScheme.surface,
      ),
      prefixIcon: Icon(icon, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
      ),
    );
  }

  Widget _buildAccountPicker() {
    return QuickTransactionDropdownField(
      value: _accountId,
      label: '账户',
      icon: Icons.account_balance_wallet_outlined,
      items: _accounts
          .map(
            (account) => DropdownMenuItem<String>(
              value: account.id,
              child: Text(account.name),
            ),
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
    return QuickTransactionDropdownField(
      value: selectableAccounts.any((account) => account.id == _toAccountId)
          ? _toAccountId
          : null,
      label: '转入账户',
      icon: Icons.move_down_outlined,
      items: selectableAccounts
          .map(
            (account) => DropdownMenuItem<String>(
              value: account.id,
              child: Text(account.name),
            ),
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
    return QuickTransactionDropdownField(
      value: selectableCategories.any((category) => category.id == _categoryId)
          ? _categoryId
          : null,
      label: '分类',
      icon: Icons.category_outlined,
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
    return QuickTransactionDropdownField(
      value: _familyMembers.any((member) => member.id == _memberId)
          ? _memberId
          : null,
      label: '成员',
      icon: Icons.group_outlined,
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('不指定成员')),
        ..._familyMembers.map(
          (member) => DropdownMenuItem<String>(
            value: member.id,
            child: Text(member.name),
          ),
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
        borderRadius: BorderRadius.circular(12),
        onTap: _pickDateTime,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accentColor.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.10
                    : 0.04,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withValues(alpha: 0.12)),
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
    final selectedTags = _selectedTags.toList();
    final compactSelectedTags = selectedTags.take(2).toList();
    final moreSelectedCount = selectedTags.length - compactSelectedTags.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.sell_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text('标签', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (selectedTags.isNotEmpty)
              Flexible(
                child: Row(
                  children: [
                    for (final tag in compactSelectedTags)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          label: Text(
                            tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onSelected: null,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (moreSelectedCount > 0)
                      Text(
                        '+$moreSelectedCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox.shrink(),
            const SizedBox(width: 6),
            _buildTagToggleButton(
              key: const ValueKey('transaction-add-custom-tag'),
              icon: _showTagList
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              onPressed: _toggleTagInput,
            ),
          ],
        ),
        if (_showTagList) ...[
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
                  onDeleted: () =>
                      setState(() => _selectedTags.remove(tagName)),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (_showCustomTagInput) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('transaction-custom-tag'),
            controller: _customTagController,
            textInputAction: TextInputAction.done,
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

  void _toggleMoreOptions() {
    final targetShowMoreOptions = !_showMoreOptions;

    if (targetShowMoreOptions) {
      unawaited(_ensureSecondaryDataLoaded());
    }

    setState(() => _showMoreOptions = targetShowMoreOptions);
  }

  void _toggleTagInput() {
    final shouldShow = !_showTagList;
    setState(() {
      _showTagList = shouldShow;
      _showCustomTagInput = shouldShow;
    });
    if (!_showTagList) {
      _customTagController.clear();
    }
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
      _showMoreOptions = false;
    }

    if (_primaryDataLoaded) {
      setState(() {
        _accounts = _accountCache;
        _categories = _categoryCache;
        _loading = false;
        _accountId ??= _accounts.isNotEmpty ? _accounts.first.id : null;
      });
      unawaited(_ensureSecondaryDataLoaded());
      return;
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

      final accounts = results[0] as List<LedgerAccount>;
      final categories = results[1] as List<LedgerCategory>;
      setState(() {
        _accounts = accounts;
        _categories = categories;
        _accountId ??= _accounts.isNotEmpty ? _accounts.first.id : null;
        _loading = false;
      });

      _accountCache = accounts;
      _categoryCache = categories;
      _primaryDataLoaded = true;
      unawaited(_ensureSecondaryDataLoaded());
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

  Future<void> _ensureSecondaryDataLoaded() async {
    if (_secondaryDataLoaded || _loadingSecondaryData) {
      return;
    }
    await _loadSecondaryFormData();
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
                  : '${_isEditing ? '交易已更新' : '交易已创建'}，附件处理中',
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

    if (_secondaryDataLoadedCache) {
      setState(() {
        _tags = _tagCache;
        _familyMembers = _familyMemberCache;
        _secondaryDataLoaded = true;
      });
      if (_familyMemberCache.isNotEmpty) {
        return;
      }
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
      final tags = results[0] as List<LedgerTag>;
      final familyMembers = results[1] as List<FamilyMember>;
      setState(() {
        _tags = tags;
        _familyMembers = familyMembers;
      });
      _tagCache = tags;
      _familyMemberCache = familyMembers;
      _secondaryDataLoadedCache = true;
    } catch (_) {
      // Optional fields should not block the primary transaction form.
      _secondaryDataLoadedCache = true;
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
      setState(() => _showCustomTagInput = false);
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
