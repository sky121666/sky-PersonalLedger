class AuthTokenPair {
  const AuthTokenPair({
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int? expiresIn;

  /// 从后端认证响应构建 token 对象。
  factory AuthTokenPair.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('认证响应格式不正确');
    }

    return AuthTokenPair(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      expiresIn: json['expires_in'] as int?,
    );
  }

  /// 校验 token 是否完整。
  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;
}
