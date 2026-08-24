import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/application/account_controller.dart';
import '../../home/data/home_repository.dart';
import '../../statistics/data/statistics_repository.dart';
import 'transaction_list_controller.dart';

void invalidateLedgerMutationProviders(
  void Function(ProviderOrFamily provider) invalidateProvider,
) {
  invalidateProvider(transactionListControllerProvider);
  invalidateProvider(accountListControllerProvider);
  invalidateProvider(homeSummaryProvider);
  invalidateProvider(homeSummaryByPeriodProvider);
  invalidateProvider(homeDateTransactionsProvider);
  invalidateProvider(statisticsDashboardProvider);
}

extension LedgerRefresh on WidgetRef {
  void invalidateLedgerMutationViews() {
    invalidateLedgerMutationProviders(invalidate);
  }
}
