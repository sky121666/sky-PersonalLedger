import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';

void main() {
  testWidgets('PremiumSurface provides a Material surface for ListTile ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PremiumSurface(
            padding: EdgeInsets.zero,
            child: ListTile(title: Text('Surface row')),
          ),
        ),
      ),
    );

    final surfaceMaterial = find.descendant(
      of: find.byType(PremiumSurface),
      matching: find.byType(Material),
    );

    expect(surfaceMaterial, findsOneWidget);
    expect(
      tester.widget<Material>(surfaceMaterial).clipBehavior,
      Clip.antiAlias,
    );
    expect(tester.takeException(), isNull);
  });
}
