import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/core/providers/core_providers.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/transactions/application/ledger_refresh.dart';
import 'package:personal_ledger/features/transactions/application/transaction_list_controller.dart';

void main() {
  test(
    'a completed newer restore revokes an earlier completion and cannot be completed twice',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final createCompletion = container.read(ledgerRestoreCompletionProvider);
      final older = createCompletion();
      final newer = createCompletion();
      expect(newer(), isTrue);
      await container.pump();
      expect(container.read(ledgerDataRevisionProvider), 1);
      expect(older(), isFalse);
      expect(newer(), isFalse);
      expect(container.read(ledgerDataRevisionProvider), 1);
    },
  );

  for (final revision in [
    ledgerDataRevisionProvider,
    ledgerSessionRevisionProvider,
  ]) {
    test(
      'old mutation refresh is revoked after ${revision == ledgerDataRevisionProvider ? 'restore' : 'session change'}',
      () async {
        var assets = 123.0;
        final container = ProviderContainer(
          overrides: [
            homeSummaryProvider.overrideWith((ref) async => _summary(assets)),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(homeSummaryProvider, (_, __) {});
        addTearDown(subscription.close);
        expect(
          (await container.read(homeSummaryProvider.future)).accounts.netAssets,
          123,
        );
        final oldRefresh = container.read(ledgerMutationRefreshProvider);
        container.read(revision.notifier).state++;
        await container.pump();
        assets = 456;
        oldRefresh();
        expect(
          (await container.read(homeSummaryProvider.future)).accounts.netAssets,
          123,
        );
        container.read(ledgerMutationRefreshProvider)();
        expect(
          (await container.read(homeSummaryProvider.future)).accounts.netAssets,
          456,
        );
      },
    );
  }

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

HomeSummary _summary(double assets) => HomeSummary(
  accounts: AccountListResponse(
    list: const [],
    totalAssets: assets,
    totalLiabilities: 0,
    netAssets: assets,
  ),
  overview: const StatisticsOverview(
    income: 0,
    expense: 0,
    balance: 0,
    transactionCount: 0,
  ),
  budgetSummary: const BudgetSummary(
    totalAmount: 0,
    totalSpent: 0,
    percentage: 0,
    dailyAvailable: 0,
    daysRemaining: 0,
    overBudgetCategories: [],
  ),
);
