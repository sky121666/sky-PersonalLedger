import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
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
          themeControllerProvider.overrideWith(
            (ref) => _FixedThemeController(AppThemePalette.teal),
          ),
        ],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('财务报告'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-report-command-center')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-provider-orchestration-panel')),
      findsNothing,
    );
    expect(find.text('AI 分析控制台'), findsNothing);
    expect(find.text('报告总数'), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-runtime-contract-rail')),
      findsNothing,
    );
    expect(find.text('数据脱敏'), findsNothing);
    expect(find.text('本地留痕'), findsNothing);
    expect(find.text('人工触发'), findsNothing);
    expect(find.text('待接入'), findsNothing);
    expect(find.text('静谧墨绿'), findsNothing);
    expect(find.text('周报未启用'), findsNothing);
    expect(find.text('Key 不回显'), findsNothing);
    await _scrollIntoTapArea(tester, find.text('分析方式'));
    expect(find.text('分析方式'), findsOneWidget);
    expect(find.text('报告服务'), findsNothing);
    expect(find.text('报告来源'), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-production-readiness-panel')),
      findsNothing,
    );
    expect(find.text('AI 生产就绪层'), findsNothing);
    expect(
      find.byKey(const ValueKey('ai-insight-quality-panel')),
      findsNothing,
    );
    expect(find.text('AI 洞察质量层'), findsNothing);
    expect(find.text('重点'), findsNothing);
    expect(find.text('风险'), findsNothing);
    expect(find.text('关注'), findsNothing);
    expect(find.text('建议 1 条'), findsNothing);
    expect(find.text('默认脱敏'), findsNothing);
    expect(find.text('手动生成'), findsNothing);
    expect(find.text('OpenAI API'), findsNothing);
    await _scrollIntoTapArea(tester, find.text('分析方式'));
    await _scrollIntoTapArea(
      tester,
      find.byKey(const ValueKey('ai-report-card-report-1')),
    );
    expect(find.text('每周总结'), findsWidgets);
    expect(
      find.byKey(const ValueKey('ai-report-status-report-1')),
      findsOneWidget,
    );
    expect(find.byType(PremiumSurface), findsWidgets);
    expect(find.text('DeepSeek / deepseek-v4-flash'), findsNothing);
    expect(find.text('DeepSeek'), findsWidgets);

    await _tapReportTitle(tester, 'report-1');
    await tester.pumpAndSettle();

    expect(find.text('支出可控'), findsWidgets);
    expect(find.text('洞察构成'), findsNothing);
    expect(find.text('3 条'), findsNothing);
    expect(find.text('重点 1'), findsNothing);
    expect(find.text('风险 1'), findsNothing);
    expect(find.text('关注 1'), findsNothing);
    expect(find.text('建议 1'), findsNothing);
    expect(find.text('• 净现金流为正'), findsOneWidget);
    expect(find.text('• 预算偏高'), findsOneWidget);
    expect(find.text('• 继续记录'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
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
          themeControllerProvider.overrideWith(
            (ref) => _FixedThemeController(AppThemePalette.graphite),
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

    expect(find.text('石墨蓝'), findsNothing);
    await _scrollIntoTapArea(
      tester,
      find.byKey(const ValueKey('ai-report-card-report-1')),
    );
    final surfaces = tester.widgetList<PremiumSurface>(
      find.byType(PremiumSurface),
    );
    expect(
      surfaces.any(
        (surface) =>
            surface.accentColor == AppThemePalette.graphite.incomeColor ||
            surface.accentColor == AppThemePalette.graphite.assetColor,
      ),
      isTrue,
    );

    await _tapReportTitle(tester, 'report-1');

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

    expect(find.text('AI 分析控制台'), findsNothing);
    expect(find.text('AI 模型编排'), findsNothing);
    expect(find.text('等待生成'), findsNothing);
    await tester.scrollUntilVisible(find.text('还没有报告'), 300);
    expect(find.text('还没有报告'), findsOneWidget);
    expect(find.text('添加分析方式'), findsOneWidget);
    expect(find.text('先添加分析方式，再生成报告'), findsNothing);
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

    await _scrollIntoTapArea(
      tester,
      find.byKey(const ValueKey('ai-report-card-report-failed')),
    );
    expect(
      find.byKey(const ValueKey('ai-report-status-report-failed')),
      findsOneWidget,
    );

    await _tapReportTitle(tester, 'report-failed');

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

    await tester.tap(find.byKey(const ValueKey('ai-report-generate')));
    await tester.pumpAndSettle();
    expect(find.text('生成报告'), findsAtLeastNWidgets(1));
    expect(find.text('DeepSeek'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const ValueKey('ai-report-generate-submit')));
    await tester.pumpAndSettle();

    expect(repository.generateCalls, hasLength(1));
    expect(repository.generateCalls.single.reportType, 'weekly');
    expect(repository.generateCalls.single.providerId, 'provider-existing');
    expect(repository.generateCalls.single.maskNames, isTrue);
    expect(find.text('报告已生成'), findsOneWidget);
  });

  testWidgets('AIReportsPage 可删除历史报告', (tester) async {
    final repository = _FakeAIReportRepository()
      ..reports.add(
        const AIReportSummary(
          id: 'report-delete',
          reportType: 'weekly',
          status: 'completed',
          periodStart: '2026-05-18',
          periodEnd: '2026-05-24',
          providerName: 'DeepSeek',
          model: 'deepseek-v4-flash',
          contentJson: '{"summary":"支出可控"}',
        ),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollIntoTapArea(
      tester,
      find.byKey(const ValueKey('ai-report-card-report-delete')),
    );
    await tester.tap(find.text('每周总结').last);
    await tester.pumpAndSettle();
    await _scrollIntoTapArea(tester, find.text('删除报告'));
    await tester.tap(find.text('删除报告'));
    await tester.pumpAndSettle();
    expect(find.text('删除「每周总结」？'), findsOneWidget);
    expect(find.text('报告将移除。'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repository.deletedReportIds, ['report-delete']);
    expect(find.text('报告已删除'), findsOneWidget);
    expect(find.text('支出可控'), findsNothing);
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

    await tester.tap(find.byKey(const ValueKey('ai-report-generate')));
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

  testWidgets('AIReportsPage 可管理定期报告设置', (tester) async {
    final repository = _FakeAIReportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('定期报告'), findsAtLeastNWidgets(1));
    expect(find.text('自动报告'), findsNothing);
    await _scrollIntoTapArea(tester, find.text('未开启'));
    expect(find.text('未开启'), findsOneWidget);
    expect(find.text('生成时间'), findsOneWidget);
    expect(find.text('运行时间'), findsNothing);
    expect(find.text('报告类型'), findsOneWidget);

    await _scrollIntoTapArea(tester, find.text('启用定期生成'));
    final scheduleSwitchSemantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('ai-schedule-enabled-semantics')),
    );
    expect(scheduleSwitchSemantics.properties.label, '启用定期生成报告');
    await tester.tap(find.text('启用定期生成'));
    await tester.pumpAndSettle();

    expect(repository.savedSchedule.enabled, isTrue);
    expect(find.text('定期报告设置已保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.scrollUntilVisible(find.text('立即生成'), 300);
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-schedule-trigger')));
    await tester.pump();

    expect(repository.triggerCalls, 1);
  });

  testWidgets('AIReportsPage 可配置和检查 Provider', (tester) async {
    final repository = _FakeAIReportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiReportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AIReportsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollIntoTapArea(tester, find.text('分析方式'));
    expect(find.text('分析方式'), findsAtLeastNWidgets(1));
    expect(find.text('报告服务'), findsNothing);
    expect(find.text('报告来源'), findsNothing);
    expect(find.text('还没有方式'), findsOneWidget);
    expect(find.text('暂无可用服务'), findsNothing);
    expect(find.text('暂无可用来源'), findsNothing);

    await _scrollIntoTapArea(tester, find.text('添加方式'));
    await tester.tap(find.text('添加方式').last);
    await tester.pumpAndSettle();
    expect(find.text('分析方式'), findsAtLeastNWidgets(1));
    expect(find.text('服务模板'), findsNothing);
    expect(find.text('预设'), findsNothing);
    expect(find.text('分析能力'), findsOneWidget);
    expect(find.text('使用模型'), findsNothing);
    expect(find.text('模型'), findsNothing);
    expect(find.text('连接地址'), findsNothing);
    expect(find.text('服务地址'), findsOneWidget);
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('密钥'), findsOneWidget);
    expect(find.text('访问凭证'), findsNothing);
    expect(find.text('访问密钥'), findsNothing);
    expect(find.text('API Key'), findsNothing);
    expect(find.text('保存方式'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('ai-provider-api-key')),
      'sk-mobile-test',
    );
    await tester.tap(find.byKey(const ValueKey('ai-provider-save')));
    await tester.pumpAndSettle();

    expect(repository.createdProviders, hasLength(1));
    expect(repository.createdProviders.single.name, 'DeepSeek');
    expect(repository.createdProviders.single.apiKey, 'sk-mobile-test');
    expect(find.text('方式已保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await _openProviderActions(tester, 'provider-1');
    await tester.tap(find.text('检查'));
    await tester.pumpAndSettle();

    expect(repository.testProviderIds, ['provider-1']);
    expect(find.text('服务检查通过'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await _openProviderActions(tester, 'provider-1');
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), 'deepseek-reasoner');
    await tester.tap(find.byKey(const ValueKey('ai-provider-save')));
    await tester.pumpAndSettle();

    expect(repository.updatedProviderIds, ['provider-1']);
    expect(repository.updatedProviders.single.apiKey, isEmpty);
    expect(repository.providers.single.model, 'deepseek-reasoner');
    expect(find.text('方式已更新'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await _openProviderActions(tester, 'provider-1');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除分析方式'), findsOneWidget);
    expect(find.text('删除「DeepSeek」？'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PremiumSurface), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(repository.deletedProviderIds, ['provider-1']);
    expect(repository.providers, isEmpty);
    expect(find.text('方式已删除'), findsOneWidget);
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

Future<void> _scrollIntoTapArea(WidgetTester tester, Finder finder) async {
  var target = finder.evaluate().length > 1 ? finder.last : finder;
  if (!_isInTapArea(tester, target)) {
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: scrollable.first,
      );
    }
    await tester.pumpAndSettle();
  }
  target = finder.evaluate().length > 1 ? finder.last : finder;
  final center = tester.getCenter(target);
  final listView = find.byType(ListView);
  if (center.dy > 500 && listView.evaluate().isNotEmpty) {
    await tester.drag(listView.first, Offset(0, -(center.dy - 420)));
    await tester.pumpAndSettle();
  }
  if (center.dy < 88 && listView.evaluate().isNotEmpty) {
    await tester.drag(listView.first, Offset(0, 112 - center.dy));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapReportTitle(WidgetTester tester, String reportId) async {
  final card = find.byKey(ValueKey('ai-report-card-$reportId'));
  final title = find.descendant(of: card, matching: find.text('每周总结'));
  await tester.tap(title);
  await tester.pumpAndSettle();
}

Future<void> _openProviderActions(
  WidgetTester tester,
  String providerId,
) async {
  final menu = find.byKey(ValueKey('ai-provider-toggle-$providerId'));
  final editAction = find.byKey(
    ValueKey('ai-provider-action-edit-$providerId'),
  );
  if (editAction.evaluate().isNotEmpty) {
    return;
  }

  await _scrollIntoTapArea(tester, menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  if (editAction.evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

bool _isInTapArea(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) {
    return false;
  }
  try {
    final center = tester.getCenter(finder);
    return center.dy >= 88 && center.dy <= 500;
  } catch (_) {
    return false;
  }
}

class _FixedThemeController extends ThemeController {
  _FixedThemeController(AppThemePalette palette) {
    state = AppThemeSettings(palette: palette);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> setPalette(AppThemePalette palette) async {
    state = state.copyWith(palette: palette);
  }
}

class _FakeAIReportRepository implements AIReportRepository {
  final List<GenerateAIReportRequest> generateCalls = [];
  final List<SaveAIProviderRequest> createdProviders = [];
  final List<SaveAIProviderRequest> updatedProviders = [];
  final List<String> updatedProviderIds = [];
  final List<String> deletedProviderIds = [];
  final List<String> testProviderIds = [];
  final List<String> deletedReportIds = [];
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
  Future<void> deleteReport(String id) async {
    deletedReportIds.add(id);
    reports.removeWhere((report) => report.id == id);
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
