import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/transactions/application/ledger_refresh.dart';
import 'package:personal_ledger/features/transactions/application/transaction_list_controller.dart';

void main() {
  test(
    'ledger mutations invalidate every derived home and statistics family',
    () {
      final invalidated = <ProviderOrFamily>[];

      invalidateLedgerMutationProviders(invalidated.add);

      expect(invalidated, contains(transactionListControllerProvider));
      expect(invalidated, contains(accountListControllerProvider));
      expect(invalidated, contains(homeSummaryProvider));
      expect(invalidated, contains(homeSummaryByPeriodProvider));
      expect(invalidated, contains(homeDateTransactionsProvider));
      expect(invalidated, contains(statisticsDashboardProvider));
    },
  );
}
