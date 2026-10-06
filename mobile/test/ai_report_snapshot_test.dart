import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/ai/presentation/ai_reports_page.dart';

void main() {
  test(
    'monthly budget snapshot retains its own period and negative remainder',
    () {
      final snapshot = AIReportSnapshotData.parse('''{
      "budget": {"period_start":"2026-05-01","period_end":"2026-05-24",
        "settings_basis":"current_budget_settings","spent":1120,"remaining":-820},
      "account_changes":[{"account_name":"账户1","balance_delta":-120}]
    }''');
      expect(snapshot.budget?.periodStart, '2026-05-01');
      expect(snapshot.budget?.periodEnd, '2026-05-24');
      expect(snapshot.budget?.spent, 1120);
      expect(snapshot.budget?.remaining, -820);
      expect(snapshot.accountChanges.single.balanceDelta, -120);
    },
  );

  test(
    'legacy report keeps account facts without inventing a monthly budget period',
    () {
      final snapshot = AIReportSnapshotData.parse('''{
      "budget":{"monthly_budget":300,"spent":120,"remaining":180},
      "account_changes":[{"account_name":"账户1","balance_delta":380}]
    }''');
      expect(snapshot.budget, isNull);
      expect(snapshot.accountChanges.single.balanceDelta, 380);
    },
  );

  test('missing total budget does not become a zero allowance', () {
    final budget = AIReportBudgetData.parse({
      'period_start': '2026-05-01',
      'period_end': '2026-05-24',
      'settings_basis': 'current_budget_settings',
      'spent': 120,
      'remaining': null,
    });
    expect(budget?.spent, 120);
    expect(budget?.remaining, isNull);
  });

  test('malformed budget values do not replace valid account changes', () {
    final snapshot = AIReportSnapshotData.parse('''{
      "budget":{"period_start":42,"spent":"NaN"},
      "account_changes":[{"account_name":"账户1","balance_delta":380}]
    }''');
    expect(snapshot.budget, isNull);
    expect(snapshot.accountChanges.single.balanceDelta, 380);
  });
}
