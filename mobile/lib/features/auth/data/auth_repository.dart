import 'package:dio/dio.dart';

import '../../../core/auth/auth_token_pair.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_interceptor.dart';

class AuthStatus {
  const AuthStatus({required this.initialized});

  final bool initialized;

  factory AuthStatus.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('初始化状态响应格式不正确');
    }

    return AuthStatus(initialized: json['initialized'] as bool? ?? false);
  }
}

class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthStatus> getStatus() async {
    final status = await _apiClient.get<AuthStatus>(
      '/auth/status',
      options: _skipAuthOptions,
      fromJsonT: AuthStatus.fromJson,
    );
    return status ?? const AuthStatus(initialized: false);
  }

  Future<AuthTokenPair> init(String password) async {
    final tokenPair = await _apiClient.post<AuthTokenPair>(
      '/auth/init',
      data: {'password': password},
      options: _skipAuthOptions,
      fromJsonT: AuthTokenPair.fromJson,
    );
    return tokenPair ?? const AuthTokenPair(accessToken: '', refreshToken: '');
  }

  Future<AuthTokenPair> login(String password) async {
    final tokenPair = await _apiClient.post<AuthTokenPair>(
      '/auth/login',
      data: {'password': password},
      options: _skipAuthOptions,
      fromJsonT: AuthTokenPair.fromJson,
    );
    return tokenPair ?? const AuthTokenPair(accessToken: '', refreshToken: '');
  }

  Future<void> logout() async {
    await _apiClient.post<void>('/auth/logout');
  }

  static final _skipAuthOptions = Options(
    extra: const {AuthInterceptor.skipAuthExtraKey: true},
  );
}
