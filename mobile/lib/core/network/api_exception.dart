class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.originalError,
  });

  final String message;
  final int? code;
  final int? statusCode;
  final Object? originalError;

  /// 判断是否为 access token 过期异常。
  bool get isTokenExpired => statusCode == 401 && code == 40102;

  /// 判断是否为未授权异常。
  bool get isUnauthorized => statusCode == 401;

  /// 判断是否为请求限流异常。
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => message;
}
