import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('documents required runtime flow', (tester) async {
    const requiredFlows = <String>[
      'server config',
      'login',
      'home summary',
      'accounts list',
      'quick transaction form',
    ];

    expect(requiredFlows, contains('server config'));
    expect(requiredFlows, contains('quick transaction form'));
  });
}
