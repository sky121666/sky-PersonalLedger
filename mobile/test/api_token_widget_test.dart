import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/api_tokens/data/api_token_repository.dart';
import 'package:personal_ledger/features/api_tokens/presentation/api_token_page.dart';

void main() {
  group('ApiTokenPage', () {
    testWidgets('展示设备授权列表和有效期状态', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      expect(find.text('设备授权'), findsOneWidget);
      expect(find.text('访问令牌'), findsNothing);
      expect(find.text('授权设备'), findsOneWidget);
      expect(find.text('API 安全访问'), findsNothing);
      expect(find.text('完整令牌只会在创建成功后显示一次，请立即保存。'), findsNothing);
      expect(
        find.byKey(const ValueKey('api-token-channel-console')),
        findsNothing,
      );
      expect(find.text('接口通道控制台'), findsNothing);
      expect(find.text('AI/自动化'), findsNothing);
      expect(find.text('脚本隔离'), findsNothing);
      expect(
        find.byKey(const ValueKey('api-token-exposure-radar')),
        findsNothing,
      );
      expect(find.text('授权暴露面雷达'), findsNothing);
      expect(find.text('未使用'), findsNothing);
      expect(find.text('完整密钥不落入列表，建议定期清理永久凭证'), findsNothing);
      expect(
        find.byKey(const ValueKey('api-token-governance-rail')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('api-token-issuance-preview')),
        findsNothing,
      );
      expect(find.text('令牌发行策略'), findsNothing);
      expect(find.text('有效期'), findsNothing);
      expect(find.text('1 个可用'), findsOneWidget);
      expect(find.text('我的手机'), findsOneWidget);
      expect(find.text('前缀 abcd1234...'), findsNothing);
      expect(find.text('abcd1234... · 未使用 · 永不过期'), findsNothing);
      expect(find.text('未启用 · 持续有效'), findsOneWidget);
      expect(find.text('未连接 · 长期可用'), findsNothing);
      expect(find.text('未使用 · 永不过期'), findsNothing);
      expect(find.text('永不过期'), findsNothing);
    });

    testWidgets('生成授权后显示一次性授权码且刷新列表', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      await tester.tap(find.byKey(const ValueKey('api-token-add')));
      await tester.pumpAndSettle();
      expect(find.text('新增设备授权'), findsOneWidget);
      expect(find.text('设备名称'), findsOneWidget);
      expect(find.text('创建新令牌'), findsNothing);
      expect(find.text('令牌名称'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('api-token-name')),
        'iPhone',
      );
      await tester.tap(find.text('生成授权'));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.name, 'iPhone');
      expect(repository.createCalls.single.expiresInDays, 0);
      expect(
        find.byKey(const ValueKey('api-token-created-value')),
        findsOneWidget,
      );
      expect(find.text('full-token-value'), findsOneWidget);
      expect(find.text('复制加入码'), findsOneWidget);
      expect(find.text('复制连接码'), findsNothing);
      expect(find.text('复制授权码'), findsNothing);
      expect(find.text('iPhone'), findsOneWidget);
      expect(find.text('待保存'), findsNothing);
      expect(find.text('完整 Token 正在等待复制保存'), findsNothing);
      expect(find.text('一次性密钥保险箱'), findsNothing);
      expect(find.text('仅本次可见'), findsNothing);
      expect(find.text('授权已生成'), findsNothing);
      final successSurface = tester.widget<PremiumSurface>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('api-token-created-value')),
              matching: find.byType(PremiumSurface),
            )
            .first,
      );
      final successBadge = tester.widget<IconBadge>(
        find.byKey(const ValueKey('api-token-created-success-icon')),
      );
      expect(successSurface.accentColor, AppThemePalette.graphite.incomeColor);
      expect(successBadge.color, AppThemePalette.graphite.incomeColor);
    });

    testWidgets('生成授权时会提交选择的有效期', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const ValueKey('api-token-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('api-token-name')),
        '自动化脚本',
      );
      await tester.tap(find.text('持续有效').last);
      await tester.pumpAndSettle();
      expect(find.text('永不过期'), findsNothing);
      await tester.tap(find.text('90 天').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成授权'));
      await tester.pumpAndSettle();

      expect(repository.createCalls.single.name, '自动化脚本');
      expect(repository.createCalls.single.expiresInDays, 90);
      expect(find.text('ffff0000... · 未使用 · 2026-07-31 过期'), findsNothing);
      expect(find.text('未启用 · 有效至 2026-07-31'), findsOneWidget);
      expect(find.text('未连接 · 有效至 2026-07-31'), findsNothing);
      expect(find.text('未使用 · 2026-07-31 过期'), findsNothing);
    });

    testWidgets('删除授权前需要确认', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const ValueKey('api-token-delete-1')));
      await tester.pumpAndSettle();
      expect(find.text('删除「我的手机」？'), findsOneWidget);
      expect(find.text('该设备将无法使用。'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, [1]);
      expect(find.text('我的手机'), findsNothing);
    });

    testWidgets('没有设备授权时展示空状态', (tester) async {
      final repository = _FakeApiTokenRepository(tokens: const []);
      await _pumpPage(tester, repository);

      expect(find.text('还没有授权'), findsOneWidget);
      expect(find.text('还没有授权设备'), findsNothing);
      expect(find.text('右上角添加'), findsOneWidget);
      expect(find.text('暂无令牌'), findsNothing);
      expect(find.text('暂无数据'), findsNothing);
      expect(find.text('未启用'), findsNothing);
    });

    testWidgets('初始加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeApiTokenRepository(failingListRequests: 1);
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('授权加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('我的手机'), findsOneWidget);
      expect(repository.listCalls, 2);
    });

    testWidgets('API Token 页使用高级表面和清晰授权层级', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      expect(find.text('设备授权'), findsOneWidget);
      expect(find.byKey(const ValueKey('api-token-add')), findsOneWidget);
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
      throw StateError('授权加载失败');
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
