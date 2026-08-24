import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localHttpTransportPolicyProvider = Provider<LocalHttpTransportPolicy>((
  ref,
) {
  return const LocalHttpTransportPolicy();
});

class LocalHttpTransportPolicy {
  const LocalHttpTransportPolicy({
    MethodChannel channel = const MethodChannel(
      'personal_ledger/network_policy',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Android must opt in at build time before the UI can offer private HTTP.
  /// Other supported platforms enforce their local-network transport policy
  /// through their platform manifests.
  Future<bool> isCleartextTrafficPermitted() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('isCleartextTrafficPermitted') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
