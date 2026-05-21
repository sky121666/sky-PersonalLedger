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
  });
}
