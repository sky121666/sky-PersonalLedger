import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/core/providers/core_providers.dart';
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
      expect(state.errorMessage, '服务器地址不能为空');
    },
  );
}

class _FakeSecureStorage extends SecureStorageService {
  String? serverUrl;

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
  Future<String?> readAccessToken() async => null;

  @override
  Future<void> saveAccessToken(String accessToken) async {}

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveRefreshToken(String refreshToken) async {}

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> clearTokens() async {}

  @override
  Future<void> clearAll() async {
    serverUrl = null;
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthStatus> getStatus() async {
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
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<void> logout() async {}
}
