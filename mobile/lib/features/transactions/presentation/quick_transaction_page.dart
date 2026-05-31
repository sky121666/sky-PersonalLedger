import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
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

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}
