import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/server_config_service.dart';
import '../network/api_client.dart';
import '../storage/secure_storage_service.dart';

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final serverConfigServiceProvider = Provider<ServerConfigService>((ref) {
  return ServerConfigService(ref.watch(secureStorageServiceProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(serverConfigService: ref.watch(serverConfigServiceProvider));
});
