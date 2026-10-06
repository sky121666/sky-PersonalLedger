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
    final generation = _beginSessionChange(publishRevision: false);
    try {
      // The initial bootstrap starts while its provider is being built.
      // Publish dependencies after construction, unless a user action won.
      await Future<void>.value();
      _checkGeneration(generation);
      _ref.read(ledgerSessionRevisionProvider.notifier).state++;
      final serverConfigService = _ref.read(serverConfigServiceProvider);
      final secureStorage = _ref.read(secureStorageServiceProvider);
      final storedConfig = await serverConfigService.readStoredConfig();
      final config = await serverConfigService.readConfig();
      _checkGeneration(generation);

      if (config == null) {
        if (await _maybeConnectRuntimeServerConfig(serverConfigService)) {
          return;
        }
        if (await _maybeBootstrapWithRuntimeE2E(serverConfigService)) {
          return;
        }

        await _mutateSession(generation, secureStorage.clearTokens);
        if (storedConfig != null &&
            ServerConfigService.requiresInsecureLocalHttpConfirmation(
              storedConfig.baseUrl,
            )) {
          _emitState(
            AuthState(
              stage: AuthStage.serverRequired,
              serverUrl: storedConfig.baseUrl,
              errorMessage: '局域网 HTTP 需要确认风险后才能连接',
            ),
          );
        } else {
          _emitState(const AuthState(stage: AuthStage.serverRequired));
        }
        return;
      }

      await _initializeApiClient();
      _checkGeneration(generation);
      if (await _maybeBootstrapWithRuntimeE2E(serverConfigService)) {
        return;
      }
      await _detectInitialRoute(config.baseUrl, generation);
    } on SessionChangedException {
      // A newer connect/login action owns routing and storage now.
    } catch (error) {
      if (_isCurrentGeneration(generation)) {
        _emitState(
          AuthState(
            stage: AuthStage.serverRequired,
            errorMessage: _formatError(error),
          ),
        );
      }
    }
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

    await connectServer(_e2eServerUrl, acknowledgeInsecureLocalHttp: true);

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

    await connectServer(_e2eServerUrl, acknowledgeInsecureLocalHttp: true);

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

  Future<void> connectServer(
    String input, {
    bool acknowledgeInsecureLocalHttp = false,
  }) async {
    final generation = _beginSessionChange();
    final serverConfigService = _ref.read(serverConfigServiceProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    var configSaved = false;

    try {
      await _mutateSession(generation, secureStorage.clearTokens);
      final config = await _mutateSession(
        generation,
        () => serverConfigService.saveServerUrl(
          input,
          acknowledgeInsecureLocalHttp: acknowledgeInsecureLocalHttp,
        ),
      );
      configSaved = true;
      await _ref.read(apiClientProvider).reloadBaseUrl();
      _checkGeneration(generation);
      await _initializeApiClient();
      _checkGeneration(generation);
      await _detectInitialRoute(config.baseUrl, generation);
    } on SessionChangedException {
      return;
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      if (configSaved) {
        try {
          await _mutateSession(generation, serverConfigService.clearConfig);
        } on SessionChangedException {
          return;
        }
      }
      _emitState(
        AuthState(
          stage: AuthStage.serverRequired,
          serverUrl: state.serverUrl,
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
    final generation = _beginSessionChange();
    final repository = _ref.read(authRepositoryProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    try {
      await repository.logout();
    } catch (_) {
      // Local logout must remain available when the server is offline or the
      // remote session has already expired. Tokens are cleared below in every
      // case, so a best-effort server revocation cannot trap the user locally.
    }
    if (!_isCurrentGeneration(generation)) return;
    try {
      await _mutateSession(generation, secureStorage.clearTokens);
    } on SessionChangedException {
      return;
    }
    _emitState(
      state.copyWith(stage: AuthStage.loginRequired, clearError: true),
    );
  }

  Future<void> changeServer() async {
    final generation = _beginSessionChange();
    final serverConfigService = _ref.read(serverConfigServiceProvider);
    final secureStorage = _ref.read(secureStorageServiceProvider);
    try {
      await _mutateSession(generation, secureStorage.clearTokens);
      await _mutateSession(generation, serverConfigService.clearConfig);
      await _ref.read(apiClientProvider).reloadBaseUrl();
      _checkGeneration(generation);
    } on SessionChangedException {
      return;
    }
    _emitState(const AuthState(stage: AuthStage.serverRequired));
  }

  Future<void> expireSession() async {
    final generation = _beginSessionChange();
    try {
      await _mutateSession(
        generation,
        _ref.read(secureStorageServiceProvider).clearTokens,
      );
    } on SessionChangedException {
      return;
    }
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
          session: apiClient.session,
          onSessionExpired: expireSession,
        ),
      ],
    );
    _apiInitialized = true;
  }

  Future<void> _detectInitialRoute(String serverUrl, int generation) async {
    try {
      _checkGeneration(generation);
      final status = await _ref.read(authRepositoryProvider).getStatus();
      _checkGeneration(generation);
      final accessToken = await _ref
          .read(secureStorageServiceProvider)
          .readAccessToken();
      _checkGeneration(generation);
      final hasToken = accessToken != null && accessToken.isNotEmpty;
      final hasValidSession = status.initialized && hasToken
          ? await _ref.read(authRepositoryProvider).validateSession()
          : false;
      _checkGeneration(generation);

      if (hasToken && !hasValidSession) {
        await _mutateSession(
          generation,
          _ref.read(secureStorageServiceProvider).clearTokens,
        );
      }

      if (hasValidSession) _activateSession(generation);

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
    } on SessionChangedException {
      return;
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
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
    final generation = _beginSessionChange();
    try {
      await _mutateSession(
        generation,
        _ref.read(secureStorageServiceProvider).clearTokens,
      );
      final tokenPair = await request();
      _checkGeneration(generation);
      if (!tokenPair.isValid) {
        throw const FormatException('认证响应无效');
      }
      await _mutateSession(
        generation,
        () => _ref
            .read(secureStorageServiceProvider)
            .saveTokens(
              accessToken: tokenPair.accessToken,
              refreshToken: tokenPair.refreshToken,
            ),
      );
      _activateSession(generation);
      _emitState(
        state.copyWith(
          stage: AuthStage.authenticated,
          initialized: true,
          clearError: true,
        ),
      );
    } on SessionChangedException {
      return;
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      final fallbackStage = state.initialized == false
          ? AuthStage.setupRequired
          : AuthStage.loginRequired;
      _emitState(
        state.copyWith(stage: fallbackStage, errorMessage: _formatError(error)),
      );
    }
  }

  int _beginSessionChange({bool publishRevision = true}) {
    final generation = _ref.read(apiClientProvider).session.invalidate();
    if (publishRevision) {
      _ref.read(ledgerSessionRevisionProvider.notifier).state++;
    }
    _emitState(state.copyWith(stage: AuthStage.checking, clearError: true));
    return generation;
  }

  void _activateSession(int generation) {
    _checkGeneration(generation);
    _ref.read(apiClientProvider).session.activate(generation);
    _ref.read(ledgerSessionRevisionProvider.notifier).state++;
  }

  bool _isCurrentGeneration(int generation) =>
      mounted && _ref.read(apiClientProvider).session.isCurrent(generation);

  void _checkGeneration(int generation) {
    if (!_isCurrentGeneration(generation)) {
      throw const SessionChangedException();
    }
  }

  Future<T> _mutateSession<T>(int generation, Future<T> Function() action) {
    return _ref.read(apiClientProvider).session.mutate(generation, action);
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
        trimmed.startsWith('局域网 HTTP') ||
        trimmed == '认证响应无效') {
      return trimmed;
    }
    return '账本连接失败，请检查地址或网络';
  }
}
