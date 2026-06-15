import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../transactions/data/transaction_models.dart';
import '../../transactions/data/transaction_repository.dart';
import 'quick_ledger_draft.dart';

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

  Future<void> dismiss(String id) async {
    state = state.where((draft) => draft.id != id).toList();
    await _platformClient.dismissDraft(id);
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
    await dismiss(id);
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
