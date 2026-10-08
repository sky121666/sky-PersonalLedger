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

// Changes at both the end of an old session and the start of an authenticated
// one. Business repositories get a new, session-bound client in either case.
final ledgerSessionRevisionProvider = StateProvider<int>((ref) => 0);

// Restoring replaces business data without clearing valid authentication.
final ledgerDataRevisionProvider = StateProvider<int>((ref) => 0);

final ledgerApiClientProvider = Provider<ApiClient>((ref) {
  ref.watch(ledgerSessionRevisionProvider);
  ref.watch(ledgerDataRevisionProvider);
  return ref.watch(apiClientProvider).forCurrentSession();
});
