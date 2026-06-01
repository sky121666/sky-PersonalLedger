import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/application/account_controller.dart';
import '../../home/data/home_repository.dart';
import 'transaction_list_controller.dart';

extension LedgerRefresh on WidgetRef {
  void invalidateLedgerMutationViews() {
    invalidate(transactionListControllerProvider);
    invalidate(accountListControllerProvider);
    invalidate(homeSummaryProvider);
    invalidate(homeDateTransactionsProvider);
  }
}
