import 'package:dio/dio.dart';

import '../config/server_config_service.dart';
import 'api_exception.dart';
import 'api_response.dart';
import 'auth_interceptor.dart';

class ApiClient {
  ApiClient({required ServerConfigService serverConfigService, Dio? dio})
    : _serverConfigService = serverConfigService,
      _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'Content-Type': 'application/json'},
    );
  }

  final ServerConfigService _serverConfigService;
  final Dio _dio;

  Dio get dio => _dio;

  /// 初始化 API Client 基础配置。
  Future<void> initialize({List<Interceptor> interceptors = const []}) async {
    await reloadBaseUrl();
    _dio.interceptors
      ..clear()
      ..addAll(interceptors);
  }

  /// 重新加载服务器基础地址。
  Future<void> reloadBaseUrl() async {
    final config = await _serverConfigService.readConfig();
    _dio.options.baseUrl = config?.apiBaseUrl ?? '';
  }

  /// 添加认证拦截器。
  void useAuthInterceptor(AuthInterceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// 发起 GET 请求并解析统一响应。
  Future<T?> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Object? json)? fromJsonT,
  }) {
    return _request<T>(
      () => _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
        options: options,
      ),
      fromJsonT: fromJsonT,
    );
  }

  /// 发起 POST 请求并解析统一响应。
  Future<T?> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Object? json)? fromJsonT,
  }) {
    return _request<T>(
      () => _dio.post<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
      fromJsonT: fromJsonT,
    );
  }

  /// 发起 multipart POST 请求并解析统一响应。
  Future<T?> postMultipart<T>(
    String path, {
    required FormData data,
    Map<String, dynamic>? queryParameters,
    void Function(int sent, int total)? onSendProgress,
    T Function(Object? json)? fromJsonT,
  }) {
    return _request<T>(
      () => _dio.post<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(contentType: Headers.multipartFormDataContentType),
        onSendProgress: onSendProgress,
      ),
      fromJsonT: fromJsonT,
    );
  }

  /// 发起 PUT 请求并解析统一响应。
  Future<T?> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Object? json)? fromJsonT,
  }) {
    return _request<T>(
      () => _dio.put<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
      fromJsonT: fromJsonT,
    );
  }

  /// 发起 PATCH 请求并解析统一响应。
  Future<T?> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Object? json)? fromJsonT,
  }) {
    return _request<T>(
      () => _dio.patch<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
      fromJsonT: fromJsonT,
    );
  }

  /// 发起 DELETE 请求并解析统一响应。
  Future<T?> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(Object? json)? fromJsonT,
  }) {
    return _request<T>(
      () => _dio.delete<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
      fromJsonT: fromJsonT,
    );
  }

  /// 统一执行请求并转换异常。
  Future<T?> _request<T>(
    Future<Response<Object?>> Function() request, {
    T Function(Object? json)? fromJsonT,
  }) async {
    try {
      final response = await request();
      return ApiResponseParser.parse<T>(response.data, fromJsonT: fromJsonT);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  /// 将 Dio 异常转换为业务异常。
  ApiException _mapDioException(DioException error) {
    final responseData = error.response?.data;
    if (responseData is Map<String, dynamic>) {
      return ApiException(
        code: responseData['code'] as int?,
        statusCode: error.response?.statusCode,
        message: responseData['message'] as String? ?? '请求失败',
        originalError: error,
      );
    }

    return ApiException(
      statusCode: error.response?.statusCode,
      message: error.response == null ? '网络连接失败' : '请求失败',
      originalError: error,
    );
  }
}
