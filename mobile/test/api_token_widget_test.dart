import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/api_tokens/data/api_token_repository.dart';
import 'package:personal_ledger/features/api_tokens/presentation/api_token_page.dart';

void main() {
  group('ApiTokenPage', () {
    testWidgets('展示令牌列表和有效期状态', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

      expect(find.text('API Token'), findsOneWidget);
      expect(find.text('我的手机'), findsOneWidget);
      expect(find.textContaining('abcd1234...'), findsOneWidget);
      expect(find.text('abcd1234... · 未使用 · 永不过期'), findsOneWidget);
    });

    testWidgets('创建令牌后显示完整 token 且刷新列表', (tester) async {
      final repository = _FakeApiTokenRepository();
      await _pumpPage(tester, repository);

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
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeApiTokenRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiTokenRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: ApiTokenPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeApiTokenRepository implements ApiTokenRepository {
  var tokens = <ApiTokenItem>[
    ApiTokenItem(
      id: 1,
      name: '我的手机',
      tokenPrefix: 'abcd1234',
      createdAt: DateTime(2026, 5, 1, 9),
    ),
  ];

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
    return tokens;
  }
}
