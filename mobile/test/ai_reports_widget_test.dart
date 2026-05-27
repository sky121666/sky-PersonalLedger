import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/ai/data/ai_report_repository.dart';
import 'package:personal_ledger/features/ai/presentation/ai_reports_page.dart';

void main() {
  testWidgets('AIReportsPage 展示报告列表', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiReportsProvider.overrideWith((ref) async {
            return const [
              AIReportSummary(
                id: 'report-1',
                reportType: 'weekly',
                status: 'completed',
                periodStart: '2026-05-18T00:00:00Z',
                periodEnd: '2026-05-24T23:59:59Z',
                providerName: 'DeepSeek',
                model: 'deepseek-chat',
                contentJson:
                    '{"summary":"支出可控","highlights":["净现金流为正"],"risks":["预算偏高"],"suggestions":["继续记录"]}',
              ),
            ];
          }),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 财务报告'), findsOneWidget);
    expect(find.text('每周总结'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.byType(PremiumSurface), findsWidgets);
    expect(find.text('DeepSeek / deepseek-chat'), findsOneWidget);

    await tester.tap(find.text('每周总结'));
    await tester.pumpAndSettle();

    expect(find.text('支出可控'), findsWidgets);
    expect(find.text('• 净现金流为正'), findsOneWidget);
    expect(find.text('• 预算偏高'), findsOneWidget);
    expect(find.text('• 继续记录'), findsOneWidget);
  });

  testWidgets('AIReportsPage 空态可见', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportsProvider.overrideWith((ref) async => const [])],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无 AI 报告'), findsOneWidget);
    expect(find.text('生成本周报告'), findsWidgets);
  });

  testWidgets('AIReportsPage 展示失败报告错误态', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiReportsProvider.overrideWith((ref) async {
            return const [
              AIReportSummary(
                id: 'report-failed',
                reportType: 'weekly',
                status: 'failed',
                periodStart: '2026-05-18T00:00:00Z',
                periodEnd: '2026-05-24T23:59:59Z',
                providerName: 'DeepSeek',
                model: 'deepseek-chat',
                errorMessage: 'enabled ai provider not found',
              ),
            ];
          }),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('失败'), findsOneWidget);

    await tester.tap(find.text('每周总结'));
    await tester.pumpAndSettle();

    expect(find.text('enabled ai provider not found'), findsWidgets);
  });

  testWidgets('AIReportsPage 可触发生成本周报告', (tester) async {
    final repository = _FakeAIReportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('生成本周报告'));
    await tester.pumpAndSettle();

    expect(repository.generateCalls, hasLength(1));
    expect(repository.generateCalls.single.reportType, 'weekly');
    expect(find.text('AI 报告已生成'), findsOneWidget);
  });
}

class _FakeAIReportRepository implements AIReportRepository {
  final List<GenerateAIReportRequest> generateCalls = [];
  final reports = <AIReportSummary>[];

  @override
  Future<AIReportSummary> generateReport(
    GenerateAIReportRequest request,
  ) async {
    generateCalls.add(request);
    final report = AIReportSummary(
      id: 'generated-1',
      reportType: request.reportType,
      status: 'completed',
      periodStart: request.periodStart,
      periodEnd: request.periodEnd,
      providerName: 'Fake',
      model: 'fake-model',
    );
    reports.add(report);
    return report;
  }

  @override
  Future<List<AIReportSummary>> listReports() async {
    return reports;
  }
}
