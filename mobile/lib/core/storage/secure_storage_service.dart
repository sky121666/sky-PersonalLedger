import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _serverUrlKey = 'server_url';
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  /// 读取已保存的服务器地址。
  Future<String?> readServerUrl() {
    return _storage.read(key: _serverUrlKey);
  }

  /// 保存服务器地址。
  Future<void> saveServerUrl(String serverUrl) {
    return _storage.write(key: _serverUrlKey, value: serverUrl);
  }

  /// 删除服务器地址。
  Future<void> deleteServerUrl() {
    return _storage.delete(key: _serverUrlKey);
  }

  /// 读取 access token。
  Future<String?> readAccessToken() {
    return _storage.read(key: _accessTokenKey);
  }

  /// 保存 access token。
  Future<void> saveAccessToken(String accessToken) {
    return _storage.write(key: _accessTokenKey, value: accessToken);
  }

  /// 读取 refresh token。
  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  /// 保存 refresh token。
  Future<void> saveRefreshToken(String refreshToken) {
    return _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// 同时保存 access token 与 refresh token。
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
    ]);
  }

  /// 清理本地 token。
  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  /// 清理所有安全存储配置。
  Future<void> clearAll() {
    return _storage.deleteAll();
  }
}
