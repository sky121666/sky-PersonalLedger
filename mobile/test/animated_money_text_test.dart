import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/animated_money_text.dart';

void main() {
  testWidgets('AnimatedMoneyText renders a formatted amount', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnimatedMoneyText(amount: 1280.5)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('¥1280.50'), findsOneWidget);
  });

  testWidgets('AnimatedMoneyText updates when amount changes', (tester) async {
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
  });

  testWidgets('AnimatedMoneyText respects disabled animations', (tester) async {
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
  });
}
