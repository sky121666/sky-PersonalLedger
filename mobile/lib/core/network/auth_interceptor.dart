import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/auth_token_pair.dart';
import '../storage/secure_storage_service.dart';
import 'api_exception.dart';
import 'api_session.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio dio,
    required SecureStorageService secureStorage,
    ApiSession? session,
    FutureOr<void> Function()? onSessionExpired,
  }) : _dio = dio,
       _secureStorage = secureStorage,
       _session = session ?? ApiSession(),
       _onSessionExpired = onSessionExpired;

  static const skipAuthExtraKey = 'skipAuth';
  static const retriedExtraKey = 'retried';

  final Dio _dio;
  final SecureStorageService _secureStorage;
  final ApiSession _session;
  final FutureOr<void> Function()? _onSessionExpired;
  Future<AuthTokenPair?>? _refreshingToken;
  int? _refreshingGeneration;
  Future<void>? _expiringSession;
  int? _expiringGeneration;

  /// 请求前自动注入认证头。
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final generation =
        options.extra[ApiSession.generationExtraKey] as int? ??
        _session.generation;
    options.extra[ApiSession.generationExtraKey] = generation;
    try {
      _checkRequestSession(options);
      if (options.extra[skipAuthExtraKey] != true) {
        final accessToken = await _secureStorage.readAccessToken();
        _checkRequestSession(options);
        if (accessToken != null && accessToken.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $accessToken';
        }
      }
      handler.next(options);
    } on SessionChangedException catch (error) {
      handler.reject(_sessionError(options, error));
    }
  }

  /// 响应异常时处理 token 过期、刷新和原请求重放。
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final generation =
        err.requestOptions.extra[ApiSession.generationExtraKey] as int? ??
        _session.generation;
    if (!_session.isCurrent(generation) ||
        err.error is SessionChangedException) {
      handler.next(
        _sessionError(err.requestOptions, const SessionChangedException()),
      );
      return;
    }
    if (err.requestOptions.extra[skipAuthExtraKey] == true) {
      handler.next(err);
      return;
    }

    final isTokenExpired =
        err.response?.statusCode == 401 &&
        err.response?.data is Map<String, dynamic> &&
        (err.response?.data as Map<String, dynamic>)['code'] == 40102;
    final hasRetried = err.requestOptions.extra[retriedExtraKey] == true;

    if (!isTokenExpired) {
      if (err.response?.statusCode == 401) {
        await _expireSession(generation);
      }
      handler.next(err);
      return;
    }
    if (hasRetried) {
      await _expireSession(generation);
      handler.next(err);
      return;
    }

    try {
      final currentAccessToken = await _secureStorage.readAccessToken();
      _session.check(generation);
      final requestAuthorization = err.requestOptions.headers['Authorization'];
      if (currentAccessToken != null &&
          currentAccessToken.isNotEmpty &&
          requestAuthorization != 'Bearer $currentAccessToken') {
        final response = await _retryRequest(
          err.requestOptions,
          currentAccessToken,
        );
        handler.resolve(response);
        return;
      }

      final tokenPair = await _refreshToken(generation);
      if (tokenPair == null || !tokenPair.isValid) {
        await _expireSession(generation);
        handler.next(err);
        return;
      }

      _session.check(generation);
      final response = await _retryRequest(
        err.requestOptions,
        tokenPair.accessToken,
      );
      handler.resolve(response);
    } on SessionChangedException catch (error) {
      handler.next(_sessionError(err.requestOptions, error));
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _expireSession(generation);
      }
      handler.next(error);
    } catch (_) {
      await _expireSession(generation);
      handler.next(err);
    }
  }

  /// 刷新 token，复用并发中的刷新任务。
  Future<AuthTokenPair?> _refreshToken(int generation) {
    if (_refreshingToken == null || _refreshingGeneration != generation) {
      _refreshingGeneration = generation;
      _refreshingToken = _doRefreshToken(generation).whenComplete(() {
        if (_refreshingGeneration == generation) {
          _refreshingToken = null;
        }
      });
    }

    return _refreshingToken!;
  }

  /// 调用后端刷新 token 接口。
  Future<AuthTokenPair?> _doRefreshToken(int generation) async {
    final refreshToken = await _secureStorage.readRefreshToken();
    _session.check(generation);
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final response = await _dio.post<Object?>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
      options: Options(
        extra: {
          skipAuthExtraKey: true,
          ApiSession.generationExtraKey: generation,
        },
      ),
      cancelToken: _session.cancelToken,
    );
    _session.check(generation);

    final responseData = response.data;
    if (responseData is! Map<String, dynamic> || responseData['code'] != 0) {
      return null;
    }

    final tokenPair = AuthTokenPair.fromJson(responseData['data']);
    if (!tokenPair.isValid) {
      return null;
    }

    await _session.mutate(
      generation,
      () => _secureStorage.saveTokens(
        accessToken: tokenPair.accessToken,
        refreshToken: tokenPair.refreshToken,
      ),
    );

    return tokenPair;
  }

  /// 使用新 token 重放原请求。
  Future<Response<dynamic>> _retryRequest(
    RequestOptions requestOptions,
    String accessToken,
  ) {
    final headers = Map<String, dynamic>.from(requestOptions.headers)
      ..['Authorization'] = 'Bearer $accessToken';
    final extra = Map<String, dynamic>.from(requestOptions.extra)
      ..[retriedExtraKey] = true;

    return _dio.fetch<dynamic>(
      requestOptions.copyWith(headers: headers, extra: extra),
    );
  }

  /// 清理登录态并通知上层会话失效。
  Future<void> _expireSession(int generation) {
    if (!_session.isCurrent(generation)) return Future<void>.value();
    if (_expiringSession == null || _expiringGeneration != generation) {
      _expiringGeneration = generation;
      _expiringSession = _doExpireSession(generation).whenComplete(() {
        if (_expiringGeneration == generation) _expiringSession = null;
      });
    }
    return _expiringSession!;
  }

  Future<void> _doExpireSession(int generation) async {
    try {
      await _session.mutate(generation, _secureStorage.clearTokens);
      _session.check(generation);
      await _onSessionExpired?.call();
    } on SessionChangedException {
      // An old 401 cannot clear credentials or redirect a newer session.
    }
  }

  void _checkRequestSession(RequestOptions options) {
    _session.check(
      options.extra[ApiSession.generationExtraKey] as int,
      requireActive: options.extra[ApiSession.requiresActiveExtraKey] == true,
    );
  }

  DioException _sessionError(
    RequestOptions options,
    SessionChangedException error,
  ) {
    return DioException(
      requestOptions: options,
      type: DioExceptionType.cancel,
      error: error,
      message: error.message,
    );
  }
}
