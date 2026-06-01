import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/adaptive_page_container.dart';

void main() {
  testWidgets('AdaptivePageContainer constrains wide layouts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdaptivePageContainer(
            padding: EdgeInsets.zero,
            child: SizedBox.expand(key: ValueKey('adaptive-child')),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('adaptive-child'))).width,
      960,
    );
  });

  testWidgets('AdaptivePageContainer exposes optional page semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdaptivePageContainer(
            semanticLabel: '账户页面内容',
            child: Text('账户列表'),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '账户页面内容',
      ),
      findsOneWidget,
    );
    expect(find.text('账户列表'), findsOneWidget);
    semantics.dispose();
  });
}
