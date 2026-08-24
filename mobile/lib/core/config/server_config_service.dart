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

  /// 读取可安全连接的服务器配置。
  ///
  /// 未绑定当前规范化 URL 风险确认的局域网 HTTP 地址不会被返回，
  /// 避免 API Client 在启动阶段绕过交互确认。
  Future<ServerConfig?> readConfig() async {
    final storedConfig = await readStoredConfig();
    if (storedConfig == null) {
      return null;
    }

    late final String normalizedUrl;
    try {
      normalizedUrl = normalizeServerUrl(storedConfig.baseUrl);
    } on FormatException {
      return null;
    }

    final config = ServerConfig(baseUrl: normalizedUrl);
    if (!requiresInsecureLocalHttpConfirmation(normalizedUrl)) {
      return config;
    }
    final acknowledgedUrl = await _storage
        .readInsecureLocalHttpAcknowledgedUrl();
    return acknowledgedUrl == normalizedUrl ? config : null;
  }

  /// 仅读取已保存的地址，供确认页预填充；不得用于发起网络请求。
  Future<ServerConfig?> readStoredConfig() async {
    final serverUrl = await _storage.readServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) {
      return null;
    }

    return ServerConfig(baseUrl: serverUrl);
  }

  /// 保存并规范化服务器地址。
  Future<ServerConfig> saveServerUrl(
    String input, {
    bool acknowledgeInsecureLocalHttp = false,
  }) async {
    final normalizedUrl = normalizeServerUrl(input);
    final requiresAcknowledgement = requiresInsecureLocalHttpConfirmation(
      normalizedUrl,
    );
    if (requiresAcknowledgement && !acknowledgeInsecureLocalHttp) {
      throw const FormatException('局域网 HTTP 需要确认风险后才能连接');
    }
    await _storage.saveServerUrl(normalizedUrl);
    if (requiresAcknowledgement) {
      await _storage.saveInsecureLocalHttpAcknowledgedUrl(normalizedUrl);
    } else {
      await _storage.deleteInsecureLocalHttpAcknowledgedUrl();
    }
    return ServerConfig(baseUrl: normalizedUrl);
  }

  /// 删除服务器配置。
  Future<void> clearConfig() async {
    await Future.wait([
      _storage.deleteServerUrl(),
      _storage.deleteInsecureLocalHttpAcknowledgedUrl(),
    ]);
  }

  /// 规范化用户输入的服务器地址。
  String normalizeServerUrl(String input) {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      throw const FormatException('账本地址不能为空');
    }

    final hasExplicitScheme = trimmedInput.startsWith(
      RegExp(r'[a-z][a-z0-9+.-]*://', caseSensitive: false),
    );
    final urlWithScheme = hasExplicitScheme
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

  /// HTTP is only accepted for loopback/private-network hosts and must be
  /// explicitly acknowledged by the user before connecting.
  static bool requiresInsecureLocalHttpConfirmation(String input) {
    final trimmedInput = input.trim();
    final hasExplicitScheme = trimmedInput.startsWith(
      RegExp(r'[a-z][a-z0-9+.-]*://', caseSensitive: false),
    );
    final urlWithScheme = hasExplicitScheme
        ? trimmedInput
        : 'https://$trimmedInput';
    final uri = Uri.tryParse(urlWithScheme);
    return uri != null &&
        uri.scheme.toLowerCase() == 'http' &&
        _isPrivateOrLoopbackHost(uri.host);
  }

  bool _isAllowedScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return true;
    }
    return scheme == 'http' && _isPrivateOrLoopbackHost(uri.host);
  }

  static bool _isPrivateOrLoopbackHost(String host) {
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
