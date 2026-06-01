import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/ledger_icon.dart';

void main() {
  group('LedgerIcon', () {
    testWidgets('renders lucide style keys as Material icons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LedgerIcon(icon: 'banknote')),
      );

      expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
      expect(find.text('banknote'), findsNothing);
    });

    testWidgets('keeps known typo compatible without leaking text', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: LedgerIcon(icon: 'banknot')),
      );

      expect(find.byIcon(Icons.payments_outlined), findsOneWidget);
      expect(find.text('banknot'), findsNothing);
    });

    testWidgets('renders emoji icons as emoji text', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LedgerIcon(icon: '💳')));

      expect(find.text('💳'), findsOneWidget);
    });

    testWidgets('exposes explicit semantics for standalone icons', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: LedgerIcon(icon: 'wallet', semanticLabel: '现金账户'),
        ),
      );

      expect(
        find.byIcon(Icons.account_balance_wallet_outlined),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('现金账户'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('LedgerIconLabel exposes label semantics once', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: LedgerIconLabel(icon: '💳', label: '信用卡还款'),
        ),
      );

      expect(find.text('信用卡还款'), findsOneWidget);
      expect(find.text('💳'), findsOneWidget);
      expect(find.bySemanticsLabel('信用卡还款'), findsOneWidget);
      expect(find.bySemanticsLabel('💳'), findsNothing);
      semantics.dispose();
    });
  });
}
