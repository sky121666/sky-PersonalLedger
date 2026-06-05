import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/auth_token_pair.dart';
import '../storage/secure_storage_service.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio dio,
    required SecureStorageService secureStorage,
    FutureOr<void> Function()? onSessionExpired,
  }) : _dio = dio,
       _secureStorage = secureStorage,
       _onSessionExpired = onSessionExpired;

  static const skipAuthExtraKey = 'skipAuth';
  static const retriedExtraKey = 'retried';

  final Dio _dio;
  final SecureStorageService _secureStorage;
  final FutureOr<void> Function()? _onSessionExpired;
  Future<AuthTokenPair?>? _refreshingToken;
  Future<void>? _expiringSession;

  /// 请求前自动注入认证头。
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[skipAuthExtraKey] == true) {
      handler.next(options);
      return;
    }

    final accessToken = await _secureStorage.readAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }

    handler.next(options);
  }

  /// 响应异常时处理 token 过期、刷新和原请求重放。
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
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
        await _expireSession();
      }
      handler.next(err);
      return;
    }
    if (hasRetried) {
      await _expireSession();
      handler.next(err);
      return;
    }

    try {
      final tokenPair = await _refreshToken();
      if (tokenPair == null || !tokenPair.isValid) {
        await _expireSession();
        handler.next(err);
        return;
      }

      final response = await _retryRequest(err.requestOptions, tokenPair);
      handler.resolve(response);
    } on DioException catch (error) {
      await _expireSession();
      handler.next(error);
    } catch (_) {
      await _expireSession();
      handler.next(err);
    }
  }

  /// 刷新 token，复用并发中的刷新任务。
  Future<AuthTokenPair?> _refreshToken() {
    _refreshingToken ??= _doRefreshToken().whenComplete(() {
      _refreshingToken = null;
    });

    return _refreshingToken!;
  }

  /// 调用后端刷新 token 接口。
  Future<AuthTokenPair?> _doRefreshToken() async {
    final refreshToken = await _secureStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final response = await _dio.post<Object?>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
      options: Options(extra: const {skipAuthExtraKey: true}),
    );

    final responseData = response.data;
    if (responseData is! Map<String, dynamic> || responseData['code'] != 0) {
      return null;
    }

    final tokenPair = AuthTokenPair.fromJson(responseData['data']);
    if (!tokenPair.isValid) {
      return null;
    }

    await _secureStorage.saveTokens(
      accessToken: tokenPair.accessToken,
      refreshToken: tokenPair.refreshToken,
    );

    return tokenPair;
  }

  /// 使用新 token 重放原请求。
  Future<Response<dynamic>> _retryRequest(
    RequestOptions requestOptions,
    AuthTokenPair tokenPair,
  ) {
    final headers = Map<String, dynamic>.from(requestOptions.headers)
      ..['Authorization'] = 'Bearer ${tokenPair.accessToken}';
    final extra = Map<String, dynamic>.from(requestOptions.extra)
      ..[retriedExtraKey] = true;

    return _dio.fetch<dynamic>(
      requestOptions.copyWith(headers: headers, extra: extra),
    );
  }

  /// 清理登录态并通知上层会话失效。
  Future<void> _expireSession() {
    _expiringSession ??= _doExpireSession().whenComplete(() {
      _expiringSession = null;
    });
    return _expiringSession!;
  }

  Future<void> _doExpireSession() async {
    await _secureStorage.clearTokens();
    await _onSessionExpired?.call();
  }
}
