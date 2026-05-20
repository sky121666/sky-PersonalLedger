import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/transaction_models.dart';
import '../data/transaction_repository.dart';

final transactionListControllerProvider =
    StateNotifierProvider.autoDispose<
      TransactionListController,
      TransactionListState
    >((ref) {
      return TransactionListController(ref.watch(transactionRepositoryProvider))
        ..refresh();
    });

class TransactionListState {
  const TransactionListState({
    this.items = const [],
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.keyword = '',
    this.type,
    this.accountId,
    this.categoryId,
  });

  final List<TransactionItem> items;
  final int page;
  final int pageSize;
  final int total;
  final bool isLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? errorMessage;
  final String keyword;
  final TransactionType? type;
  final String? accountId;
  final String? categoryId;

  bool get hasMore => page * pageSize < total;

  bool get hasActiveFilter {
    return keyword.trim().isNotEmpty ||
        type != null ||
        (accountId != null && accountId!.isNotEmpty) ||
        (categoryId != null && categoryId!.isNotEmpty);
  }

  TransactionListState copyWith({
    List<TransactionItem>? items,
    int? page,
    int? pageSize,
    int? total,
    bool? isLoading,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? errorMessage,
    String? keyword,
    TransactionType? type,
    String? accountId,
    String? categoryId,
    bool clearError = false,
    bool clearType = false,
    bool clearAccount = false,
    bool clearCategory = false,
  }) {
    return TransactionListState(
      items: items ?? this.items,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      keyword: keyword ?? this.keyword,
      type: clearType ? null : type ?? this.type,
      accountId: clearAccount ? null : accountId ?? this.accountId,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    );
  }
}

class TransactionListController extends StateNotifier<TransactionListState> {
  TransactionListController(this._repository)
    : super(const TransactionListState());

  final TransactionRepository _repository;
  Timer? _searchDebounce;

  /// 下拉刷新交易列表。
  Future<void> refresh() async {
    await _loadPage(page: 1, refresh: state.items.isNotEmpty);
  }

  /// 加载下一页交易。
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }
    await _loadPage(page: state.page + 1, append: true);
  }

  /// 更新搜索关键词并执行 300ms 防抖刷新。
  void updateKeyword(String keyword) {
    state = state.copyWith(keyword: keyword, clearError: true);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  /// 更新筛选条件并刷新列表。
  Future<void> updateFilters({
    TransactionType? type,
    String? accountId,
    String? categoryId,
    bool clearType = false,
    bool clearAccount = false,
    bool clearCategory = false,
  }) async {
    state = state.copyWith(
      type: type,
      accountId: accountId,
      categoryId: categoryId,
      clearType: clearType,
      clearAccount: clearAccount,
      clearCategory: clearCategory,
      clearError: true,
    );
    await refresh();
  }

  /// 清空全部筛选和搜索条件。
  Future<void> clearFilters() async {
    _searchDebounce?.cancel();
    state = state.copyWith(
      keyword: '',
      clearType: true,
      clearAccount: true,
      clearCategory: true,
      clearError: true,
    );
    await refresh();
  }

  /// 删除交易并刷新列表。
  Future<void> deleteTransaction(String id) async {
    await _repository.delete(id);
    await refresh();
  }

  /// 批量删除交易并刷新列表。
  Future<void> deleteTransactions(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await _repository.batchDelete(ids);
    await refresh();
  }

  /// 按页加载交易数据。
  Future<void> _loadPage({
    required int page,
    bool append = false,
    bool refresh = false,
  }) async {
    if (append) {
      state = state.copyWith(isLoadingMore: true, clearError: true);
    } else if (refresh) {
      state = state.copyWith(isRefreshing: true, clearError: true);
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final result = await _repository.list(
        TransactionListQuery(
          page: page,
          pageSize: state.pageSize,
          keyword: state.keyword,
          type: state.type,
          accountId: state.accountId,
          categoryId: state.categoryId,
        ),
      );
      state = state.copyWith(
        items: append ? [...state.items, ...result.list] : result.list,
        page: result.page,
        pageSize: result.pageSize,
        total: result.total,
        isLoading: false,
        isRefreshing: false,
        isLoadingMore: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        isLoadingMore: false,
        errorMessage: error.toString(),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
