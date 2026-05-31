import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/app/widgets/finance_dashboard_widgets.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/accounts/presentation/accounts_page.dart';

void main() {
  group('AccountsPage', () {
    test('解析后端账户负债字段', () {
      final account = Account.fromJson({
        'id': 'mortgage',
        'name': '住房贷款',
        'type': 'mortgage',
        'icon': 'home',
        'color': '#EF4444',
        'initial_balance': 500000,
        'current_balance': 480000,
        'payment_day': 20,
        'billing_day': 1,
        'credit_limit': '800000',
        'interest_rate': 3.25,
        'total_paid': 20000,
        'start_date': '2026-01-01T00:00:00Z',
        'target_date': '2056-01-01T00:00:00Z',
        'remark': '首套房商贷',
        'is_archived': false,
        'sort_order': 2,
      });

      expect(account.paymentDay, 20);
      expect(account.billingDay, 1);
      expect(account.creditLimit, 800000);
      expect(account.interestRate, 3.25);
      expect(account.totalPaid, 20000);
      expect(account.startDate, '2026-01-01');
      expect(account.targetDate, '2056-01-01');
      expect(account.remark, '首套房商贷');
    });

    testWidgets('展示完整账户类型标签', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      expect(find.text('银行卡'), findsOneWidget);
      expect(find.text('房贷'), findsOneWidget);
      expect(find.text('Apple Pay'), findsOneWidget);
    });

    testWidgets('账户概览和账户卡片使用分段入场动效', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      expect(find.text('负债承压'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('account-portfolio-control-strip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('account-portfolio-matrix-panel')),
        findsOneWidget,
      );
      expect(find.text('资产控制中枢'), findsOneWidget);
      expect(find.text('静谧墨绿'), findsOneWidget);
      expect(find.text('活跃 3 个'), findsOneWidget);
      expect(find.text('无归档'), findsOneWidget);
      expect(find.text('流动账户'), findsOneWidget);
      expect(find.text('负债暴露'), findsOneWidget);
      expect(find.text('资产路径'), findsOneWidget);
      expect(find.text('账户资产矩阵'), findsOneWidget);
      expect(find.text('流动优先'), findsOneWidget);
      expect(find.text('资产池'), findsOneWidget);
      expect(find.text('负债池'), findsOneWidget);
      expect(find.text('主资产账户'), findsOneWidget);
      expect(find.text('手机钱包'), findsOneWidget);
      expect(find.text('主要负债'), findsOneWidget);
      expect(find.text('账户覆盖'), findsOneWidget);
      expect(find.text('3 个活跃'), findsOneWidget);
      expect(find.text('2 资产 / 1 负债'), findsOneWidget);
      expect(find.text('结构比例'), findsOneWidget);
      expect(find.text('资产占比'), findsOneWidget);
      expect(find.text('负债占比'), findsOneWidget);
      expect(find.text('资产账户'), findsOneWidget);
      expect(find.text('负债账户'), findsOneWidget);
      expect(find.text('2 个'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('account-card-bank-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('account-balance-bank-card')),
        findsOneWidget,
      );
      expect(find.text('当前余额'), findsAtLeastNWidgets(1));
      expect(find.text('剩余负债'), findsOneWidget);
      expect(find.text('资产轨道'), findsAtLeastNWidgets(1));
      expect(find.text('偿还进度'), findsOneWidget);
      expect(find.text('期初对比'), findsAtLeastNWidgets(1));
      expect(find.text('支持排序'), findsOneWidget);
      expect(find.text('资产类'), findsAtLeastNWidgets(1));
      expect(find.text('负债类'), findsOneWidget);
      expect(find.text('正常'), findsAtLeastNWidgets(1));
      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(5));
    });

    testWidgets('账户表单使用高级分区和可视化标识选择', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增账户'));
      await tester.pumpAndSettle();

      expect(find.text('创建可用于记账和资产统计的账户'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('视觉标识'), findsOneWidget);
      expect(find.text('卡片'), findsOneWidget);
      expect(find.byType(IconBadge), findsWidgets);
      expect(find.byType(PremiumSurface), findsWidgets);
    });

    testWidgets('新增负债账户时提交负债字段', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增账户'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('account-name')), '房贷');
      await tester.tap(find.byKey(const ValueKey('account-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('房贷').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-initial-balance')),
        '500000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-payment-day')),
        '20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-billing-day')),
        '1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-credit-limit')),
        '800000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-interest-rate')),
        '3.25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-start-date')),
        '2026-01-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-target-date')),
        '2056-01-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('account-remark')),
        '首套房商贷',
      );
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      final payload = repository.createCalls.single.toJson();
      expect(payload['type'], 'mortgage');
      expect(payload['initial_balance'], 500000);
      expect(payload['payment_day'], 20);
      expect(payload['billing_day'], 1);
      expect(payload['credit_limit'], 800000);
      expect(payload['interest_rate'], 3.25);
      expect(payload['start_date'], '2026-01-01');
      expect(payload['target_date'], '2056-01-01');
      expect(payload['remark'], '首套房商贷');
      expect(find.text('保存成功'), findsOneWidget);
    });

    testWidgets('编辑负债账户时保留负债字段', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-name')),
        '自住房贷款',
      );
      await tester.tap(find.byKey(const ValueKey('account-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'mortgage');
      final payload = repository.updateCalls.single.$2.toJson();
      expect(payload['name'], '自住房贷款');
      expect(payload['payment_day'], 20);
      expect(payload['billing_day'], 1);
      expect(payload['credit_limit'], 800000);
      expect(payload['interest_rate'], 3.25);
      expect(payload['start_date'], '2026-01-01');
      expect(payload['target_date'], '2056-01-01');
      expect(payload['remark'], '首套房商贷');
    });

    testWidgets('账户菜单可以调整正常账户排序', (tester) async {
      final repository = _FakeAccountRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上移'));
      await tester.pumpAndSettle();

      expect(repository.sortCalls, [
        ['mortgage', 'bank-card', 'apple-pay'],
      ]);
      expect(find.text('账户排序已更新'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeAccountRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repository),
        themeControllerProvider.overrideWith(
          (ref) => _FixedThemeController(AppThemePalette.teal),
        ),
      ],
      child: const MaterialApp(home: AccountsPage()),
    ),
  );
  await tester.pumpAndSettle();
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

class _FakeAccountRepository implements AccountRepository {
  var accounts = <Account>[
    const Account(
      id: 'bank-card',
      name: '招商银行',
      type: 'bank_card',
      icon: '💳',
      color: '#3B82F6',
      initialBalance: 1000,
      currentBalance: 1200,
      isArchived: false,
      sortOrder: 1,
    ),
    const Account(
      id: 'mortgage',
      name: '住房贷款',
      type: 'mortgage',
      icon: '🏠',
      color: '#EF4444',
      initialBalance: 500000,
      currentBalance: 480000,
      paymentDay: 20,
      billingDay: 1,
      creditLimit: 800000,
      interestRate: 3.25,
      startDate: '2026-01-01',
      targetDate: '2056-01-01',
      remark: '首套房商贷',
      isArchived: false,
      sortOrder: 2,
    ),
    const Account(
      id: 'apple-pay',
      name: '手机钱包',
      type: 'apple_pay',
      icon: '📱',
      color: '#111827',
      initialBalance: 0,
      currentBalance: 300,
      isArchived: false,
      sortOrder: 3,
    ),
  ];

  final List<CreateAccountRequest> createCalls = [];
  final List<(String, UpdateAccountRequest)> updateCalls = [];
  final List<String> deleteCalls = [];
  final List<(String, bool)> archiveCalls = [];
  final List<List<String>> sortCalls = [];

  @override
  Future<void> archive(String id, bool isArchived) async {
    archiveCalls.add((id, isArchived));
    accounts = [
      for (final account in accounts)
        if (account.id == id)
          Account(
            id: account.id,
            name: account.name,
            type: account.type,
            icon: account.icon,
            color: account.color,
            initialBalance: account.initialBalance,
            currentBalance: account.currentBalance,
            paymentDay: account.paymentDay,
            billingDay: account.billingDay,
            creditLimit: account.creditLimit,
            interestRate: account.interestRate,
            totalPaid: account.totalPaid,
            startDate: account.startDate,
            targetDate: account.targetDate,
            paidOffAt: account.paidOffAt,
            remark: account.remark,
            isArchived: isArchived,
            sortOrder: account.sortOrder,
          )
        else
          account,
    ];
  }

  @override
  Future<Account> create(CreateAccountRequest request) async {
    createCalls.add(request);
    final account = Account(
      id: 'account-${accounts.length + 1}',
      name: request.name,
      type: request.type,
      icon: request.icon,
      color: request.color,
      initialBalance: request.initialBalance,
      currentBalance: request.initialBalance,
      isArchived: false,
      sortOrder: accounts.length + 1,
    );
    accounts = [...accounts, account];
    return account;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    accounts = accounts.where((account) => account.id != id).toList();
  }

  @override
  Future<Account> getById(String id) async {
    return accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<AccountListResult> list({bool includeArchived = true}) async {
    return AccountListResult(
      accounts: includeArchived
          ? accounts
          : accounts.where((account) => !account.isArchived).toList(),
      totalAssets: 1500,
      totalLiabilities: 480000,
      netAssets: -478500,
    );
  }

  @override
  Future<Account> update(String id, UpdateAccountRequest request) async {
    updateCalls.add((id, request));
    return accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<void> updateSort(List<String> ids) async {
    sortCalls.add(ids);
    final order = {for (final entry in ids.indexed) entry.$2: entry.$1};
    accounts = [
      ...accounts.where((account) => order.containsKey(account.id)).toList()
        ..sort((a, b) => order[a.id]!.compareTo(order[b.id]!)),
      ...accounts.where((account) => !order.containsKey(account.id)),
    ];
  }
}
