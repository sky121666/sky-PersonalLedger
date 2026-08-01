import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_interceptor.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/config/server_config_service.dart';
import '../../../core/providers/core_providers.dart';
import '../data/auth_repository.dart';

const _e2eServerUrl = String.fromEnvironment(
  'LEDGER_E2E_SERVER_URL',
  defaultValue: '',
);
const _e2ePassword = String.fromEnvironment(
  'LEDGER_E2E_PASSWORD',
  defaultValue: '',
);
const _e2eAutoAuth = bool.fromEnvironment(
  'LEDGER_E2E_AUTO_AUTH',
  defaultValue: false,
);
const _runningWidgetTests = bool.fromEnvironment(
  'FLUTTER_TEST',
  defaultValue: false,
);

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
    _emitState(state.copyWith(stage: AuthStage.checking, clearError: true));
    final serverConfigService = _ref.read(serverConfigServiceProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    final config = await serverConfigService.readConfig();

    if (config == null) {
      if (await _maybeConnectRuntimeServerConfig(serverConfigService)) {
        return;
      }
      if (await _maybeBootstrapWithRuntimeE2E(serverConfigService)) {
        return;
      }

      await secureStorage.clearTokens();
      _emitState(const AuthState(stage: AuthStage.serverRequired));
      return;
    }

    await _initializeApiClient();
    if (await _maybeBootstrapWithRuntimeE2E(serverConfigService)) {
      return;
    }
    await _detectInitialRoute(config.baseUrl);
  }

  bool get _shouldAutoBootstrapE2E {
    return _e2eAutoAuth &&
        !_runningWidgetTests &&
        _e2eServerUrl.trim().isNotEmpty &&
        _e2ePassword.trim().isNotEmpty;
  }

  bool get _hasRuntimeServerConfig {
    return !_runningWidgetTests && _e2eServerUrl.trim().isNotEmpty;
  }

  Future<bool> _maybeConnectRuntimeServerConfig(
    ServerConfigService serverConfigService,
  ) async {
    if (!_hasRuntimeServerConfig) {
      return false;
    }

    if (!_isEnvironmentValidForAutoBootstrap(serverConfigService)) {
      return false;
    }

    await connectServer(_e2eServerUrl);

    if (_shouldAutoBootstrapE2E) {
      if (state.stage == AuthStage.setupRequired) {
        await setupPassword(_e2ePassword);
      } else if (state.stage == AuthStage.loginRequired) {
        await login(_e2ePassword);
      }
    }

    return state.stage != AuthStage.serverRequired;
  }

  Future<bool> _maybeBootstrapWithRuntimeE2E(
    ServerConfigService serverConfigService,
  ) async {
    if (!_shouldAutoBootstrapE2E) {
      return false;
    }

    if (!_isEnvironmentValidForAutoBootstrap(serverConfigService)) {
      return false;
    }

    await connectServer(_e2eServerUrl);

    if (state.stage == AuthStage.authenticated) {
      return true;
    }

    if (state.stage == AuthStage.setupRequired) {
      await setupPassword(_e2ePassword);
    } else if (state.stage == AuthStage.loginRequired) {
      await login(_e2ePassword);
    }

    return state.stage == AuthStage.authenticated;
  }

  bool _isEnvironmentValidForAutoBootstrap(
    ServerConfigService serverConfigService,
  ) {
    try {
      serverConfigService.normalizeServerUrl(_e2eServerUrl);
    } catch (_) {
      return false;
    }

    return true;
  }

  Future<void> connectServer(String input) async {
    _emitState(state.copyWith(stage: AuthStage.checking, clearError: true));
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
      _emitState(
        AuthState(
          stage: AuthStage.serverRequired,
          errorMessage: _formatError(error),
        ),
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
    } catch (_) {
      // Local logout must remain available when the server is offline or the
      // remote session has already expired. Tokens are cleared below in every
      // case, so a best-effort server revocation cannot trap the user locally.
    }
    await secureStorage.clearTokens();
    _emitState(
      state.copyWith(stage: AuthStage.loginRequired, clearError: true),
    );
  }

  Future<void> changeServer() async {
    final serverConfigService = _ref.read(serverConfigServiceProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    await secureStorage.clearTokens();
    await serverConfigService.clearConfig();
    _emitState(const AuthState(stage: AuthStage.serverRequired));
  }

  Future<void> expireSession() async {
    await _ref.read(secureStorageServiceProvider).clearTokens();
    _emitState(
      state.copyWith(
        stage: AuthStage.loginRequired,
        errorMessage: '登录已过期，请重新登录',
      ),
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
      final hasValidSession = hasToken
          ? await _ref.read(authRepositoryProvider).validateSession()
          : false;

      if (hasToken && !hasValidSession) {
        await _ref.read(secureStorageServiceProvider).clearTokens();
      }

      _emitState(
        AuthState(
          stage: !status.initialized
              ? AuthStage.setupRequired
              : hasValidSession
              ? AuthStage.authenticated
              : AuthStage.loginRequired,
          serverUrl: serverUrl,
          initialized: status.initialized,
        ),
      );
    } catch (error) {
      _emitState(
        AuthState(
          stage: AuthStage.serverRequired,
          serverUrl: serverUrl,
          errorMessage: _formatError(error),
        ),
      );
      return;
    }
  }

  Future<void> _authenticate(Future<dynamic> Function() request) async {
    _emitState(state.copyWith(stage: AuthStage.checking, clearError: true));
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
      _emitState(
        state.copyWith(stage: AuthStage.authenticated, clearError: true),
      );
    } catch (error) {
      final fallbackStage = state.initialized == false
          ? AuthStage.setupRequired
          : AuthStage.loginRequired;
      _emitState(
        state.copyWith(stage: fallbackStage, errorMessage: _formatError(error)),
      );
    }
  }

  void _emitState(AuthState next) {
    if (!mounted) {
      return;
    }
    state = next;
  }

  String _formatError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 401) {
        return '密码错误，请重试';
      }
      if (error.statusCode == 429) {
        return '尝试次数过多，请稍后再试';
      }
      if (error.statusCode == 403) {
        return '账本暂时锁定，请稍后再试';
      }
      if (error.statusCode != null && error.statusCode! >= 500) {
        return '账本服务暂时不可用，请稍后再试';
      }
    }
    final message = error.toString();
    final lowerMessage = message.toLowerCase();
    if (lowerMessage.contains('dioexception') ||
        lowerMessage.contains('socketexception') ||
        lowerMessage.contains('httpexception') ||
        lowerMessage.contains('xmlhttprequest') ||
        lowerMessage.contains('connection') ||
        lowerMessage.contains('timeout')) {
      return '账本连接失败，请检查地址或网络';
    }
    const prefixes = ['Exception: ', 'FormatException: '];
    for (final prefix in prefixes) {
      if (message.startsWith(prefix)) {
        return _safeAuthMessage(message.substring(prefix.length));
      }
    }
    return _safeAuthMessage(message);
  }

  String _safeAuthMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.startsWith('账本地址') ||
        trimmed.startsWith('远程账本') ||
        trimmed == '认证响应无效') {
      return trimmed;
    }
    return '账本连接失败，请检查地址或网络';
  }
}
