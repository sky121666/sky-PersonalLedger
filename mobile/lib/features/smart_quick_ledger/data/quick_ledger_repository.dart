import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../transactions/data/transaction_models.dart';
import '../../transactions/data/transaction_repository.dart';
import 'quick_ledger_draft.dart';
import 'quick_ledger_text_parser.dart';

final quickLedgerDraftsProvider =
    StateNotifierProvider<QuickLedgerDraftController, List<QuickLedgerDraft>>((
      ref,
    ) {
      final controller = QuickLedgerDraftController(
        transactionWriter: TransactionRepositoryQuickLedgerWriter(
          ref.watch(transactionRepositoryProvider),
        ),
        platformClient: const MethodChannelQuickLedgerPlatformClient(),
        initialDrafts: const [],
      );
      unawaited(controller.loadFromPlatform());
      return controller;
    });

class QuickLedgerDraftController extends StateNotifier<List<QuickLedgerDraft>> {
  QuickLedgerDraftController({
    required QuickLedgerTransactionWriter transactionWriter,
    QuickLedgerPlatformClient platformClient =
        const NoopQuickLedgerPlatformClient(),
    List<QuickLedgerDraft>? initialDrafts,
  }) : _transactionWriter = transactionWriter,
       _platformClient = platformClient,
       super(initialDrafts ?? const []);

  final QuickLedgerTransactionWriter _transactionWriter;
  final QuickLedgerPlatformClient _platformClient;

  Future<void> loadFromPlatform() async {
    final drafts = await _platformClient.getPendingDrafts();
    if (drafts.isNotEmpty) {
      state = drafts;
    }
  }

  Future<bool> isNotificationListenerEnabled() {
    return _platformClient.isNotificationListenerEnabled();
  }

  Future<void> openNotificationListenerSettings() {
    return _platformClient.openNotificationListenerSettings();
  }

  Future<Set<String>> getEnabledSources() {
    return _platformClient.getEnabledSources();
  }

  Future<void> setEnabledSources(Set<String> sources) {
    return _platformClient.setEnabledSources(sources);
  }

  QuickLedgerDraft importText(String text) {
    final draft = QuickLedgerTextParser.parse(text);
    if (draft == null) {
      throw const FormatException('未识别到明确的收支金额');
    }
    state = [draft, ...state.where((item) => item.id != draft.id)];
    return draft;
  }

  Future<void> dismiss(String id) async {
    state = state.where((draft) => draft.id != id).toList();
    await _platformClient.dismissDraft(id);
  }

  Future<QuickLedgerConfirmationOptions> loadConfirmationOptions() async {
    final accounts = await _transactionWriter.listAccounts();
    final categories = await _transactionWriter.listCategories();
    return QuickLedgerConfirmationOptions(
      accounts: accounts.where((account) => !account.isArchived).toList(),
      categories: categories,
    );
  }

  Future<TransactionItem> confirm(
    String id,
    TransactionFormData formData,
  ) async {
    if (!state.any((item) => item.id == id)) {
      throw const FormatException('候选已不存在');
    }

    _validateAmount(formData.amount);
    final accounts = await _transactionWriter.listAccounts();
    _validateAccount(accounts, formData.accountId, errorMessage: '所选账户不可用或已归档');

    if (formData.type == TransactionType.transfer) {
      final toAccountId = formData.toAccountId;
      if (toAccountId == null || toAccountId.isEmpty) {
        throw const FormatException('请选择转入账户');
      }
      if (toAccountId == formData.accountId) {
        throw const FormatException('转出和转入账户不能相同');
      }
      _validateAccount(accounts, toAccountId, errorMessage: '所选转入账户不可用或已归档');
    } else {
      final categoryId = formData.categoryId;
      if (categoryId == null || categoryId.isEmpty) {
        throw const FormatException('请选择分类');
      }
      final categories = await _transactionWriter.listCategories();
      final category = _findCategory(categories, categoryId);
      if (category == null) {
        throw const FormatException('所选分类不可用');
      }
      if (category.type != formData.type.value) {
        throw const FormatException('分类与收支方向不匹配');
      }
    }

    final transaction = await _transactionWriter.create(formData);
    await dismiss(id);
    return transaction;
  }

  static void _validateAmount(double amount) {
    if (!amount.isFinite || amount <= 0) {
      throw const FormatException('请输入有效金额');
    }
  }

  static void _validateAccount(
    List<LedgerAccount> accounts,
    String accountId, {
    required String errorMessage,
  }) {
    final account = _findAccount(accounts, accountId);
    if (account == null || account.isArchived) {
      throw FormatException(errorMessage);
    }
  }

  static LedgerAccount? _findAccount(List<LedgerAccount> accounts, String id) {
    for (final account in accounts) {
      if (account.id == id) {
        return account;
      }
    }
    return null;
  }

  static LedgerCategory? _findCategory(
    List<LedgerCategory> categories,
    String id,
  ) {
    for (final category in categories) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }
}

class QuickLedgerConfirmationOptions {
  const QuickLedgerConfirmationOptions({
    required this.accounts,
    required this.categories,
  });

  final List<LedgerAccount> accounts;
  final List<LedgerCategory> categories;
}

abstract class QuickLedgerPlatformClient {
  Future<bool> isNotificationListenerEnabled();

  Future<void> openNotificationListenerSettings();

  Future<List<QuickLedgerDraft>> getPendingDrafts();

  Future<void> dismissDraft(String id);

  Future<Set<String>> getEnabledSources();

  Future<void> setEnabledSources(Set<String> sources);
}

class MethodChannelQuickLedgerPlatformClient
    implements QuickLedgerPlatformClient {
  const MethodChannelQuickLedgerPlatformClient();

  static const _channel = MethodChannel('personal_ledger/smart_quick_ledger');

  @override
  Future<bool> isNotificationListenerEnabled() async {
    return await _safeInvoke<bool>('isNotificationListenerEnabled') ?? false;
  }

  @override
  Future<void> openNotificationListenerSettings() async {
    await _safeInvoke<void>('openNotificationListenerSettings');
  }

  @override
  Future<List<QuickLedgerDraft>> getPendingDrafts() async {
    final raw = await _safeInvoke<List<dynamic>>('getPendingDrafts');
    if (raw == null) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .map(QuickLedgerDraft.fromJson)
        .where((draft) => draft.id.isNotEmpty)
        .toList();
  }

  @override
  Future<void> dismissDraft(String id) async {
    await _safeInvoke<void>('dismissDraft', {'id': id});
  }

  @override
  Future<Set<String>> getEnabledSources() async {
    final raw = await _safeInvoke<List<dynamic>>('getEnabledSources');
    return raw?.whereType<String>().toSet() ?? {'wechat', 'alipay', 'bank'};
  }

  @override
  Future<void> setEnabledSources(Set<String> sources) async {
    await _safeInvoke<void>('setEnabledSources', {'sources': sources.toList()});
  }

  Future<T?> _safeInvoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

class NoopQuickLedgerPlatformClient implements QuickLedgerPlatformClient {
  const NoopQuickLedgerPlatformClient();

  @override
  Future<bool> isNotificationListenerEnabled() async => false;

  @override
  Future<void> openNotificationListenerSettings() async {}

  @override
  Future<List<QuickLedgerDraft>> getPendingDrafts() async => const [];

  @override
  Future<void> dismissDraft(String id) async {}

  @override
  Future<Set<String>> getEnabledSources() async => {'wechat', 'alipay', 'bank'};

  @override
  Future<void> setEnabledSources(Set<String> sources) async {}
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
