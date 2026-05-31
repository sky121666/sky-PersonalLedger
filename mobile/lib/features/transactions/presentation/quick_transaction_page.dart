import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../../app/widgets/adaptive_page_container.dart';
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
                    accentColor: Theme.of(context).colorScheme.primary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SegmentedButton<TransactionType>(
                          segments: TransactionType.values
                              .map(
                                (type) => ButtonSegment(
                                  value: type,
                                  label: Text(type.label),
                                ),
                              )
                              .toList(),
                          selected: {_type},
                          onSelectionChanged: (values) {
                            setState(() {
                              _type = values.first;
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
                          decoration: const InputDecoration(
                            labelText: '金额',
                            prefixText: '¥ ',
                            border: OutlineInputBorder(),
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
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? '保存修改' : '保存'),
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
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('时间'),
        subtitle: Text(_formatDateTime(_transactionDate)),
        trailing: const Icon(Icons.calendar_month_outlined),
        onTap: _pickDateTime,
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

String _formatDateTime(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}-$month-$day $hour:$minute';
}
