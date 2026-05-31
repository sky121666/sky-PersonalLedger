import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ledger/app/personal_ledger_app.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots native app and routes through server config', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
        ],
        child: const PersonalLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('连接服务器'), findsOneWidget);
    expect(find.text('自托管入口'), findsOneWidget);
    expect(find.textContaining('连接后会自动判断是否需要首次初始化'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(find.text('请输入服务器地址'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      'ledger.example.com:8080',
    );
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(find.text('欢迎回来'), findsOneWidget);
    expect(find.text('ledger.example.com:8080'), findsOneWidget);
  });
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref) {
    state = const AuthState(stage: AuthStage.serverRequired);
  }

  @override
  Future<void> connectServer(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      state = const AuthState(
        stage: AuthStage.serverRequired,
        errorMessage: '请输入服务器地址',
      );
      return;
    }
    state = AuthState(
      stage: AuthStage.loginRequired,
      serverUrl: trimmed,
      initialized: true,
    );
  }
}
