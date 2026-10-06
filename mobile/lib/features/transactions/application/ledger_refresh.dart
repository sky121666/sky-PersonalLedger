import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
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

// Keep a refresh callback alive across page disposal, while revoking it when
// the authenticated session or restored ledger changes.
final ledgerMutationRefreshProvider = Provider<void Function()>((ref) {
  ref.watch(ledgerSessionRevisionProvider);
  ref.watch(ledgerDataRevisionProvider);
  var current = true;
  ref.onDispose(() => current = false);
  return () {
    if (current) invalidateLedgerMutationProviders(ref.invalidate);
  };
});

// Create a request-bound completion before awaiting restore. Page disposal
// does not revoke it; session/data replacement and container disposal do.
final ledgerRestoreCompletionProvider = Provider<bool Function() Function()>((
  ref,
) {
  ref.watch(ledgerSessionRevisionProvider);
  ref.watch(ledgerDataRevisionProvider);
  var current = true;
  ref.onDispose(() => current = false);
  return () {
    var completed = false;
    return () {
      if (!current || completed) return false;
      completed = true;
      ref.read(ledgerDataRevisionProvider.notifier).state++;
      return true;
    };
  };
});

extension LedgerRefresh on WidgetRef {
  void invalidateRestoredLedger() {
    read(ledgerRestoreCompletionProvider)()();
  }

  void invalidateLedgerMutationViews() {
    read(ledgerMutationRefreshProvider)();
  }
}
