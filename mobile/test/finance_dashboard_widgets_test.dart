import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';

void main() {
  testWidgets('RoundedBarChart exposes data semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundedBarChart(
            items: const [
              RoundedBarChartItem(
                label: '周一',
                primaryValue: 120,
                secondaryValue: 45,
                primaryColor: Colors.green,
                secondaryColor: Colors.red,
              ),
            ],
            maxValue: 160,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('柱状图，周一，主值 120，副值 45'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('RoundedBarChart accepts custom semantics summary', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundedBarChart(
            semanticLabel: '近七日收支对比，收入稳定高于支出',
            items: const [
              RoundedBarChartItem(
                label: '周二',
                primaryValue: 80,
                secondaryValue: 60,
                primaryColor: Colors.green,
                secondaryColor: Colors.red,
              ),
            ],
            maxValue: 100,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('近七日收支对比，收入稳定高于支出'), findsOneWidget);
    semantics.dispose();
  });
}
