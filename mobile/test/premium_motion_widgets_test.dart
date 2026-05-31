import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/pressable_scale.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';

void main() {
  testWidgets('PremiumSurface renders child and handles tap', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PremiumSurface(
            onTap: () => tapped = true,
            child: const Text('高级卡片'),
          ),
        ),
      ),
    );

    expect(find.text('高级卡片'), findsOneWidget);

    await tester.tap(find.text('高级卡片'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('PressableScale renders child and handles tap', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressableScale(
            onTap: () => tapped = true,
            child: const Text('按压反馈'),
          ),
        ),
      ),
    );

    expect(find.text('按压反馈'), findsOneWidget);

    await tester.tap(find.text('按压反馈'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('PressableScale supports keyboard activation', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              onTap: () => tapped = true,
              child: const SizedBox(
                width: 120,
                height: 48,
                child: Center(child: Text('键盘反馈')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('键盘反馈'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('StaggeredEntrance renders child after settling', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StaggeredEntrance(index: 1, child: Text('入场内容'))),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('入场内容'), findsOneWidget);
  });
}
