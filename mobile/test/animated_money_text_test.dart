import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/animated_money_text.dart';

void main() {
  testWidgets('AnimatedMoneyText renders a formatted amount', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnimatedMoneyText(amount: 1280.5)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('¥1,280.50'), findsOneWidget);
    expect(find.bySemanticsLabel('¥1,280.50'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('AnimatedMoneyText updates when amount changes', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AnimatedMoneyText(amount: 100))),
    );
    await tester.pumpAndSettle();
    expect(find.text('¥100.00'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AnimatedMoneyText(amount: 250))),
    );
    await tester.pumpAndSettle();

    expect(find.text('¥250.00'), findsOneWidget);
    expect(find.bySemanticsLabel('¥250.00'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('AnimatedMoneyText respects disabled animations', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: AnimatedMoneyText(amount: 88.8)),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('¥88.80'), findsOneWidget);
    expect(find.bySemanticsLabel('¥88.80'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('AnimatedMoneyText exposes final amount immediately', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AnimatedMoneyText(amount: 320))),
    );

    await tester.pump();

    expect(find.text('¥320.00'), findsOneWidget);
    expect(find.bySemanticsLabel('¥320.00'), findsOneWidget);
    semantics.dispose();
  });
}
