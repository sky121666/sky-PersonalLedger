import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../transactions/data/transaction_models.dart';
import '../../transactions/data/transaction_repository.dart';
import 'quick_ledger_draft.dart';

final quickLedgerDraftsProvider =
    StateNotifierProvider<QuickLedgerDraftController, List<QuickLedgerDraft>>((
      ref,
    ) {
      return QuickLedgerDraftController(
        transactionWriter: TransactionRepositoryQuickLedgerWriter(
          ref.watch(transactionRepositoryProvider),
        ),
      );
    });

class QuickLedgerDraftController extends StateNotifier<List<QuickLedgerDraft>> {
  QuickLedgerDraftController({
    required QuickLedgerTransactionWriter transactionWriter,
  }) : _transactionWriter = transactionWriter,
       super(_initialDrafts());

  final QuickLedgerTransactionWriter _transactionWriter;

  void dismiss(String id) {
    state = state.where((draft) => draft.id != id).toList();
  }

  Future<TransactionItem> confirm(String id) async {
    final draft = state.firstWhere((item) => item.id == id);
    final accounts = await _transactionWriter.listAccounts();
    final accountId = _resolveAccountId(draft, accounts);
    if (accountId == null) {
      throw const FormatException('缺少可用账户');
    }

    String? categoryId;
    if (draft.type != TransactionType.transfer) {
      final categories = await _transactionWriter.listCategories(
        type: draft.type.value,
      );
      categoryId = _resolveCategoryId(draft, categories);
      if (categoryId == null) {
        throw const FormatException('缺少可用分类');
      }
    }

    final transaction = await _transactionWriter.create(
      draft.toFormData(accountId: accountId, categoryId: categoryId),
    );
    dismiss(id);
    return transaction;
  }

  static String? _resolveAccountId(
    QuickLedgerDraft draft,
    List<LedgerAccount> accounts,
  ) {
    if (draft.suggestedAccountId != null &&
        accounts.any((account) => account.id == draft.suggestedAccountId)) {
      return draft.suggestedAccountId;
    }
    final active = accounts.where((account) => !account.isArchived).toList();
    return active.isEmpty ? null : active.first.id;
  }

  static String? _resolveCategoryId(
    QuickLedgerDraft draft,
    List<LedgerCategory> categories,
  ) {
    if (draft.suggestedCategoryId != null &&
        categories.any(
          (category) => category.id == draft.suggestedCategoryId,
        )) {
      return draft.suggestedCategoryId;
    }
    return categories.isEmpty ? null : categories.first.id;
  }
}

abstract class QuickLedgerTransactionWriter {
  Future<List<LedgerAccount>> listAccounts();

  Future<List<LedgerCategory>> listCategories({String? type});

  Future<TransactionItem> create(TransactionFormData formData);
}

class TransactionRepositoryQuickLedgerWriter
    implements QuickLedgerTransactionWriter {
  const TransactionRepositoryQuickLedgerWriter(this._repository);

  final TransactionRepository _repository;

  @override
  Future<List<LedgerAccount>> listAccounts() {
    return _repository.listAccounts();
  }

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) {
    return _repository.listCategories(type: type);
  }

  @override
  Future<TransactionItem> create(TransactionFormData formData) {
    return _repository.create(formData);
  }
}

List<QuickLedgerDraft> _initialDrafts() {
  final now = DateTime.now();
  return [
    QuickLedgerDraft(
      id: 'draft-wechat-coffee',
      source: QuickLedgerDraftSource.androidNotification,
      sourceName: '微信支付',
      type: TransactionType.expense,
      amount: 38.9,
      merchant: '瑞幸咖啡',
      occurredAt: DateTime(now.year, now.month, now.day, 9, 18),
      confidence: 0.92,
      suggestedAccountName: '微信钱包',
      suggestedCategoryName: '餐饮',
      rawText: '微信支付收款方 瑞幸咖啡 ¥38.90',
      notificationHash: 'wechat-coffee-3890',
    ),
    QuickLedgerDraft(
      id: 'draft-alipay-transport',
      source: QuickLedgerDraftSource.androidNotification,
      sourceName: '支付宝',
      type: TransactionType.expense,
      amount: 12.0,
      merchant: '地铁出行',
      occurredAt: DateTime(now.year, now.month, now.day, 8, 42),
      confidence: 0.88,
      suggestedAccountName: '支付宝',
      suggestedCategoryName: '交通',
      rawText: '支付宝付款 地铁出行 12.00元',
      notificationHash: 'alipay-transport-1200',
    ),
  ];
}
