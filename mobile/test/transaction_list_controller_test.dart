import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/transactions/application/transaction_list_controller.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';

void main() {
  test(
    'late results cannot replace a newer income filter or its loading state',
    () async {
      final repository = _ControlledRepository();
      final controller = TransactionListController(repository);
      addTearDown(controller.dispose);
      final oldLoad = controller.refresh();
      final incomeLoad = controller.updateFilters(type: TransactionType.income);
      repository.requests[1].complete(
        _result('income', TransactionType.income),
      );
      await incomeLoad;
      repository.requests[0].complete(
        _result('expense', TransactionType.expense),
      );
      await oldLoad;

      expect(controller.state.type, TransactionType.income);
      expect(controller.state.items.single.id, 'income');
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.errorMessage, isNull);
    },
  );

  test(
    'old pagination cannot append to a new filter and pagination waits for refresh',
    () async {
      final repository = _ControlledRepository();
      final controller = TransactionListController(repository);
      addTearDown(controller.dispose);
      final firstLoad = controller.refresh();
      repository.requests[0].complete(
        _result('first', TransactionType.expense, total: 40),
      );
      await firstLoad;
      final more = controller.loadMore();
      expect(repository.queries[1].page, 2);
      final filtered = controller.updateFilters(type: TransactionType.income);
      await controller.loadMore();
      expect(repository.requests, hasLength(3));
      repository.requests[2].complete(
        _result('income', TransactionType.income, total: 40),
      );
      await filtered;
      repository.requests[1].complete(
        _result('old-page-two', TransactionType.expense, page: 2, total: 40),
      );
      await more;

      expect(controller.state.items.map((item) => item.id), ['income']);
      expect(controller.state.page, 1);
      final incomeMore = controller.loadMore();
      expect(repository.queries.last.type, TransactionType.income);
      expect(repository.queries.last.page, 2);
      repository.requests.last.complete(
        _result('income-two', TransactionType.income, page: 2, total: 40),
      );
      await incomeMore;
      expect(controller.state.items.map((item) => item.id), [
        'income',
        'income-two',
      ]);
    },
  );

  test(
    'a keyword change rejects the old response before the debounce expires',
    () async {
      final repository = _ControlledRepository();
      final controller = TransactionListController(repository);
      addTearDown(controller.dispose);
      final firstLoad = controller.refresh();
      controller.updateKeyword('coffee');
      repository.requests[0].complete(
        _result('unfiltered', TransactionType.expense),
      );
      await firstLoad;
      expect(controller.state.items, isEmpty);
      await controller.loadMore();
      expect(repository.requests, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(repository.queries.last.keyword, 'coffee');
      repository.requests.last.complete(
        _result('coffee', TransactionType.expense),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.items.single.id, 'coffee');
    },
  );

  test(
    'an obsolete failure cannot replace the latest results or escape after disposal',
    () async {
      final repository = _ControlledRepository();
      final controller = TransactionListController(repository);
      final oldLoad = controller.refresh();
      final newLoad = controller.updateFilters(type: TransactionType.income);
      repository.requests[1].complete(
        _result('income', TransactionType.income),
      );
      await newLoad;
      repository.requests[0].completeError(Exception('old network failure'));
      await oldLoad;
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.items.single.id, 'income');

      final pending = controller.refresh();
      controller.dispose();
      repository.requests.last.complete(
        _result('late', TransactionType.expense),
      );
      await expectLater(pending, completes);
    },
  );
}

TransactionListResult _result(
  String id,
  TransactionType type, {
  int page = 1,
  int total = 1,
}) {
  return TransactionListResult(
    list: [
      TransactionItem(
        id: id,
        type: type,
        amount: 10,
        accountId: 'wallet',
        transactionDate: DateTime(2026, 9, 8),
      ),
    ],
    total: total,
    page: page,
    pageSize: 20,
  );
}

class _ControlledRepository implements TransactionRepository {
  final queries = <TransactionListQuery>[];
  final requests = <Completer<TransactionListResult>>[];

  @override
  Future<TransactionListResult> list(TransactionListQuery query) {
    queries.add(query);
    final request = Completer<TransactionListResult>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
