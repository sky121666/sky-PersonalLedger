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
          aiReportScheduleProvider.overrideWith(
            (ref) async => const AIReportScheduleSettings(),
          ),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 财务报告'), findsOneWidget);
    expect(find.text('每周总结'), findsWidgets);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.byType(PremiumSurface), findsWidgets);
    expect(find.text('DeepSeek / deepseek-chat'), findsOneWidget);

    await tester.tap(find.text('DeepSeek / deepseek-chat'));
    await tester.pumpAndSettle();

    expect(find.text('支出可控'), findsWidgets);
    expect(find.text('• 净现金流为正'), findsOneWidget);
    expect(find.text('• 预算偏高'), findsOneWidget);
    expect(find.text('• 继续记录'), findsOneWidget);
  });

  testWidgets('AIReportsPage 空态可见', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiReportsProvider.overrideWith((ref) async => const []),
          aiReportScheduleProvider.overrideWith(
            (ref) async => const AIReportScheduleSettings(),
          ),
        ],
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
          aiReportScheduleProvider.overrideWith(
            (ref) async => const AIReportScheduleSettings(),
          ),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('失败'), findsOneWidget);

    await tester.tap(find.text('DeepSeek / deepseek-chat'));
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

  testWidgets('AIReportsPage 可管理自动报告设置', (tester) async {
    final repository = _FakeAIReportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自动报告'), findsOneWidget);
    expect(find.text('默认关闭'), findsOneWidget);

    await tester.tap(find.text('启用自动生成'));
    await tester.pumpAndSettle();

    expect(repository.savedSchedule.enabled, isTrue);
    expect(find.text('自动报告设置已保存'), findsOneWidget);

    await tester.tap(find.text('立即触发应生成报告'));
    await tester.pump();

    expect(repository.triggerCalls, 1);
  });
}

class _FakeAIReportRepository implements AIReportRepository {
  final List<GenerateAIReportRequest> generateCalls = [];
  var triggerCalls = 0;
  var savedSchedule = const AIReportScheduleSettings();
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

  @override
  Future<AIReportScheduleSettings> getScheduleSettings() async {
    return savedSchedule;
  }

  @override
  Future<AIReportScheduleSettings> updateScheduleSettings(
    AIReportScheduleSettings settings,
  ) async {
    savedSchedule = settings;
    return savedSchedule;
  }

  @override
  Future<List<AIReportScheduleRunResult>> triggerSchedule() async {
    triggerCalls++;
    return const [
      AIReportScheduleRunResult(
        reportType: 'weekly',
        periodStart: '2026-05-18',
        periodEnd: '2026-05-24',
        attempted: 1,
        succeeded: 1,
      ),
    ];
  }
}
