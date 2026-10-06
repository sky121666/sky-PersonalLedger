import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/config/server_config_service.dart';
import 'package:personal_ledger/core/network/api_client.dart';
import 'package:personal_ledger/core/network/api_exception.dart';
import 'package:personal_ledger/core/providers/core_providers.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/categories/application/category_controller.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/transactions/application/ledger_refresh.dart';

void main() {
  test(
    'restore completion captured before real logout cannot refresh or reauthenticate the logged-out ledger',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.connect('a.example');
      final completeRestore = fixture.container.read(
        ledgerRestoreCompletionProvider,
      )();
      final before = fixture.container.read(ledgerDataRevisionProvider);
      await fixture.auth.logout();
      expect(completeRestore(), isFalse);
      expect(fixture.container.read(ledgerDataRevisionProvider), before);
      expect(fixture.storage.accessToken, isNull);
      expect(
        fixture.container.read(authControllerProvider).stage,
        AuthStage.loginRequired,
      );
    },
  );

  test(
    'restore reloads account category home and statistics caches and rejects late old state without logout',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.connect('a.example');
      final accountSubscription = fixture.container.listen(
        accountListControllerProvider,
        (_, __) {},
      );
      final categorySubscription = fixture.container.listen(
        categoryListControllerProvider,
        (_, __) {},
      );
      const homeQuery = HomeSummaryQuery(month: '2026-10');
      const statsQuery = StatisticsDashboardQuery(
        month: '2026-10',
        categoryType: 'expense',
      );
      final homeSubscription = fixture.container.listen(
        homeSummaryByPeriodProvider(homeQuery),
        (_, __) {},
      );
      final statsSubscription = fixture.container.listen(
        statisticsDashboardProvider(statsQuery),
        (_, __) {},
      );
      addTearDown(accountSubscription.close);
      addTearDown(categorySubscription.close);
      addTearDown(homeSubscription.close);
      addTearDown(statsSubscription.close);
      await _waitFor(
        () =>
            fixture.accountName == 'a.example' &&
            fixture.categoryName == 'a.example',
      );
      expect(
        (await fixture.container.read(
          homeSummaryByPeriodProvider(homeQuery).future,
        )).accounts.netAssets,
        123,
      );
      expect(
        (await fixture.container.read(
          statisticsDashboardProvider(statsQuery).future,
        )).overview.balance,
        123,
      );
      final held = Completer<void>();
      fixture.adapter.accountResponse = held;
      final oldLoad = fixture.container
          .read(accountListControllerProvider.notifier)
          .load();
      await _waitFor(() => fixture.adapter.accountRequestHeld);
      fixture.adapter.accountResponse = null;
      fixture.adapter.datasetName = 'restored';
      fixture.container.read(ledgerDataRevisionProvider.notifier).state++;
      await _waitFor(
        () =>
            fixture.accountName == 'restored' &&
            fixture.categoryName == 'restored',
      );
      expect(
        (await fixture.container.read(
          homeSummaryByPeriodProvider(homeQuery).future,
        )).accounts.netAssets,
        456,
      );
      expect(
        (await fixture.container.read(
          statisticsDashboardProvider(statsQuery).future,
        )).overview.balance,
        456,
      );
      held.complete();
      await oldLoad;
      expect(fixture.accountName, 'restored');
      expect(fixture.storage.accessToken, 'a.example-access');
      expect(
        fixture.container.read(authControllerProvider).stage,
        AuthStage.authenticated,
      );
    },
  );

  test(
    'changing ledgers replaces account/category caches and ignores A responses after B login',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.connect('a.example');
      final accountSubscription = fixture.container.listen(
        accountListControllerProvider,
        (_, __) {},
      );
      final categorySubscription = fixture.container.listen(
        categoryListControllerProvider,
        (_, __) {},
      );
      addTearDown(accountSubscription.close);
      addTearDown(categorySubscription.close);
      await _waitFor(
        () =>
            fixture.accountName == 'a.example' &&
            fixture.categoryName == 'a.example',
      );
      final oldRepository = fixture.container.read(accountRepositoryProvider);

      fixture.adapter.accountResponse = Completer<void>();
      final oldLoad = fixture.container
          .read(accountListControllerProvider.notifier)
          .load();
      await _waitFor(() => fixture.adapter.accountRequestHeld);
      await fixture.auth.changeServer();
      expect(fixture.accountName, isNot('a.example'));
      expect(fixture.categoryName, isNot('a.example'));
      await fixture.connect('b.example');
      await _waitFor(
        () =>
            fixture.accountName == 'b.example' &&
            fixture.categoryName == 'b.example',
      );
      fixture.adapter.accountResponse!.complete();
      await oldLoad;
      await Future<void>.delayed(Duration.zero);

      expect(fixture.accountName, 'b.example');
      expect(fixture.categoryName, 'b.example');
      expect(fixture.storage.accessToken, 'b.example-access');
      final requestCount = fixture.adapter.requests.length;
      await expectLater(
        oldRepository.list(),
        throwsA(isA<SessionChangedException>()),
      );
      expect(fixture.adapter.requests, hasLength(requestCount));
    },
  );

  test(
    'late login success cannot restore A tokens or authentication after changing to B',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.ready();
      await fixture.auth.connectServer('https://a.example');
      fixture.adapter.loginResponse = Completer<void>();
      final oldLogin = fixture.auth.login('password');
      await _waitFor(() => fixture.adapter.loginRequestHeld);
      await fixture.auth.changeServer();
      await fixture.connect('b.example');
      fixture.adapter.loginResponse!.complete();
      await oldLogin;

      expect(fixture.storage.accessToken, 'b.example-access');
      expect(fixture.storage.refreshToken, 'b.example-refresh');
      expect(
        fixture.container.read(authControllerProvider).serverUrl,
        'https://b.example',
      );
      expect(
        fixture.container.read(authControllerProvider).stage,
        AuthStage.authenticated,
      );
    },
  );

  test(
    'a pending credential write finishes before the new-session clear, so logout cannot resurrect tokens',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.connect('a.example');
      final saveStarted = Completer<void>();
      final finishSave = Completer<void>();
      fixture.storage.beforeSave = () async {
        saveStarted.complete();
        await finishSave.future;
      };
      final oldLogin = fixture.auth.login('password');
      await saveStarted.future;
      final changeServer = fixture.auth.changeServer();
      finishSave.complete();
      await Future.wait([oldLogin, changeServer]);

      expect(fixture.storage.accessToken, isNull);
      expect(fixture.storage.refreshToken, isNull);
      expect(fixture.storage.serverUrl, isNull);
      expect(
        fixture.container.read(authControllerProvider).stage,
        AuthStage.serverRequired,
      );
    },
  );

  test(
    'an old unauthorized response cannot expire the authenticated B session',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.connect('a.example');
      fixture.adapter.unauthorizedResponse = Completer<void>();
      final oldRequest = fixture.container
          .read(ledgerApiClientProvider)
          .get<void>('/late-401');
      final rejected = expectLater(
        oldRequest,
        throwsA(isA<SessionChangedException>()),
      );
      await _waitFor(() => fixture.adapter.unauthorizedRequestHeld);
      await fixture.auth.changeServer();
      await fixture.connect('b.example');
      fixture.adapter.unauthorizedResponse!.complete();
      await rejected;

      expect(fixture.storage.accessToken, 'b.example-access');
      expect(
        fixture.container.read(authControllerProvider).stage,
        AuthStage.authenticated,
      );
    },
  );

  test(
    'a refresh started for A cannot overwrite B credentials after a server switch',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.connect('a.example');
      fixture.storage.accessToken = 'a.example-expired';
      fixture.adapter.refreshResponse = Completer<void>();
      final oldRequest = fixture.container
          .read(ledgerApiClientProvider)
          .get<void>('/expired');
      final rejected = expectLater(
        oldRequest,
        throwsA(isA<SessionChangedException>()),
      );
      await _waitFor(() => fixture.adapter.refreshRequestHeld);
      await fixture.auth.changeServer();
      await fixture.connect('b.example');
      fixture.adapter.refreshResponse!.complete();
      await rejected;

      expect(fixture.storage.accessToken, 'b.example-access');
      expect(fixture.storage.refreshToken, 'b.example-refresh');
      expect(
        fixture.container.read(authControllerProvider).stage,
        AuthStage.authenticated,
      );
    },
  );

  test(
    'changing servers while logout clears credentials does not surface an obsolete cancellation',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.connect('a.example');
      final clearStarted = Completer<void>();
      final finishClear = Completer<void>();
      fixture.storage.beforeClear = () async {
        fixture.storage.beforeClear = null;
        clearStarted.complete();
        await finishClear.future;
      };
      final logout = fixture.auth.logout();
      await clearStarted.future;
      final changeServer = fixture.auth.changeServer();
      finishClear.complete();
      await expectLater(Future.wait([logout, changeServer]), completes);

      expect(fixture.storage.accessToken, isNull);
      expect(fixture.storage.serverUrl, isNull);
      expect(
        fixture.container.read(authControllerProvider).stage,
        AuthStage.serverRequired,
      );
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Expected client state was not reached');
}

