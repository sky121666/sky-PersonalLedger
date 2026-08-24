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

    expect(find.text('连接账本'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-url-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('server-connect-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('server-connect-button')));
    await tester.pumpAndSettle();
    expect(find.text('请输入账本地址'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      'ledger.example.com:8080',
    );
    await tester.tap(find.byKey(const ValueKey('server-connect-button')));
    await tester.pumpAndSettle();

    expect(find.text('账本解锁'), findsOneWidget);
    expect(find.text('ledger.example.com:8080'), findsOneWidget);
  });

  testWidgets('accepts password input and triggers login flow', (tester) async {
    const password = 'TestPassw0rd';
    late _TestAuthController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) {
            controller = _TestAuthController(ref, captureLogin: true);
            return controller;
          }),
        ],
        child: const PersonalLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      'ledger.example.com:8080',
    );
    await tester.tap(find.byKey(const ValueKey('server-connect-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('auth-login-password-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('auth-login-submit-button')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('auth-login-password-field')),
      password,
    );
    await tester.tap(find.byKey(const ValueKey('auth-login-submit-button')));
    await tester.pumpAndSettle();

    expect(controller.loginCalls, equals([password]));
    expect(controller.debugState.stage, AuthStage.authenticated);
  });
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref, {this.captureLogin = false}) {
    state = const AuthState(stage: AuthStage.serverRequired);
  }

  final bool captureLogin;
  final List<String> loginCalls = [];

  @override
  AuthState get debugState => state;

  @override
  Future<void> connectServer(
    String input, {
    bool acknowledgeInsecureLocalHttp = false,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      state = const AuthState(
        stage: AuthStage.serverRequired,
        errorMessage: '请输入账本地址',
      );
      return;
    }
    state = AuthState(
      stage: AuthStage.loginRequired,
      serverUrl: trimmed,
      initialized: true,
    );
  }

  @override
  Future<void> login(String password) async {
    if (captureLogin) {
      loginCalls.add(password);
      state = state.copyWith(stage: AuthStage.authenticated, clearError: true);
      return;
    }
    return super.login(password);
  }

  @override
  Future<void> setupPassword(String password) async {
    state = AuthState(
      stage: AuthStage.authenticated,
      initialized: true,
      serverUrl: state.serverUrl,
      errorMessage: null,
    );
  }
}
