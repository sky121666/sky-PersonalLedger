import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Owns the lifetime of requests and storage writes for one ledger session.
class ApiSession {
  static const generationExtraKey = 'ledgerSessionGeneration';
  static const requiresActiveExtraKey = 'requiresActiveLedgerSession';

  int _generation = 0;
  bool _active = true;
  CancelToken _cancelToken = CancelToken();
  Future<void> _pendingMutation = Future<void>.value();

  int get generation => _generation;
  CancelToken get cancelToken => _cancelToken;

  bool isCurrent(int generation) => generation == _generation;

  int invalidate() {
    _generation++;
    _active = false;
    _cancelToken.cancel('账本会话已变更');
    _cancelToken = CancelToken();
    return _generation;
  }

  void activate(int generation) {
    check(generation);
    _active = true;
  }

  void check(int generation, {bool requireActive = false}) {
    if (!isCurrent(generation) || (requireActive && !_active)) {
      throw const SessionChangedException();
    }
  }

  /// A clear queued after an in-flight credential write must finish last.
  /// Checking again when the write starts also rejects queued old-session work.
  Future<T> mutate<T>(int generation, Future<T> Function() action) {
    final result = _pendingMutation.then((_) async {
      check(generation);
      final value = await action();
      check(generation);
      return value;
    });
    _pendingMutation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}
