import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/api_tokens/data/api_token_repository.dart';
import 'package:personal_ledger/features/api_tokens/presentation/api_token_page.dart';

void main() {
  group('ApiTokenPage', () {
    testWidgets('展示令牌列表和有效期状态', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      expect(find.text('API Token'), findsOneWidget);
      expect(find.text('API 安全访问'), findsOneWidget);
      expect(find.text('显示策略 · 隐藏'), findsOneWidget);
      expect(find.text('列表保护 · 仅前缀'), findsOneWidget);
      expect(find.text('失效控制 · 可撤销'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('api-token-channel-console')),
        findsOneWidget,
      );
      expect(find.text('接口通道控制台'), findsOneWidget);
      expect(find.text('移动端'), findsOneWidget);
      expect(find.text('OpenAPI'), findsOneWidget);
      expect(find.text('AI/自动化'), findsOneWidget);
      expect(find.text('脚本隔离'), findsOneWidget);
      expect(find.text('完整 Token 不进入列表，仅保留前缀和撤销入口'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('api-token-exposure-radar')),
        findsOneWidget,
      );
      expect(find.text('授权暴露面雷达'), findsOneWidget);
      expect(find.text('永久凭证'), findsOneWidget);
      expect(find.text('未使用'), findsWidgets);
      expect(find.text('限期凭证'), findsOneWidget);
      expect(find.text('可撤销'), findsOneWidget);
      expect(find.text('完整密钥不落入列表，建议定期清理永久凭证'), findsOneWidget);
      expect(find.text('1 个访问凭证正在管理中'), findsOneWidget);
      expect(find.text('我的手机'), findsOneWidget);
      expect(find.textContaining('abcd1234...'), findsOneWidget);
      expect(find.text('abcd1234... · 未使用 · 永不过期'), findsOneWidget);
    });

    testWidgets('创建令牌后显示完整 token 且刷新列表', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      await tester.enterText(
        find.byKey(const ValueKey('api-token-name')),
        'iPhone',
      );
      await tester.tap(find.text('创建令牌'));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.name, 'iPhone');
      expect(repository.createCalls.single.expiresInDays, 0);
      expect(
        find.byKey(const ValueKey('api-token-created-value')),
        findsOneWidget,
      );
      expect(find.text('full-token-value'), findsOneWidget);
      expect(find.text('iPhone'), findsOneWidget);
      expect(find.text('待保存'), findsWidgets);
      expect(find.text('完整 Token 正在等待复制保存'), findsOneWidget);
      final successSurface = tester.widget<PremiumSurface>(
        find
            .ancestor(
              of: find.text('令牌创建成功'),
              matching: find.byType(PremiumSurface),
            )
            .first,
      );
      final successBadge = tester.widget<IconBadge>(
        find
            .ancestor(
              of: find.byIcon(Icons.check_circle_outline),
              matching: find.byType(IconBadge),
            )
            .first,
      );
      expect(successSurface.accentColor, AppThemePalette.graphite.incomeColor);
      expect(successBadge.color, AppThemePalette.graphite.incomeColor);
    });

    testWidgets('创建令牌时会提交选择的有效期', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('api-token-name')),
        '自动化脚本',
      );
      await tester.tap(find.text('永不过期').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('90 天').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建令牌'));
      await tester.pumpAndSettle();

      expect(repository.createCalls.single.name, '自动化脚本');
      expect(repository.createCalls.single.expiresInDays, 90);
      expect(find.text('ffff0000... · 未使用 · 2026-07-31 过期'), findsOneWidget);
    });

    testWidgets('删除令牌前需要确认', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('删除令牌'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, [1]);
      expect(find.text('我的手机'), findsNothing);
    });

    testWidgets('没有令牌时展示空状态', (tester) async {
      final repository = _FakeApiTokenRepository(tokens: const []);
      await _pumpPage(tester, repository);

      expect(find.text('暂无令牌'), findsOneWidget);
      expect(find.text('创建令牌后可用于 App 或 API 访问。'), findsOneWidget);
    });

    testWidgets('初始加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeApiTokenRepository(failingListRequests: 1);
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('令牌加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('我的手机'), findsOneWidget);
      expect(repository.listCalls, 2);
    });

    testWidgets('API Token 页使用分段入场动效组织控制台区域', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(4));
      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(3));
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeApiTokenRepository repository, {
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiTokenRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: const ApiTokenPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeApiTokenRepository implements ApiTokenRepository {
  _FakeApiTokenRepository({
    List<ApiTokenItem>? tokens,
    this.failingListRequests = 0,
  }) : tokens = tokens ?? [_token()];

  var tokens = <ApiTokenItem>[];
  var failingListRequests = 0;
  var listCalls = 0;

  final List<ApiTokenCreateRequest> createCalls = [];
  final List<int> deleteCalls = [];

  @override
  Future<ApiTokenCreateResult> create(ApiTokenCreateRequest request) async {
    createCalls.add(request);
    final result = ApiTokenCreateResult(
      id: 2,
      name: request.name,
      token: 'full-token-value',
      tokenPrefix: 'ffff0000',
      createdAt: DateTime(2026, 5, 2, 9),
      expiresAt: request.expiresInDays == 0
          ? null
          : DateTime(2026, 5, 2).add(Duration(days: request.expiresInDays)),
    );
    tokens = [result, ...tokens];
    return result;
  }

  @override
  Future<void> delete(int id) async {
    deleteCalls.add(id);
    tokens = tokens.where((token) => token.id != id).toList();
  }

  @override
  Future<List<ApiTokenItem>> list() async {
    listCalls += 1;
    if (failingListRequests > 0) {
      failingListRequests -= 1;
      throw StateError('令牌加载失败');
    }
    return tokens;
  }
}

ApiTokenItem _token() {
  return ApiTokenItem(
    id: 1,
    name: '我的手机',
    tokenPrefix: 'abcd1234',
    createdAt: DateTime(2026, 5, 1, 9),
  );
}