class _Fixture {
  _Fixture() {
    final client = ApiClient(
      serverConfigService: ServerConfigService(storage),
      dio: Dio()..httpClientAdapter = adapter,
    );
    container = ProviderContainer(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(client),
      ],
    );
  }

  final storage = _MemoryStorage();
  final adapter = _LedgerAdapter();
  late final ProviderContainer container;
  AuthController get auth => container.read(authControllerProvider.notifier);
  String? get accountName => container
      .read(accountListControllerProvider)
      .asData
      ?.value
      .accounts
      .firstOrNull
      ?.name;
  String? get categoryName => container
      .read(categoryListControllerProvider)
      .asData
      ?.value
      .categories
      .firstOrNull
      ?.name;

  Future<void> ready() async {
    container.read(authControllerProvider);
    await _waitFor(
      () => container.read(authControllerProvider).stage != AuthStage.checking,
    );
  }

  Future<void> connect(String host) async {
    await ready();
    await auth.connectServer('https://$host');
    await auth.login('password');
    expect(
      container.read(authControllerProvider).stage,
      AuthStage.authenticated,
    );
  }

  void dispose() => container.dispose();
}

class _LedgerAdapter implements HttpClientAdapter {
  String? datasetName;
  final requests = <RequestOptions>[];
  Completer<void>? accountResponse;
  Completer<void>? loginResponse;
  Completer<void>? unauthorizedResponse;
  Completer<void>? refreshResponse;
  bool accountRequestHeld = false;
  bool loginRequestHeld = false;
  bool unauthorizedRequestHeld = false;
  bool refreshRequestHeld = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final host = options.uri.host;
    final name = datasetName ?? host;
    final balance = datasetName == null ? 123 : 456;
    Object? data;
    switch (options.path) {
      case '/auth/status':
        data = {'initialized': true};
      case '/auth/login':
        if (host == 'a.example' && loginResponse != null) {
          loginRequestHeld = true;
          await loginResponse!.future;
        }
        data = {
          'access_token': '$host-access',
          'refresh_token': '$host-refresh',
        };
      case '/auth/profile':
        data = {'id': 1};
      case '/auth/refresh':
        refreshRequestHeld = true;
        await refreshResponse!.future;
        data = {
          'access_token': '$host-refreshed-access',
          'refresh_token': '$host-refreshed-refresh',
        };
      case '/auth/logout':
        data = null;
      case '/accounts':
        if (host == 'a.example' && accountResponse != null) {
          accountRequestHeld = true;
          await accountResponse!.future;
        }
        data = {
          'list': [
            {'id': '$host-wallet', 'name': name},
          ],
          'total_assets': balance,
          'total_liabilities': 0,
          'net_assets': balance,
        };
      case '/categories':
        data = {
          'list': [
            {'id': '$host-category', 'name': name, 'type': 'expense'},
          ],
        };
      case '/statistics/overview':
        data = {'balance': balance};
      case '/statistics/trend':
      case '/statistics/categories':
      case '/budgets/summary':
      case '/family/summary':
        data = <String, Object?>{};
      case '/transactions':
        data = {'list': <Object?>[]};
      case '/late-401':
        unauthorizedRequestHeld = true;
        await unauthorizedResponse!.future;
        return _response(401, {'code': 40101, 'message': 'unauthorized'});
      case '/expired':
        return _response(401, {'code': 40102, 'message': 'expired'});
      default:
        throw StateError('Unexpected request: ${options.path}');
    }
    return _response(200, {'code': 0, 'data': data});
  }

  ResponseBody _response(int status, Map<String, Object?> body) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

class _MemoryStorage extends SecureStorageService {
  String? serverUrl;
  String? accessToken;
  String? refreshToken;
  Future<void> Function()? beforeSave;
  Future<void> Function()? beforeClear;

  @override
  Future<String?> readServerUrl() async => serverUrl;
  @override
  Future<void> saveServerUrl(String value) async {
    serverUrl = value;
  }

  @override
  Future<void> deleteServerUrl() async {
    serverUrl = null;
  }

  @override
  Future<void> deleteInsecureLocalHttpAcknowledgedUrl() async {}
  @override
  Future<String?> readAccessToken() async => accessToken;
  @override
  Future<String?> readRefreshToken() async => refreshToken;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await beforeSave?.call();
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    await beforeClear?.call();
    accessToken = null;
    refreshToken = null;
  }
}
