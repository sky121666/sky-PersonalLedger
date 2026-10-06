import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/config/server_config_service.dart';
import 'package:personal_ledger/core/network/api_client.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';
import 'package:personal_ledger/features/ai/data/ai_report_repository.dart';

void main() {
  test(
    'AI generation can wait for the backend while ordinary reads retain their shorter timeout',
    () async {
      final adapter = _ReportAdapter();
      final client = ApiClient(
        serverConfigService: ServerConfigService(SecureStorageService()),
        dio: Dio()..httpClientAdapter = adapter,
      );
      client.dio.options.baseUrl = 'https://ledger.example/api/v1';
      final repository = AIReportRepository(client.forCurrentSession());
      final report = await repository.generateReport(
        const GenerateAIReportRequest(
          reportType: 'weekly',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-07',
        ),
      );
      await repository.listReports();

      expect(report.id, 'generated-report');
      expect(adapter.requests[0].receiveTimeout, const Duration(seconds: 45));
      expect(adapter.requests[1].receiveTimeout, const Duration(seconds: 10));
      expect(client.dio.options.receiveTimeout, const Duration(seconds: 10));
    },
  );
}

class _ReportAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': options.method == 'POST' ? {'id': 'generated-report'} : [],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
