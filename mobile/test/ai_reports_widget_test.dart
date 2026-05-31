import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
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
                model: 'deepseek-v4-flash',
                contentJson:
                    '{"summary":"支出可控","highlights":["净现金流为正"],"risks":["预算偏高"],"suggestions":["继续记录"]}',
                snapshotJson:
                    '{"account_changes":[{"account_name":"账户1","balance_delta":380}]}',
              ),
            ];
          }),
          aiReportScheduleProvider.overrideWith(
            (ref) async => const AIReportScheduleSettings(),
          ),
          aiProviderSetupProvider.overrideWith(
            (ref) async =>
                const AIProviderSetupData(presets: [], providers: []),
          ),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 财务报告'), findsOneWidget);
    expect(find.text('0 个启用'), findsOneWidget);
    expect(find.text('Key 已保护'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('DeepSeek / deepseek-v4-flash'),
      300,
    );
    expect(find.text('每周总结'), findsWidgets);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.byType(PremiumSurface), findsWidgets);
    expect(find.text('DeepSeek / deepseek-v4-flash'), findsWidgets);

    await tester.tap(find.text('DeepSeek / deepseek-v4-flash'));
    await tester.pumpAndSettle();

    expect(find.text('支出可控'), findsWidgets);
    expect(find.text('• 净现金流为正'), findsOneWidget);
    expect(find.text('• 预算偏高'), findsOneWidget);
    expect(find.text('• 继续记录'), findsOneWidget);
    expect(find.text('账户变化'), findsOneWidget);
    expect(find.text('账户1'), findsOneWidget);
    expect(find.text('+¥380.00'), findsOneWidget);
  });

  testWidgets('AIReportsPage 跟随主题色模板', (tester) async {
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
                model: 'deepseek-v4-flash',
                contentJson:
                    '{"summary":"支出可控","highlights":["净现金流为正"],"risks":["预算偏高"],"suggestions":["继续记录"]}',
                snapshotJson:
                    '{"account_changes":[{"account_name":"账户1","balance_delta":380}]}',
              ),
            ];
          }),
          aiReportScheduleProvider.overrideWith(
            (ref) async => const AIReportScheduleSettings(),
          ),
          aiProviderSetupProvider.overrideWith(
            (ref) async =>
                const AIProviderSetupData(presets: [], providers: []),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(AppThemePalette.graphite),
          darkTheme: AppTheme.darkTheme(AppThemePalette.graphite),
          home: const AIReportsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('DeepSeek / deepseek-v4-flash'),
      300,
    );

    final surfaces = tester.widgetList<PremiumSurface>(
      find.byType(PremiumSurface),
    );
    expect(
      surfaces.any(
        (surface) => surface.accentColor == AppThemePalette.graphite.assetColor,
      ),
      isTrue,
    );

    await tester.tap(find.text('DeepSeek / deepseek-v4-flash'));
    await tester.pumpAndSettle();

    final highlightIcon = tester.widget<Icon>(
      find.byIcon(Icons.trending_up_outlined).first,
    );
    final riskIcon = tester.widget<Icon>(
      find.byIcon(Icons.warning_amber_outlined).first,
    );
    expect(highlightIcon.color, AppThemePalette.graphite.incomeColor);
    expect(riskIcon.color, AppThemePalette.graphite.warningColor);
  });

  testWidgets('AIReportsPage 空态可见', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiReportsProvider.overrideWith((ref) async => const []),
          aiReportScheduleProvider.overrideWith(
            (ref) async => const AIReportScheduleSettings(),
          ),
          aiProviderSetupProvider.overrideWith(
            (ref) async =>
                const AIProviderSetupData(presets: [], providers: []),
          ),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('暂无 AI 报告'), 300);
    expect(find.text('暂无 AI 报告'), findsOneWidget);
    expect(find.text('生成报告'), findsWidgets);
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
                model: 'deepseek-v4-flash',
                errorMessage: 'enabled ai provider not found',
              ),
            ];
          }),
          aiReportScheduleProvider.overrideWith(
            (ref) async => const AIReportScheduleSettings(),
          ),
          aiProviderSetupProvider.overrideWith(
            (ref) async =>
                const AIProviderSetupData(presets: [], providers: []),
          ),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('DeepSeek / deepseek-v4-flash'),
      300,
    );
    expect(find.text('失败'), findsOneWidget);

    await tester.tap(find.text('DeepSeek / deepseek-v4-flash'));
    await tester.pumpAndSettle();

    expect(find.text('enabled ai provider not found'), findsWidgets);
  });

  testWidgets('AIReportsPage 可触发生成本周报告', (tester) async {
    final repository = _FakeAIReportRepository();
    repository.providers.add(
      const AIProviderSummary(
        id: 'provider-existing',
        name: 'DeepSeek',
        providerType: 'openai_compatible',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        enabled: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('生成报告'));
    await tester.pumpAndSettle();
    expect(find.text('生成 AI 报告'), findsOneWidget);
    expect(find.text('DeepSeek / deepseek-v4-flash'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-report-generate-submit')));
    await tester.pumpAndSettle();

    expect(repository.generateCalls, hasLength(1));
    expect(repository.generateCalls.single.reportType, 'weekly');
    expect(repository.generateCalls.single.providerId, 'provider-existing');
    expect(repository.generateCalls.single.maskNames, isTrue);
    expect(find.text('AI 报告已生成'), findsOneWidget);
  });

  testWidgets('AIReportsPage 校验报告周期', (tester) async {
    final repository = _FakeAIReportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('生成报告'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-report-start-date')),
      '2026-05-31',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-report-end-date')),
      '2026-05-01',
    );
    await tester.tap(find.byKey(const ValueKey('ai-report-generate-submit')));
    await tester.pumpAndSettle();

    expect(repository.generateCalls, isEmpty);
    expect(find.text('开始日期不能晚于结束日期'), findsOneWidget);
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
    expect(find.text('运行时间'), findsOneWidget);
    expect(find.text('聚合快照'), findsOneWidget);

    await tester.tap(find.text('启用自动生成'));
    await tester.pumpAndSettle();

    expect(repository.savedSchedule.enabled, isTrue);
    expect(find.text('自动报告设置已保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.scrollUntilVisible(find.text('立即触发应生成报告'), 300);
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-schedule-trigger')));
    await tester.pump();

    expect(repository.triggerCalls, 1);
  });

  testWidgets('AIReportsPage 可配置和测试 Provider', (tester) async {
    final repository = _FakeAIReportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Provider 配置'), findsOneWidget);
    expect(find.text('暂无 Provider'), findsOneWidget);
    expect(find.text('0 个启用'), findsOneWidget);
    expect(find.text('Key 已保护'), findsOneWidget);

    await tester.tap(find.text('添加 Provider'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-provider-api-key')),
      'sk-mobile-test',
    );
    await tester.tap(find.byKey(const ValueKey('ai-provider-save')));
    await tester.pumpAndSettle();

    expect(repository.createdProviders, hasLength(1));
    expect(repository.createdProviders.single.name, 'DeepSeek');
    expect(repository.createdProviders.single.apiKey, 'sk-mobile-test');
    expect(find.text('Provider 已保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const ValueKey('ai-provider-test-provider-1')));
    await tester.pumpAndSettle();

    expect(repository.testProviderIds, ['provider-1']);
    expect(find.text('连接测试通过'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const ValueKey('ai-provider-edit-provider-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), 'deepseek-reasoner');
    await tester.tap(find.byKey(const ValueKey('ai-provider-save')));
    await tester.pumpAndSettle();

    expect(repository.updatedProviderIds, ['provider-1']);
    expect(repository.updatedProviders.single.apiKey, isEmpty);
    expect(repository.providers.single.model, 'deepseek-reasoner');
    expect(find.text('Provider 已更新'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.tap(
      find.byKey(const ValueKey('ai-provider-delete-provider-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(repository.deletedProviderIds, ['provider-1']);
    expect(repository.providers, isEmpty);
    expect(find.text('Provider 已删除'), findsOneWidget);
  });

  test('空 AI Provider API Key 不会进入移动端请求 JSON', () {
    const request = SaveAIProviderRequest(
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-v4-flash',
      apiKey: '',
    );

    final payload = request.toJson();

    expect(payload, isNot(contains('api_key')));
  });
}

class _FakeAIReportRepository implements AIReportRepository {
  final List<GenerateAIReportRequest> generateCalls = [];
  final List<SaveAIProviderRequest> createdProviders = [];
  final List<SaveAIProviderRequest> updatedProviders = [];
  final List<String> updatedProviderIds = [];
  final List<String> deletedProviderIds = [];
  final List<String> testProviderIds = [];
  var triggerCalls = 0;
  var savedSchedule = const AIReportScheduleSettings();
  final reports = <AIReportSummary>[];
  final providers = <AIProviderSummary>[];

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

  @override
  Future<List<AIProviderPreset>> listProviderPresets() async {
    return const [
      AIProviderPreset(
        id: 'deepseek',
        name: 'DeepSeek',
        providerType: 'openai_compatible',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        models: [
          'deepseek-v4-flash',
          'deepseek-v4-pro',
          'deepseek-chat',
          'deepseek-reasoner',
        ],
      ),
    ];
  }

  @override
  Future<List<AIProviderSummary>> listProviders() async {
    return providers;
  }

  @override
  Future<AIProviderSummary> createProvider(
    SaveAIProviderRequest request,
  ) async {
    createdProviders.add(request);
    final provider = AIProviderSummary(
      id: 'provider-1',
      name: request.name,
      providerType: request.providerType,
      baseUrl: request.baseUrl,
      model: request.model,
      enabled: request.enabled,
    );
    providers.add(provider);
    return provider;
  }

  @override
  Future<AIProviderSummary> updateProvider(
    String id,
    SaveAIProviderRequest request,
  ) async {
    updatedProviderIds.add(id);
    updatedProviders.add(request);
    final index = providers.indexWhere((provider) => provider.id == id);
    final provider = AIProviderSummary(
      id: id,
      name: request.name,
      providerType: request.providerType,
      baseUrl: request.baseUrl,
      model: request.model,
      enabled: request.enabled,
    );
    if (index == -1) {
      providers.add(provider);
    } else {
      providers[index] = provider;
    }
    return provider;
  }

  @override
  Future<void> deleteProvider(String id) async {
    deletedProviderIds.add(id);
    providers.removeWhere((provider) => provider.id == id);
  }

  @override
  Future<void> testProvider(String id) async {
    testProviderIds.add(id);
  }
}
