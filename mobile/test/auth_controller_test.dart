import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/core/providers/core_providers.dart';
import 'package:personal_ledger/core/network/api_exception.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';

void main() {
  test(
    'connectServer strips FormatException prefix from validation errors',
    () async {
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(authControllerProvider.notifier);

      await controller.connectServer('');

      final state = container.read(authControllerProvider);
      expect(state.stage, AuthStage.serverRequired);
      expect(state.errorMessage, '账本地址不能为空');
    },
  );

  test('connectServer hides low-level status errors', () async {
    final container = ProviderContainer(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(
          _FakeAuthRepository(statusError: Exception('raw socket failure')),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(authControllerProvider.notifier);

    await controller.connectServer('https://ledger.example.com');

    final state = container.read(authControllerProvider);
    expect(state.stage, AuthStage.serverRequired);
    expect(state.errorMessage, '账本连接失败，请检查地址或网络');
    expect(state.errorMessage, isNot(contains('raw socket failure')));
  });

  test(
    'bootstrap falls back to login when stored token is unauthorized',
    () async {
      final storage = _FakeSecureStorage()
        ..serverUrl = 'https://ledger.example.com'
        ..accessToken = 'expired-access'
        ..refreshToken = 'expired-refresh';
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(sessionValid: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      await _waitForAuthStage(
        container,
        predicate: (stage) => stage != AuthStage.checking,
      );

      final state = container.read(authControllerProvider);
      expect(state.stage, AuthStage.loginRequired);
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
    },
  );

  test(
    'bootstrap blocks a stored local HTTP URL until that exact URL is acknowledged',
    () async {
      final storage = _FakeSecureStorage()
        ..serverUrl = 'http://192.168.1.20:8080'
        ..insecureLocalHttpAcknowledgedUrl = 'http://192.168.1.21:8080'
        ..accessToken = 'stored-access'
        ..refreshToken = 'stored-refresh';
      final repository = _FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await _waitForAuthStage(
        container,
        predicate: (stage) => stage != AuthStage.checking,
      );

      final state = container.read(authControllerProvider);
      expect(state.stage, AuthStage.serverRequired);
      expect(state.serverUrl, 'http://192.168.1.20:8080');
      expect(state.errorMessage, contains('需要确认风险'));
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
      expect(repository.getStatusCalls, 0);
    },
  );

  for (final storedUrl in <String>[
    'http://ledger.example.com',
    'ftp://ledger.example.com',
  ]) {
    test(
      'bootstrap rejects unsafe stored server URL without initializing the API: $storedUrl',
      () async {
        final storage = _FakeSecureStorage()
          ..serverUrl = storedUrl
          ..accessToken = 'stored-access'
          ..refreshToken = 'stored-refresh';
        final repository = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [
            secureStorageServiceProvider.overrideWithValue(storage),
            authRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        await _waitForAuthStage(
          container,
          predicate: (stage) => stage != AuthStage.checking,
        );

        final state = container.read(authControllerProvider);
        expect(state.stage, AuthStage.serverRequired);
        expect(state.serverUrl, isNull);
        expect(await storage.readAccessToken(), isNull);
        expect(await storage.readRefreshToken(), isNull);
        expect(repository.getStatusCalls, 0);
      },
    );
  }

  test(
    'connectServer rejects local HTTP without controller-level acknowledgement',
    () async {
      final storage = _FakeSecureStorage();
      final repository = _FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await _waitForAuthStage(
        container,
        predicate: (stage) => stage == AuthStage.serverRequired,
      );

      await container
          .read(authControllerProvider.notifier)
          .connectServer('http://192.168.1.20:8080');

      final state = container.read(authControllerProvider);
      expect(state.stage, AuthStage.serverRequired);
      expect(state.errorMessage, contains('需要确认风险'));
      expect(storage.serverUrl, isNull);
      expect(storage.insecureLocalHttpAcknowledgedUrl, isNull);
      expect(repository.getStatusCalls, 0);
    },
  );

  test(
    'connectServer binds local HTTP acknowledgement to normalized URL',
    () async {
      final storage = _FakeSecureStorage();
      final repository = _FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await _waitForAuthStage(
        container,
        predicate: (stage) => stage == AuthStage.serverRequired,
      );

      await container
          .read(authControllerProvider.notifier)
          .connectServer(
            ' http://192.168.1.20:8080/ ',
            acknowledgeInsecureLocalHttp: true,
          );

      final state = container.read(authControllerProvider);
      expect(state.stage, AuthStage.loginRequired);
      expect(storage.serverUrl, 'http://192.168.1.20:8080');
      expect(
        storage.insecureLocalHttpAcknowledgedUrl,
        'http://192.168.1.20:8080',
      );
      expect(repository.getStatusCalls, 1);
    },
  );

  test('login distinguishes invalid password from a network failure', () async {
    final container = ProviderContainer(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
        authRepositoryProvider.overrideWithValue(
          _FakeAuthRepository(
            loginError: const ApiException(
              statusCode: 401,
              code: 40101,
              message: 'invalid password',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(authControllerProvider.notifier);
    await controller.connectServer('https://ledger.example.com');

    await controller.login('wrong-password');

    final state = container.read(authControllerProvider);
    expect(state.stage, AuthStage.loginRequired);
    expect(state.errorMessage, '密码错误，请重试');
  });

  test(
    'logout clears local tokens when remote revocation is unavailable',
    () async {
      final storage = _FakeSecureStorage();
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(logoutError: Exception('server offline')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(authControllerProvider.notifier);
      await controller.connectServer('https://ledger.example.com');
      await storage.saveTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );

      await controller.logout();

      final state = container.read(authControllerProvider);
      expect(state.stage, AuthStage.loginRequired);
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
    },
  );
}

Future<void> _waitForAuthStage(
  ProviderContainer container, {
  required bool Function(AuthStage stage) predicate,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final stage = container.read(authControllerProvider).stage;
    if (predicate(stage)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeSecureStorage extends SecureStorageService {
  String? serverUrl;
  String? insecureLocalHttpAcknowledgedUrl;
  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> readServerUrl() async => serverUrl;

  @override
  Future<void> saveServerUrl(String serverUrl) async {
    this.serverUrl = serverUrl;
  }

  @override
  Future<void> deleteServerUrl() async {
    serverUrl = null;
  }

  @override
  Future<String?> readInsecureLocalHttpAcknowledgedUrl() async {
    return insecureLocalHttpAcknowledgedUrl;
  }

  @override
  Future<void> saveInsecureLocalHttpAcknowledgedUrl(String serverUrl) async {
    insecureLocalHttpAcknowledgedUrl = serverUrl;
  }

  @override
  Future<void> deleteInsecureLocalHttpAcknowledgedUrl() async {
    insecureLocalHttpAcknowledgedUrl = null;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<void> saveAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveRefreshToken(String refreshToken) async {
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<void> clearAll() async {
    serverUrl = null;
    insecureLocalHttpAcknowledgedUrl = null;
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.statusError,
    this.loginError,
    this.logoutError,
    this.sessionValid = true,
  });

  final Object? statusError;
  final Object? loginError;
  final Object? logoutError;
  final bool sessionValid;
  var getStatusCalls = 0;

  @override
  Future<AuthStatus> getStatus() async {
    getStatusCalls += 1;
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return const AuthStatus(initialized: true);
  }

  @override
  Future<AuthTokenPair> init(String password) async {
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<AuthTokenPair> login(String password) async {
    final error = loginError;
    if (error != null) {
      throw error;
    }
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<bool> validateSession() async => sessionValid;

  @override
  Future<void> logout() async {
    final error = logoutError;
    if (error != null) {
      throw error;
    }
  }
}
