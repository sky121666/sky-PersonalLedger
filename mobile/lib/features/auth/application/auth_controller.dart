import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_interceptor.dart';
import '../../../core/providers/core_providers.dart';
import '../data/auth_repository.dart';

enum AuthStage {
  checking,
  serverRequired,
  setupRequired,
  loginRequired,
  authenticated,
}

class AuthState {
  const AuthState({
    required this.stage,
    this.serverUrl,
    this.initialized,
    this.errorMessage,
  });

  final AuthStage stage;
  final String? serverUrl;
  final bool? initialized;
  final String? errorMessage;

  bool get isAuthenticated => stage == AuthStage.authenticated;

  bool get hasServerConfig => serverUrl != null && serverUrl!.isNotEmpty;

  AuthState copyWith({
    AuthStage? stage,
    String? serverUrl,
    bool? initialized,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      stage: stage ?? this.stage,
      serverUrl: serverUrl ?? this.serverUrl,
      initialized: initialized ?? this.initialized,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref)..bootstrap();
  },
);

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState(stage: AuthStage.checking));

  final Ref _ref;
  bool _apiInitialized = false;

  Future<void> bootstrap() async {
    state = state.copyWith(stage: AuthStage.checking, clearError: true);
    final serverConfigService = _ref.read(serverConfigServiceProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    final config = await serverConfigService.readConfig();

    if (config == null) {
      await secureStorage.clearTokens();
      state = const AuthState(stage: AuthStage.serverRequired);
      return;
    }

    await _initializeApiClient();
    await _detectInitialRoute(config.baseUrl);
  }

  Future<void> connectServer(String input) async {
    state = state.copyWith(stage: AuthStage.checking, clearError: true);
    final serverConfigService = _ref.read(serverConfigServiceProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);

    try {
      final normalizedUrl = serverConfigService.normalizeServerUrl(input);
      await secureStorage.clearTokens();
      await secureStorage.saveServerUrl(normalizedUrl);
      await _ref.read(apiClientProvider).reloadBaseUrl();
      await _initializeApiClient();
      await _detectInitialRoute(normalizedUrl);
    } catch (error) {
      await serverConfigService.clearConfig();
      state = AuthState(
        stage: AuthStage.serverRequired,
        errorMessage: _formatError(error),
      );
    }
  }

  Future<void> setupPassword(String password) async {
    await _authenticate(() => _ref.read(authRepositoryProvider).init(password));
  }

  Future<void> login(String password) async {
    await _authenticate(
      () => _ref.read(authRepositoryProvider).login(password),
    );
  }

  Future<void> logout() async {
    final repository = _ref.read(authRepositoryProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    try {
      await repository.logout();
    } catch (_) {}
    await secureStorage.clearTokens();
    state = state.copyWith(stage: AuthStage.loginRequired, clearError: true);
  }

  Future<void> changeServer() async {
    final serverConfigService = _ref.read(serverConfigServiceProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    await secureStorage.clearTokens();
    await serverConfigService.clearConfig();
    state = const AuthState(stage: AuthStage.serverRequired);
  }

  Future<void> expireSession() async {
    await _ref.read(secureStorageServiceProvider).clearTokens();
    state = state.copyWith(
      stage: AuthStage.loginRequired,
      errorMessage: '登录已过期，请重新登录',
    );
  }

  Future<void> _initializeApiClient() async {
    if (_apiInitialized) {
      return;
    }

    final apiClient = _ref.read(apiClientProvider);
    await apiClient.initialize(
      interceptors: [
        AuthInterceptor(
          dio: apiClient.dio,
          secureStorage: _ref.read(secureStorageServiceProvider),
          onSessionExpired: expireSession,
        ),
      ],
    );
    _apiInitialized = true;
  }

  Future<void> _detectInitialRoute(String serverUrl) async {
    try {
      final status = await _ref.read(authRepositoryProvider).getStatus();
      final accessToken = await _ref
          .read(secureStorageServiceProvider)
          .readAccessToken();
      final hasToken = accessToken != null && accessToken.isNotEmpty;

      state = AuthState(
        stage: !status.initialized
            ? AuthStage.setupRequired
            : hasToken
            ? AuthStage.authenticated
            : AuthStage.loginRequired,
        serverUrl: serverUrl,
        initialized: status.initialized,
      );
    } catch (error) {
      state = AuthState(
        stage: AuthStage.serverRequired,
        serverUrl: serverUrl,
        errorMessage: _formatError(error),
      );
    }
  }

  Future<void> _authenticate(Future<dynamic> Function() request) async {
    state = state.copyWith(stage: AuthStage.checking, clearError: true);
    try {
      final tokenPair = await request();
      if (!tokenPair.isValid) {
        throw const FormatException('认证响应无效');
      }
      await _ref
          .read(secureStorageServiceProvider)
          .saveTokens(
            accessToken: tokenPair.accessToken,
            refreshToken: tokenPair.refreshToken,
          );
      state = state.copyWith(stage: AuthStage.authenticated, clearError: true);
    } catch (error) {
      final fallbackStage = state.initialized == false
          ? AuthStage.setupRequired
          : AuthStage.loginRequired;
      state = state.copyWith(
        stage: fallbackStage,
        errorMessage: _formatError(error),
      );
    }
  }

  String _formatError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }
    return message;
  }
}
