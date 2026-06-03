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
      throw const FormatException('账本地址不能为空');
    }

    final urlWithScheme = trimmedInput.startsWith(RegExp('https?://'))
        ? trimmedInput
        : 'https://$trimmedInput';
    final uri = Uri.tryParse(urlWithScheme);
    if (uri == null || uri.host.isEmpty) {
      throw const FormatException('账本地址格式不正确');
    }
    if (!_isAllowedScheme(uri)) {
      throw const FormatException('远程账本必须使用 HTTPS；HTTP 仅允许本机或局域网私有地址');
    }

    return uri.replace(path: _trimTrailingSlash(uri.path)).toString();
  }

  bool _isAllowedScheme(Uri uri) {
    if (uri.scheme == 'https') {
      return true;
    }
    return uri.scheme == 'http' && _isPrivateOrLoopbackHost(uri.host);
  }

  bool _isPrivateOrLoopbackHost(String host) {
    final normalizedHost = host.toLowerCase();
    if (normalizedHost == 'localhost' || normalizedHost == '::1') {
      return true;
    }
    final parts = normalizedHost.split('.');
    if (parts.length != 4) {
      return false;
    }
    final octets = parts.map(int.tryParse).toList(growable: false);
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  /// 移除路径末尾斜杠。
  String _trimTrailingSlash(String path) {
    if (path == '/' || path.isEmpty) {
      return '';
    }

    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
}
