import 'api_exception.dart';

class ApiResponse<T> {
  const ApiResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final T? data;

  /// 从后端统一响应 JSON 构建响应对象。
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json)? fromJsonT,
  ) {
    return ApiResponse<T>(
      code: json['code'] as int? ?? -1,
      message: json['message'] as String? ?? 'Request failed',
      data: fromJsonT == null ? json['data'] as T? : fromJsonT(json['data']),
    );
  }
}

class ApiResponseParser {
  const ApiResponseParser._();

  /// 解析后端统一响应并返回 data。
  static T? parse<T>(
    Object? responseData, {
    T Function(Object? json)? fromJsonT,
  }) {
    if (responseData is! Map<String, dynamic>) {
      throw const ApiException(message: '响应格式不正确');
    }

    final apiResponse = ApiResponse<T>.fromJson(responseData, fromJsonT);
    if (apiResponse.code != 0) {
      throw ApiException(code: apiResponse.code, message: apiResponse.message);
    }

    return apiResponse.data;
  }
}
