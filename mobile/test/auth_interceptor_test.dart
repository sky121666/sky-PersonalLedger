import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/network/auth_interceptor.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';

void main() {
  test('refreshes an expired token once for concurrent requests', () async {
    final storage = _MemorySecureStorage(
      accessToken: 'expired-access',
      refreshToken: 'valid-refresh',
    );
    final adapter = _TokenRefreshAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://ledger.example.com/api/v1',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(AuthInterceptor(dio: dio, secureStorage: storage));

    final responses = await Future.wait([
      dio.get<Object?>('/protected'),
      dio.get<Object?>('/protected'),
      dio.get<Object?>('/protected'),
    ]);

    expect(adapter.refreshRequests, 1);
    expect(adapter.protectedRequests, 6);
    expect(adapter.refreshRequestAuthHeaders, [isNull]);
    expect(
      adapter.protectedRequestAuthHeaders.where(
        (header) => header == 'Bearer fresh-access',
      ),
      hasLength(3),
    );
    expect(storage.accessToken, 'fresh-access');
    expect(storage.refreshToken, 'fresh-refresh');
    expect(
      responses.map((response) => response.data),
      everyElement({'code': 0, 'message': 'ok', 'data': 'done'}),
    );
  });

  test(
    'does not recursively refresh when the refresh request is rejected',
    () async {
      final storage = _MemorySecureStorage(
        accessToken: 'expired-access',
        refreshToken: 'invalid-refresh',
      );
      final adapter = _TokenRefreshAdapter(refreshShouldFail: true);
      var expired = false;
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://ledger.example.com/api/v1',
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      )..httpClientAdapter = adapter;
      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          secureStorage: storage,
          onSessionExpired: () {
            expired = true;
          },
        ),
      );

      await expectLater(
        dio.get<Object?>('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(adapter.refreshRequests, 1);
      expect(expired, isTrue);
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    },
  );

  test(
    'expires the session once when concurrent refresh attempts fail',
    () async {
      final storage = _MemorySecureStorage(
        accessToken: 'expired-access',
        refreshToken: 'invalid-refresh',
      );
      final adapter = _TokenRefreshAdapter(refreshShouldFail: true);
      var expiredCalls = 0;
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://ledger.example.com/api/v1',
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      )..httpClientAdapter = adapter;
      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          secureStorage: storage,
          onSessionExpired: () async {
            expiredCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          },
        ),
      );

      final results = await Future.wait(
        [
          dio.get<Object?>('/protected'),
          dio.get<Object?>('/protected'),
          dio.get<Object?>('/protected'),
        ].map((request) async {
          try {
            await request;
            return false;
          } on DioException {
            return true;
          }
        }),
      );

      expect(results, everyElement(isTrue));
      expect(adapter.refreshRequests, 1);
      expect(expiredCalls, 1);
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    },
  );

  test(
    'expires the session when a retried request is still unauthorized',
    () async {
      final storage = _MemorySecureStorage(
        accessToken: 'expired-access',
        refreshToken: 'valid-refresh',
      );
      final adapter = _TokenRefreshAdapter(retriedRequestShouldFail: true);
      var expired = false;
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://ledger.example.com/api/v1',
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      )..httpClientAdapter = adapter;
      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          secureStorage: storage,
          onSessionExpired: () {
            expired = true;
          },
        ),
      );

      await expectLater(
        dio.get<Object?>('/protected'),
        throwsA(isA<DioException>()),
      );

      expect(adapter.refreshRequests, 1);
      expect(expired, isTrue);
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    },
  );
}

class _TokenRefreshAdapter implements HttpClientAdapter {
  _TokenRefreshAdapter({
    this.refreshShouldFail = false,
    this.retriedRequestShouldFail = false,
  });

  final bool refreshShouldFail;
  final bool retriedRequestShouldFail;
  int protectedRequests = 0;
  int refreshRequests = 0;
  final List<String?> protectedRequestAuthHeaders = [];
  final List<String?> refreshRequestAuthHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/refresh') {
      refreshRequests++;
      refreshRequestAuthHeaders.add(_authorizationHeader(options));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (refreshShouldFail) {
        return _jsonResponse(options, 401, {
          'code': 40102,
          'message': 'refresh expired',
          'data': null,
        });
      }
      return _jsonResponse(options, 200, {
        'code': 0,
        'message': 'ok',
        'data': {
          'access_token': 'fresh-access',
          'refresh_token': 'fresh-refresh',
          'expires_in': 900,
        },
      });
    }

    if (options.path == '/protected') {
      protectedRequests++;
      final authHeader = _authorizationHeader(options);
      protectedRequestAuthHeaders.add(authHeader);
      if (authHeader == 'Bearer fresh-access' && !retriedRequestShouldFail) {
        return _jsonResponse(options, 200, {
          'code': 0,
          'message': 'ok',
          'data': 'done',
        });
      }
      return _jsonResponse(options, 401, {
        'code': 40102,
        'message': 'token expired',
        'data': null,
      });
    }

    return _jsonResponse(options, 404, {
      'code': 404,
      'message': 'not found',
      'data': null,
    });
  }

  String? _authorizationHeader(RequestOptions options) {
    final value = options.headers['Authorization'];
    return value is String ? value : null;
  }

  ResponseBody _jsonResponse(
    RequestOptions options,
    int statusCode,
    Map<String, Object?> body,
  ) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemorySecureStorage extends SecureStorageService {
  _MemorySecureStorage({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<void> saveAccessToken(String accessToken) async {
    this.accessToken = accessToken;
  }

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveRefreshToken(String refreshToken) async {
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }
}
