import '../storage/secure_storage_service.dart';

class ServerConfig {
  const ServerConfig({required this.baseUrl});

  final String baseUrl;

  /// 返回后端 API 基础地址。
  String get apiBaseUrl => '$baseUrl/api/v1';
}

class ServerConfigService {
  ServerConfigService(this._storage);

  final SecureStorageService _storage;

  /// 读取服务器配置。
  Future<ServerConfig?> readConfig() async {
    final serverUrl = await _storage.readServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) {
      return null;
    }

    return ServerConfig(baseUrl: serverUrl);
  }

  /// 保存并规范化服务器地址。
  Future<ServerConfig> saveServerUrl(String input) async {
    final normalizedUrl = normalizeServerUrl(input);
    await _storage.saveServerUrl(normalizedUrl);
    return ServerConfig(baseUrl: normalizedUrl);
  }

  /// 删除服务器配置。
  Future<void> clearConfig() {
    return _storage.deleteServerUrl();
  }

  /// 规范化用户输入的服务器地址。
  String normalizeServerUrl(String input) {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      throw const FormatException('服务器地址不能为空');
    }

    final urlWithScheme = trimmedInput.startsWith(RegExp('https?://'))
        ? trimmedInput
        : 'https://$trimmedInput';
    final uri = Uri.tryParse(urlWithScheme);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('服务器地址格式不正确');
    }

    return uri.replace(path: _trimTrailingSlash(uri.path)).toString();
  }

  /// 移除路径末尾斜杠。
  String _trimTrailingSlash(String path) {
    if (path == '/' || path.isEmpty) {
      return '';
    }

    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
}
