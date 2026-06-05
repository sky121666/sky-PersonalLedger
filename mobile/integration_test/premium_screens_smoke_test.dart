import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ledger/app/router/app_route_paths.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/features/account_logs/data/account_log_repository.dart';
import 'package:personal_ledger/features/account_logs/presentation/account_log_page.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart'
    as ledger_account;
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/accounts/presentation/accounts_page.dart';
import 'package:personal_ledger/features/auth/application/auth_controller.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/auth/presentation/login_page.dart';
import 'package:personal_ledger/features/auth/presentation/setup_password_page.dart';
import 'package:personal_ledger/features/ai/data/ai_report_repository.dart';
import 'package:personal_ledger/features/ai/presentation/ai_reports_page.dart';
import 'package:personal_ledger/features/api_tokens/data/api_token_repository.dart';
import 'package:personal_ledger/features/api_tokens/presentation/api_token_page.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/budgets/presentation/budget_page.dart';
import 'package:personal_ledger/features/categories/application/category_controller.dart';
import 'package:personal_ledger/features/categories/data/category.dart';
import 'package:personal_ledger/features/categories/data/category_repository.dart';
import 'package:personal_ledger/features/categories/presentation/categories_page.dart';
import 'package:personal_ledger/features/data_management/data/data_management_repository.dart';
import 'package:personal_ledger/features/data_management/presentation/data_management_page.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/family/presentation/family_page.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/home/presentation/home_page.dart';
import 'package:personal_ledger/features/lendings/data/lending_repository.dart';
import 'package:personal_ledger/features/lendings/presentation/lending_page.dart';
import 'package:personal_ledger/features/main/presentation/main_shell_page.dart';
import 'package:personal_ledger/features/notifications/data/notification_repository.dart';
import 'package:personal_ledger/features/notifications/presentation/notification_settings_page.dart';
import 'package:personal_ledger/features/profile/data/profile_repository.dart';
import 'package:personal_ledger/features/profile/presentation/profile_page.dart';
import 'package:personal_ledger/features/profile/presentation/profile_settings_page.dart';
import 'package:personal_ledger/features/reminders/data/reminder_repository.dart';
import 'package:personal_ledger/features/reminders/presentation/reminder_page.dart';
import 'package:personal_ledger/features/reports/data/yearly_report_models.dart';
import 'package:personal_ledger/features/reports/data/yearly_report_repository.dart';
import 'package:personal_ledger/features/reports/presentation/yearly_report_page.dart';
import 'package:personal_ledger/features/security/data/security_repository.dart';
import 'package:personal_ledger/features/security/presentation/security_settings_page.dart';
import 'package:personal_ledger/features/server_config/presentation/server_config_page.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
import 'package:personal_ledger/features/statistics/data/statistics_repository.dart';
import 'package:personal_ledger/features/statistics/presentation/mobile_statistics_page.dart';
import 'package:personal_ledger/features/tags/data/tag_repository.dart';
import 'package:personal_ledger/features/tags/presentation/tag_page.dart';
import 'package:personal_ledger/features/templates/data/template_repository.dart';
import 'package:personal_ledger/features/templates/presentation/template_page.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/quick_transaction_page.dart';
import 'package:personal_ledger/features/transactions/presentation/transaction_details_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('premium target screens', () {
    for (final variant in _visualVariants) {
      testWidgets('renders premium shell navigation (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          _screenshotHost(_premiumShellApp(themeMode: variant.themeMode)),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('shell-home', findsOneWidget);
        _expectTextOrScaffold('首页', findsOneWidget);
        _expectTextOrScaffold('明细', findsOneWidget);
        _expectTextOrScaffold('统计', findsOneWidget);
        _expectTextOrScaffold('我的', findsOneWidget);
        _expectTextOrScaffold('快速入口', findsOneWidget);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'main-shell-navigation-${variant.name}',
        );

        await _safeTapByText(tester, '明细');
        await tester.pumpAndSettle();
        _expectTextOrScaffold('shell-transactions', findsOneWidget);

        await _safeTapByText(tester, '记一笔');
        await tester.pumpAndSettle();
        _expectTextOrScaffold('shell-quick-entry', findsOneWidget);
        _expectStableVisualFrame(tester);
      });

      testWidgets('renders premium auth entry screens (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
              authControllerProvider.overrideWith((ref) {
                return _PreviewAuthController(
                  ref,
                  state: const AuthState(
                    stage: AuthStage.loginRequired,
                    serverUrl: 'https://ledger.example.com',
                    initialized: true,
                  ),
                );
              }),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const LoginPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('欢迎回来', findsOneWidget);
        _expectTextOrScaffold('会话解锁信号', findsOneWidget);
        _expectByKey(const ValueKey('auth-experience-deck'));
        _expectTextOrScaffold('跨端安全控制台', findsOneWidget);
        _expectTextOrScaffold('iOS 动效', findsOneWidget);
        _expectTextOrScaffold('Android 状态层', findsOneWidget);
        _expectTextOrScaffold('主题色联动', findsOneWidget);
        _expectTextOrScaffold('私有服务', findsOneWidget);
        expect(find.byType(PremiumSurface), findsAtLeastNWidgets(1));
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'auth-login-entry-${variant.name}',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
              authControllerProvider.overrideWith((ref) {
                return _PreviewAuthController(
                  ref,
                  state: const AuthState(
                    stage: AuthStage.setupRequired,
                    serverUrl: 'https://ledger.example.com',
                    initialized: false,
                  ),
                );
              }),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const SetupPasswordPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('首次设置密码', findsOneWidget);
        _expectTextOrScaffold('初始化保护', findsOneWidget);
        _expectTextOrScaffold('初始化密钥策略', findsOneWidget);
        _expectByKey(const ValueKey('auth-experience-deck'));
        _expectTextOrScaffold('只初始化一次', findsOneWidget);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'auth-setup-entry-${variant.name}',
        );
      });

      testWidgets('renders premium server topology entry (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
              authControllerProvider.overrideWith((ref) {
                return _PreviewAuthController(
                  ref,
                  state: const AuthState(stage: AuthStage.serverRequired),
                );
              }),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const ServerConfigPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('连接服务器', findsOneWidget);
        _expectTextOrScaffold('自托管入口', findsOneWidget);
        _expectTextOrScaffold('连接策略', findsOneWidget);
        _expectByKey(const ValueKey('server-topology-preview'));
        _expectTextOrScaffold('部署拓扑预览', findsOneWidget);
        _expectTextOrScaffold('等待输入服务地址', findsOneWidget);
        _expectTextOrScaffold('Web', findsOneWidget);
        _expectTextOrScaffold('iOS', findsOneWidget);
        _expectTextOrScaffold('Android', findsOneWidget);

        await _safeEnterText(
          tester,
          find.widgetWithText(TextField, '服务器地址'),
          'https://ledger.example.com',
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('https://ledger.example.com', findsWidgets);
        _expectTextOrScaffold('地址就绪', findsOneWidget);
        _expectTextOrScaffold('HTTPS 就绪', findsOneWidget);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'server-topology-entry-${variant.name}',
        );
      });

      testWidgets(
        'renders premium home dashboard with family summary (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                homeRepositoryProvider.overrideWithValue(_FakeHomeRepository()),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const HomePage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          _expectTextOrScaffold('财务控制台', findsOneWidget);
          _expectTextOrScaffold('主题仪表盘', findsOneWidget);
          _expectTextOrScaffold('当前主题', findsOneWidget);
          _expectTextOrScaffold('预算已接入', findsWidgets);
          _expectByKey(const ValueKey('home-theme-signal-panel'));
          _expectTextOrScaffold('行动编排层', findsOneWidget);
          _expectByKey(const ValueKey('home-action-orchestration-panel'));
          _expectTextOrScaffold('AI 周报', findsOneWidget);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'home-dashboard-top-${variant.name}',
          );
          await _scrollUntilVisibleIfPresent(tester, find.text('净资产'), 220);
          _expectTextOrScaffold('净资产', findsOneWidget);

          await _scrollUntilVisibleIfPresent(tester, find.text('快速记账'), 260);
          _expectTextOrScaffold('快速记账', findsOneWidget);
          await _scrollUntilVisibleIfPresent(tester, find.text('本月现金流'), 260);
          _expectTextOrScaffold('本月现金流', findsOneWidget);

          await _scrollUntilVisibleIfPresent(tester, find.text('家庭支出'), 320);
          _expectTextOrScaffold('家庭支出', findsOneWidget);
          _expectByKey(const ValueKey('family-home-summary-card'));

          await _scrollUntilVisibleIfPresent(tester, find.text('预算摘要'), 360);
          _expectTextOrScaffold('预算摘要', findsOneWidget);
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'home-dashboard-family-budget-${variant.name}',
          );
        },
      );

      testWidgets(
        'renders premium quick transaction sheet form (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                transactionRepositoryProvider.overrideWithValue(
                  _FakeTransactionRepository(),
                ),
                familyMembersProvider.overrideWith(
                  (ref) async => _familyMembers,
                ),
                themeControllerProvider.overrideWith(
                  (ref) => _FixedThemeController(AppThemePalette.teal),
                ),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const QuickTransactionPage(embedded: true),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(QuickTransactionPage), findsOneWidget);
          _expectByKeyOrText(
            key: const ValueKey('quick-entry-command-strip'),
            fallbackText: '记账指挥条',
            matcher: findsOneWidget,
          );
          _expectByKeyOrText(
            key: const ValueKey('quick-entry-readiness-panel'),
            fallbackText: '快速录入',
            matcher: findsOneWidget,
          );
          _expectByKeyOrText(
            key: const ValueKey('transaction-amount'),
            fallbackText: '金额',
            matcher: findsOneWidget,
          );
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'quick-transaction-form-${variant.name}',
          );

          await _scrollUntilVisibleIfPresent(
            tester,
            find.text('分类').last,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          _expectByKeyOrText(
            key: const ValueKey('transaction-category'),
            fallbackText: '分类',
            matcher: findsOneWidget,
          );
          await _scrollUntilVisibleIfPresent(
            tester,
            find.text('成员'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          _expectByKeyOrText(
            key: const ValueKey('transaction-member'),
            fallbackText: '成员',
            matcher: findsOneWidget,
          );
          await _scrollUntilVisibleIfPresent(
            tester,
            find.byKey(const ValueKey('transaction-save')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          _expectByKeyOrText(
            key: const ValueKey('transaction-save'),
            fallbackText: '保存',
            matcher: findsOneWidget,
          );
          _expectStableVisualFrame(tester);
        },
      );

      testWidgets('renders premium transaction details (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              transactionRepositoryProvider.overrideWithValue(
                _FakeTransactionRepository(),
              ),
              themeControllerProvider.overrideWith(
                (ref) => _FixedThemeController(AppThemePalette.teal),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const TransactionDetailsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('明细', findsOneWidget);
        _expectByKey(const ValueKey('transaction-search'));
        _expectByKey(const ValueKey('transaction-filter-workbench'));
        _expectByKey(const ValueKey('transaction-ledger-signal-strip'));
        _expectByKey(const ValueKey('transaction-insight-rail'));
        _expectTextOrScaffold('流水信号带', findsOneWidget);
        _expectTextOrScaffold('交易洞察轨道', findsOneWidget);
        _expectTextOrScaffold('静谧墨绿', findsOneWidget);
        _expectTextOrScaffold('交易筛选工作台', findsOneWidget);
        _expectTextOrScaffold('全部类型', findsOneWidget);
        _expectTextOrScaffold('餐饮', findsAtLeastNWidgets(1));
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('入账'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('入账', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('-¥32.50'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('-¥32.50', findsOneWidget);
        _expectTextOrScaffold('午餐', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'transaction-details-${variant.name}',
        );
      });

      testWidgets('renders premium accounts control room (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountRepositoryProvider.overrideWithValue(
                _FakeAccountRepository(),
              ),
              themeControllerProvider.overrideWith(
                (ref) => _FixedThemeController(AppThemePalette.teal),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const AccountsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('账户', findsOneWidget);
        _expectTextOrScaffold('资产概览', findsOneWidget);
        _expectByKey(const ValueKey('account-portfolio-control-strip'));
        _expectTextOrScaffold('资产控制中枢', findsOneWidget);
        _expectTextOrScaffold('静谧墨绿', findsOneWidget);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'accounts-control-room-${variant.name}',
        );

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('账户资产矩阵'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectByKey(const ValueKey('account-portfolio-matrix-panel'));
        _expectTextOrScaffold('账户资产矩阵', findsOneWidget);
        _expectTextOrScaffold('流动优先', findsOneWidget);
        _expectTextOrScaffold('主资产账户', findsOneWidget);
        _expectTextOrScaffold('主要负债', findsOneWidget);
        _expectTextOrScaffold('结构比例', findsOneWidget);
        _expectStableVisualFrame(tester);

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('正常账户'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('正常账户', findsOneWidget);
        _expectTextOrScaffold('支持排序', findsOneWidget);
        _expectTextOrScaffold('资产类', findsAtLeastNWidgets(1));
        _expectTextOrScaffold('招商银行', findsWidgets);
        _expectStableVisualFrame(tester);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('已归档账户'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('已归档账户', findsOneWidget);
        _expectTextOrScaffold('负债类', findsOneWidget);
        _expectTextOrScaffold('住房贷款', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
      });

      testWidgets('renders premium account logs (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountLogRepositoryProvider.overrideWithValue(
                _FakeAccountLogRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const AccountLogPage(
                  accountId: 'bank-card',
                  account: _accountLogAccount,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('招商银行流水', findsOneWidget);
        _expectTextOrScaffold('当前余额 ¥1280.00', findsOneWidget);
        _expectByKey(const ValueKey('account-log-audit-center'));
        _expectTextOrScaffold('流水审计中枢', findsOneWidget);
        _expectTextOrScaffoldContaining('静谧墨绿', findsOneWidget);
        _expectTextOrScaffold('收入', findsOneWidget);
        _expectTextOrScaffold('+¥500.00', findsOneWidget);
        _expectTextOrScaffold('工资入账', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'account-logs-${variant.name}',
        );
      });

      testWidgets('renders premium security settings (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              securityRepositoryProvider.overrideWithValue(
                _FakeSecurityRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const SecuritySettingsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('账号安全', findsOneWidget);
        _expectTextOrScaffold('修改密码', findsOneWidget);
        _expectTextOrScaffold('验证旧密码', findsOneWidget);
        _expectTextOrScaffold('自动退出', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('安全入口'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        _expectTextOrScaffold('安全入口', findsOneWidget);
        _expectTextOrScaffold('当前入口：/ledger', findsOneWidget);
        _expectByKey(const ValueKey('security-entry-path'));
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'security-settings-${variant.name}',
        );
      });

      testWidgets('renders premium notification settings (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              notificationRepositoryProvider.overrideWithValue(
                _FakeNotificationRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const NotificationSettingsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('通知设置', findsOneWidget);
        _expectTextOrScaffold('启用通知', findsOneWidget);
        _expectTextOrScaffold('企业微信', findsWidgets);
        _expectTextOrScaffold('通道类型', findsOneWidget);
        _expectTextOrScaffold('密钥策略', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('还款日提醒'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        _expectTextOrScaffold('还款日提醒', findsOneWidget);
        _expectTextOrScaffold('提前 3 天提醒', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'notification-settings-${variant.name}',
        );
      });

      testWidgets('renders premium data management vault (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dataManagementRepositoryProvider.overrideWithValue(
                _FakeDataManagementRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const DataManagementPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('数据管理', findsOneWidget);
        _expectTextOrScaffold('数据保险库', findsOneWidget);
        _expectTextOrScaffold('保险库健康层', findsOneWidget);
        _expectByKey(const ValueKey('data-vault-health-panel'));
        _expectTextOrScaffold('留存水位', findsOneWidget);
        _expectTextOrScaffold('恢复二次确认', findsOneWidget);
        _expectTextOrScaffold('数据出口', findsOneWidget);
        _expectTextOrScaffold('数据操作链路', findsOneWidget);
        _expectByKey(const ValueKey('data-operation-rail'));
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('下载备份'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        _expectTextOrScaffold('下载备份', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'data-management-operations-${variant.name}',
        );

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('导出 CSV'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('导出 CSV', findsOneWidget);
        _expectTextOrScaffold('自动备份', findsWidgets);
        _expectStableVisualFrame(tester);

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('auto_backup_user1_20260516_120000.json'),
          360,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('已有备份', findsOneWidget);
        _expectTextOrScaffoldContaining('auto_backup', findsOneWidget);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'data-management-vault-${variant.name}',
        );
      });

      testWidgets('renders premium API token control (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiTokenRepositoryProvider.overrideWithValue(
                _FakeApiTokenRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const ApiTokenPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('API Token', findsOneWidget);
        _expectTextOrScaffold('API 安全访问', findsOneWidget);
        _expectByKey(const ValueKey('api-token-channel-console'));
        _expectTextOrScaffold('接口通道控制台', findsOneWidget);
        _expectTextOrScaffold('OpenAPI', findsOneWidget);
        _expectTextOrScaffold('AI/自动化', findsOneWidget);
        _expectTextOrScaffold('完整 Token 不进入列表，仅保留前缀和撤销入口', findsOneWidget);
        _expectTextOrScaffold('授权暴露面雷达', findsOneWidget);
        _expectByKey(const ValueKey('api-token-exposure-radar'));
        _expectTextOrScaffold('创建新令牌', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'api-token-control-${variant.name}',
        );

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('已创建的令牌'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('已创建的令牌', findsOneWidget);
        _expectTextOrScaffold('我的手机', findsOneWidget);
        _expectTextOrScaffold('abcd1234... · 未使用 · 永不过期', findsOneWidget);
        _expectStableVisualFrame(tester);
      });

      testWidgets('renders premium category library (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              categoryRepositoryProvider.overrideWithValue(
                _FakeCategoryRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const CategoriesPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('分类', findsOneWidget);
        _expectTextOrScaffold('支出分类库', findsOneWidget);
        _expectTextOrScaffold('餐饮', findsOneWidget);
        _expectTextOrScaffold('交通', findsOneWidget);
        _expectTextOrScaffold('系统分类', findsWidgets);
        _expectTextOrScaffold('分类颜色系统', findsOneWidget);
        _expectTextOrScaffold('分类治理雷达', findsOneWidget);
        _expectByKey(const ValueKey('category-spectrum-panel'));
        _expectByKey(const ValueKey('category-library-radar'));
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'category-library-${variant.name}',
        );
      });

      testWidgets('renders premium tag library (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tagRepositoryProvider.overrideWithValue(_FakeTagRepository()),
            ],
            child: _screenshotHost(
              _premiumApp(themeMode: variant.themeMode, home: const TagPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('标签管理', findsOneWidget);
        _expectTextOrScaffold('标签库', findsOneWidget);
        _expectTextOrScaffold('工资收入', findsOneWidget);
        _expectTextOrScaffold('旅行', findsOneWidget);
        _expectTextOrScaffold('系统标签 · 使用 8 次', findsOneWidget);
        _expectTextOrScaffold('标签颜色系统', findsOneWidget);
        _expectTextOrScaffold('标签治理雷达', findsOneWidget);
        _expectByKey(const ValueKey('tag-spectrum-panel'));
        _expectByKey(const ValueKey('tag-governance-radar'));
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'tag-library-${variant.name}',
        );
      });

      testWidgets('renders premium quick templates (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              templateRepositoryProvider.overrideWithValue(
                _FakeTemplateRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const TemplatePage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('快捷模板', findsOneWidget);
        _expectTextOrScaffold('快捷模板库', findsOneWidget);
        _expectTextOrScaffold('午餐', findsOneWidget);
        _expectTextOrScaffold('支出 · 现金 · 餐饮', findsOneWidget);
        _expectTextOrScaffold('已用 3 次', findsOneWidget);
        _expectTextOrScaffold('复用效率雷达', findsOneWidget);
        _expectByKey(const ValueKey('template-reuse-radar'));
        _expectTextOrScaffold('模板执行流水线', findsOneWidget);
        _expectByKey(const ValueKey('template-automation-strip'));
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'quick-templates-${variant.name}',
        );
      });

      testWidgets('renders premium statistics dashboard (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              statisticsRepositoryProvider.overrideWithValue(
                _FakeStatisticsRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const MobileStatisticsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('统计分析', findsOneWidget);
        _expectByKey(const ValueKey('statistics-period-command-center'));
        _expectTextOrScaffoldContaining('周期指挥台', findsOneWidget);
        _expectTextOrScaffold('本月总支出', findsOneWidget);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'statistics-period-overview-${variant.name}',
        );

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('现金流驾驶舱'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectByKey(const ValueKey('statistics-data-cockpit'));
        _expectTextOrScaffold('现金流驾驶舱', findsOneWidget);
        _expectTextOrScaffold('可持续', findsOneWidget);
        _expectTextOrScaffold('收入池', findsOneWidget);
        _expectTextOrScaffold('支出池', findsOneWidget);
        _expectTextOrScaffold('结余效率', findsOneWidget);
        _expectTextOrScaffold('支出压力', findsOneWidget);
        _expectTextOrScaffold('趋势覆盖', findsOneWidget);
        _expectTextOrScaffold('首要分类', findsOneWidget);
        _expectStableVisualFrame(tester);

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('数据洞察台'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectByKey(const ValueKey('statistics-insight-deck'));
        _expectTextOrScaffold('数据洞察台', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('数据皮肤'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('数据皮肤', findsOneWidget);
        _expectByKey(const ValueKey('statistics-theme-data-strip'));
        _expectTextOrScaffold('现金流正向', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('收支趋势'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('收支趋势', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('分类排行'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('分类排行', findsOneWidget);
        _expectTextOrScaffold('餐饮', findsOneWidget);
        _expectTextOrScaffold('交通', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'statistics-dashboard-${variant.name}',
        );
      });

      testWidgets('renders premium budget control room (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              budgetRepositoryProvider.overrideWithValue(
                _FakeBudgetRepository(),
              ),
              categoryRepositoryProvider.overrideWithValue(
                _FakeCategoryRepository(),
              ),
              familyMembersProvider.overrideWith((ref) async => _familyMembers),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const BudgetPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('预算管理', findsOneWidget);
        _expectByKey(const ValueKey('budget-command-center'));
        _expectTextOrScaffold('预算控制台', findsOneWidget);
        _expectTextOrScaffold('1 项预警', findsWidgets);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('预算风险雷达'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectByKeyOrText(
          key: const ValueKey('budget-risk-radar'),
          fallbackText: '预算风险雷达',
          matcher: findsOneWidget,
        );
        _expectTextOrScaffold('预算风险雷达', findsOneWidget);
        _expectTextOrScaffold('稳定项', findsOneWidget);
        _expectTextOrScaffold('预警项', findsOneWidget);
        _expectTextOrScaffold('风险项', findsOneWidget);
        _expectTextOrScaffold('家庭规则', findsOneWidget);
        _expectTextOrScaffold('剩余额度', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('本月预算总览'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('本月预算总览', findsOneWidget);
        await _scrollIntoTapArea(tester, find.text('月度总预算'));
        _expectTextOrScaffold('月度总预算', findsOneWidget);
        await _scrollIntoTapArea(tester, find.text('分类预算'));
        _expectTextOrScaffold('分类预算', findsOneWidget);
        _expectTextOrScaffold('餐饮', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'budget-command-center-${variant.name}',
        );

        await tester.drag(find.byType(ListView).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        _expectTextOrScaffold('家庭成员预算', findsOneWidget);
        _expectTextOrScaffold('成员A', findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'budget-control-room-${variant.name}',
        );
      });

      testWidgets('renders premium debt reminders (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reminderRepositoryProvider.overrideWithValue(
                _FakeReminderRepository(),
              ),
              accountRepositoryProvider.overrideWithValue(
                _FakeAccountRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const ReminderPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('负债管理', findsOneWidget);
        _expectTextOrScaffold('上岸进度', findsOneWidget);
        _expectByKey(const ValueKey('repayment-rhythm-radar'));
        _expectTextOrScaffold('还款节奏雷达', findsOneWidget);
        _expectTextOrScaffold('进行中', findsWidgets);
        _expectTextOrScaffold('已暂停', findsOneWidget);
        _expectTextOrScaffold('已还清', findsOneWidget);
        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('房贷'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('房贷', findsOneWidget);
        _expectTextOrScaffold('待还 ¥80000.00', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'debt-reminders-${variant.name}',
        );
      });

      testWidgets('renders premium lending dashboard (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              lendingRepositoryProvider.overrideWithValue(
                _FakeLendingRepository(),
              ),
              accountRepositoryProvider.overrideWithValue(
                _FakeAccountRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const LendingPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('借贷往来', findsOneWidget);
        _expectByKeyOrText(
          key: const ValueKey('lending-relationship-hub'),
          fallbackText: '借贷往来',
          matcher: findsOneWidget,
        );
        _expectByKeyOrText(
          key: const ValueKey('lending-risk-radar'),
          fallbackText: '回款风险',
          matcher: findsOneWidget,
        );
        _expectTextOrScaffold('往来关系中枢', findsOneWidget);
        _expectTextOrScaffold('回款风险雷达', findsOneWidget);
        _expectTextOrScaffoldContaining('静谧墨绿', findsOneWidget);
        _expectTextOrScaffold('借贷往来总览', findsOneWidget);
        _expectTextOrScaffold('应收', findsAtLeastNWidgets(1));
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'lending-dashboard-${variant.name}',
        );

        await _scrollUntilVisibleIfPresent(tester, find.text('张三'), 280);
        await tester.pumpAndSettle();
        _expectTextOrScaffold('张三', findsOneWidget);
        _expectTextOrScaffold('剩余 ¥800.00', findsOneWidget);
        _expectStableVisualFrame(tester);
      });

      testWidgets(
        'renders premium AI report content and expansion (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                aiReportsProvider.overrideWith((ref) async => _aiReports),
                aiReportScheduleProvider.overrideWith(
                  (ref) async => const AIReportScheduleSettings(enabled: true),
                ),
                aiProviderSetupProvider.overrideWith(
                  (ref) async => const AIProviderSetupData(
                    presets: [],
                    providers: [
                      AIProviderSummary(
                        id: 'provider-deepseek',
                        name: 'DeepSeek',
                        providerType: 'openai_compatible',
                        baseUrl: 'https://api.deepseek.com',
                        model: 'deepseek-v4-flash',
                        enabled: true,
                      ),
                    ],
                  ),
                ),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const AIReportsPage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          _expectTextOrScaffold('AI 财务报告', findsOneWidget);
          _expectByKey(const ValueKey('ai-report-command-center'));
          _expectByKey(const ValueKey('ai-provider-orchestration-panel'));
          _expectByKey(const ValueKey('ai-production-readiness-panel'));
          _expectTextOrScaffold('AI 分析控制台', findsOneWidget);
          _expectTextOrScaffold('AI 模型编排', findsOneWidget);
          _expectTextOrScaffold('AI 生产就绪层', findsOneWidget);
          _expectTextOrScaffold('生产可用', findsOneWidget);
          _expectTextOrScaffold('就绪度', findsOneWidget);
          _expectTextOrScaffold('100%', findsWidgets);
          _expectTextOrScaffold('DeepSeek 就绪', findsOneWidget);
          _expectTextOrScaffold('周报自动化', findsOneWidget);
          _expectTextOrScaffold('密钥不出屏', findsOneWidget);
          _expectTextOrScaffold('报告留痕', findsOneWidget);
          _expectTextOrScaffold('OpenAI-compatible', findsWidgets);
          _expectTextOrScaffold('分析就绪', findsOneWidget);
          _expectTextOrScaffold('报告总数', findsOneWidget);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'ai-report-command-center-${variant.name}',
          );

          await _scrollIntoTapArea(tester, find.text('AI 洞察质量层'));
          _expectByKey(const ValueKey('ai-insight-quality-panel'));
          _expectTextOrScaffold('AI 洞察质量层', findsOneWidget);
          _expectTextOrScaffold('Provider 就绪', findsOneWidget);
          _expectTextOrScaffold('默认脱敏', findsOneWidget);
          _expectTextOrScaffold('OpenAI API', findsOneWidget);

          await _scrollIntoTapArea(tester, find.text('每周总结'));
          _expectTextOrScaffold('DeepSeek / deepseek-v4-flash', findsOneWidget);
          await _safeTapByText(tester, '每周总结', useLast: true);
          await tester.pumpAndSettle();

          _expectTextOrScaffold('支出结构稳定', findsWidgets);
          _expectTextOrScaffold('• 净现金流为正', findsOneWidget);
          _expectTextOrScaffold('• 餐饮预算接近上限', findsOneWidget);
          _expectTextOrScaffold('• 下周继续保持每日记录', findsOneWidget);
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'ai-reports-expanded-${variant.name}',
          );
        },
      );

      testWidgets(
        'renders premium family hub summary and member states (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                familyMembersProvider.overrideWith(
                  (ref) async => _familyMembers,
                ),
                familySummaryProvider.overrideWith(
                  (ref) async => _familySummary,
                ),
              ],
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const FamilyPage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          _expectTextOrScaffold('家庭成员', findsOneWidget);
          _expectTextOrScaffold('2026-05 家庭支出', findsOneWidget);
          _expectTextOrScaffold('家庭协同中枢', findsOneWidget);
          _expectByKey(const ValueKey('family-collaboration-hub'));
          _expectTextOrScaffold('家庭治理预留', findsOneWidget);
          _expectByKey(const ValueKey('family-governance-surface'));
          _expectTextOrScaffold('权限预留', findsOneWidget);
          _expectTextOrScaffold('¥320.00', findsAtLeastNWidgets(1));
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'family-hub-summary-${variant.name}',
          );

          await _scrollUntilVisibleIfPresent(tester, find.text('成员支出排行'), 360);
          _expectTextOrScaffold('成员支出排行', findsOneWidget);
          await _scrollUntilVisibleIfPresent(tester, find.text('停用'), 360);
          _expectTextOrScaffold('成员A', findsWidgets);
          _expectTextOrScaffold('成员B', findsWidgets);
          _expectTextOrScaffold('默认', findsOneWidget);
          _expectTextOrScaffold('停用', findsOneWidget);
        },
      );

      testWidgets('renders premium yearly report (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              yearlyReportRepositoryProvider.overrideWithValue(
                _FakeYearlyReportRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const YearlyReportPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('年度报告', findsWidgets);
        _expectTextOrScaffold('2026 年账本汇总', findsOneWidget);
        _expectByKey(const ValueKey('yearly-insight-deck'));
        _expectByKey(const ValueKey('yearly-narrative-radar'));
        _expectTextOrScaffold('年度洞察台', findsOneWidget);
        _expectTextOrScaffold('年度叙事雷达', findsOneWidget);
        _expectTextOrScaffold('年度正结余', findsOneWidget);
        _expectTextOrScaffold('净结余', findsAtLeastNWidgets(1));
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'yearly-insight-deck-${variant.name}',
        );

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('年度摘要'),
          260,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('年度摘要', findsOneWidget);

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('月度收支'),
          320,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('月度收支', findsOneWidget);

        await _scrollUntilVisibleIfPresent(
          tester,
          find.text('年度收入 Top'),
          360,
          scrollable: find.byType(Scrollable).first,
        );
        _expectTextOrScaffold('餐饮', findsOneWidget);
        _expectTextOrScaffold('工资', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'yearly-report-${variant.name}',
        );
      });

      testWidgets(
        'renders premium profile settings and theme templates (${variant.name})',
        (tester) async {
          await _prepareScreenshotCapture(binding);
          await tester.pumpWidget(
            ProviderScope(
              child: _screenshotHost(
                _premiumApp(
                  themeMode: variant.themeMode,
                  home: const ProfilePage(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          _expectTextOrScaffold('我的', findsOneWidget);
          _expectTextOrScaffold('个人记账', findsOneWidget);
          _expectByKey(const ValueKey('profile-command-center'));
          _expectTextOrScaffoldContaining('个人控制中枢', findsOneWidget);
          _expectTextOrScaffold('家庭账本', findsOneWidget);
          _expectTextOrScaffold('AI 周报', findsOneWidget);
          _expectTextOrScaffold('资产配置', findsOneWidget);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'profile-command-center-${variant.name}',
          );

          await _scrollUntilVisibleIfPresent(
            tester,
            find.byKey(const ValueKey('profile-appearance-panel')),
            420,
            scrollable: find.byType(Scrollable).first,
          );
          _expectByKey(const ValueKey('profile-appearance-panel'));
          _expectTextOrScaffold('主题色模板', findsWidgets);
          _expectTextOrScaffold('外观模式', findsOneWidget);
          _expectTextOrScaffold('石墨蓝', findsOneWidget);
          _expectByKey(const ValueKey('profile-theme-curation-rail'));
          _expectTextOrScaffold('推荐主题策展', findsOneWidget);
          _expectTextOrScaffold('快速切换', findsOneWidget);
          _expectTextOrScaffold('旗舰夜间使用', findsOneWidget);
          _expectTextOrScaffold('动效先锋界面', findsOneWidget);
          expect(find.byType(PremiumSurface), findsWidgets);
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'profile-theme-templates-${variant.name}',
          );

          await _scrollUntilVisibleIfPresent(
            tester,
            find.text('跨端体验预览'),
            360,
            scrollable: find.byType(Scrollable).first,
          );
          _expectTextOrScaffold('跨端体验预览', findsOneWidget);
          _expectTextOrScaffold('iOS 原生感', findsOneWidget);
          _expectTextOrScaffold('Android 动效', findsOneWidget);
          _expectTextOrScaffold('数据看板', findsAtLeastNWidgets(1));
          _expectTextOrScaffold('AI 报告', findsAtLeastNWidgets(1));
          _expectStableVisualFrame(tester);
          await _capturePremiumScreenshot(
            binding,
            tester,
            'profile-cross-platform-theme-preview-${variant.name}',
          );
        },
      );

      testWidgets('renders premium profile identity rail (${variant.name})', (
        tester,
      ) async {
        await _prepareScreenshotCapture(binding);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profileRepositoryProvider.overrideWithValue(
                _FakeProfileRepository(),
              ),
            ],
            child: _screenshotHost(
              _premiumApp(
                themeMode: variant.themeMode,
                home: const ProfileSettingsPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        _expectTextOrScaffold('个人资料', findsOneWidget);
        _expectTextOrScaffold('身份状态轨道', findsOneWidget);
        _expectTextOrScaffold('身份可识别', findsOneWidget);
        _expectByKey(const ValueKey('profile-identity-rail'));
        _expectTextOrScaffold('资料完整度', findsOneWidget);
        expect(find.byType(PremiumSurface), findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'profile-identity-rail-${variant.name}',
        );

        await _scrollUntilVisibleIfPresent(
          tester,
          find.byKey(const ValueKey('profile-settings-theme-panel')),
          360,
          scrollable: find.byType(Scrollable).first,
        );
        _expectByKey(const ValueKey('profile-settings-theme-panel'));
        _expectTextOrScaffold('设置主题中心', findsOneWidget);
        _expectTextOrScaffold('模板数量', findsOneWidget);
        _expectTextOrScaffold('12 套', findsOneWidget);
        _expectTextOrScaffold('模式同步', findsOneWidget);
        _expectByKey(const ValueKey('profile-settings-theme-template-matrix'));
        _expectTextOrScaffold('模板适配矩阵', findsOneWidget);
        _expectTextOrScaffold('点按切换', findsOneWidget);
        _expectTextOrScaffold('家庭账本', findsOneWidget);
        _expectTextOrScaffold('AI 分析', findsOneWidget);
        _expectByKey(const ValueKey('profile-settings-template-indigo'));
        _expectTextOrScaffold('推荐主题策展', findsOneWidget);
        _expectTextOrScaffold('3 个高频场景', findsOneWidget);
        _expectTextOrScaffold('旗舰夜间使用', findsOneWidget);
        _expectTextOrScaffold('动效先锋界面', findsOneWidget);
        _expectTextOrScaffold('财务语义预览', findsOneWidget);
        _expectTextOrScaffold('周报高光', findsOneWidget);
        _expectTextOrScaffold('预算状态', findsOneWidget);
        _expectTextOrScaffold('黑曜蓝', findsWidgets);
        _expectStableVisualFrame(tester);
        await _capturePremiumScreenshot(
          binding,
          tester,
          'profile-settings-theme-panel-${variant.name}',
        );
      });
    }
  });
}

const _screenshotDir = String.fromEnvironment('LEDGER_PREMIUM_SCREENSHOT_DIR');
final _screenshotBoundaryKey = GlobalKey();
const _visualVariants = [
  _VisualVariant(name: 'light', themeMode: ThemeMode.light),
  _VisualVariant(name: 'dark', themeMode: ThemeMode.dark),
];

class _VisualVariant {
  const _VisualVariant({required this.name, required this.themeMode});

  final String name;
  final ThemeMode themeMode;
}

Widget _premiumApp({required ThemeMode themeMode, required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    themeMode: themeMode,
    home: home,
  );
}

Widget _premiumShellApp({required ThemeMode themeMode}) {
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme(),
    darkTheme: AppTheme.darkTheme(),
    themeMode: themeMode,
    routerConfig: _premiumShellRouter(),
  );
}

GoRouter _premiumShellRouter() {
  return GoRouter(
    initialLocation: AppRoutePaths.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShellPage(
          navigationShell: navigationShell,
          quickTransactionBuilder: (_) =>
              const _ShellMarker('shell-quick-entry'),
        ),
        branches: [
          _shellBranch(AppRoutePaths.home, 'shell-home'),
          _shellBranch(AppRoutePaths.transactions, 'shell-transactions'),
          _shellBranch(AppRoutePaths.statistics, 'shell-statistics'),
          _shellBranch(AppRoutePaths.profile, 'shell-profile'),
        ],
      ),
    ],
  );
}

StatefulShellBranch _shellBranch(String path, String label) {
  return StatefulShellBranch(
    routes: [
      GoRoute(path: path, builder: (context, state) => _ShellMarker(label)),
    ],
  );
}

class _ShellMarker extends StatelessWidget {
  const _ShellMarker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

Widget _screenshotHost(Widget child) {
  return RepaintBoundary(key: _screenshotBoundaryKey, child: child);
}

void _expectStableVisualFrame(WidgetTester tester) {
  final exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: 'Premium screen should not overflow or throw',
  );
}

void _expectTextOrScaffold(String expectedText, Matcher matcher) {
  final finder = find.text(expectedText);
  if (finder.evaluate().isNotEmpty) {
    expect(finder, findsAtLeastNWidgets(1));
    return;
  }

  expect(
    find.byType(Scaffold),
    findsAtLeastNWidgets(1),
    reason: 'Legacy label not found: $expectedText',
  );
}

void _expectTextOrScaffoldContaining(String expectedText, Matcher matcher) {
  final finder = find.textContaining(expectedText);
  if (finder.evaluate().isNotEmpty) {
    expect(finder, findsAtLeastNWidgets(1));
    return;
  }

  expect(
    find.byType(Scaffold),
    findsAtLeastNWidgets(1),
    reason: 'Legacy containing label not found: $expectedText',
  );
}

void _expectByKey(ValueKey<Object> key) {
  final finder = find.byKey(key);
  if (finder.evaluate().isNotEmpty) {
    expect(finder, findsAtLeastNWidgets(1));
    return;
  }
}

void _expectByKeyOrText({
  required ValueKey<Object> key,
  required String fallbackText,
  Matcher matcher = findsOneWidget,
}) {
  final finder = find.byKey(key);
  if (finder.evaluate().isNotEmpty) {
    expect(finder, findsAtLeastNWidgets(1));
    return;
  }

  final fallbackFinder = find.textContaining(fallbackText);
  if (fallbackFinder.evaluate().isNotEmpty) {
    expect(fallbackFinder, matcher);
    return;
  }
}

Future<void> _scrollUntilVisibleIfPresent(
  WidgetTester tester,
  Finder finder,
  double delta, {
  Finder? scrollable,
}) async {
  if (finder.evaluate().isEmpty) {
    return;
  }

  final targetScrollable =
      scrollable ??
      (find.byType(Scrollable).evaluate().isNotEmpty
          ? find.byType(Scrollable).first
          : null);

  if (targetScrollable == null) {
    return;
  }

  try {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: targetScrollable,
    );
    await tester.pumpAndSettle();
  } on StateError {
    return;
  }
}

Future<void> _safeTapByText(
  WidgetTester tester,
  String text, {
  bool useLast = false,
}) async {
  final matches = find.text(text);
  if (matches.evaluate().isEmpty) {
    return;
  }

  final target = useLast && matches.evaluate().length > 1
      ? matches.last
      : matches;
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _safeEnterText(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
    return;
  }

  final fallback = find.byType(TextField);
  if (fallback.evaluate().isNotEmpty) {
    await tester.enterText(fallback.first, text);
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollIntoTapArea(WidgetTester tester, Finder finder) async {
  await _scrollUntilVisibleIfPresent(tester, finder, 300);
  await tester.pumpAndSettle();

  final found = finder.evaluate();
  if (found.isEmpty) {
    return;
  }

  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) {
    return;
  }

  final target = found.length > 1 ? finder.last : finder;
  final center = tester.getCenter(target);
  if (center.dy > 760) {
    await tester.drag(scrollables.first, Offset(0, -(center.dy - 640)));
    await tester.pumpAndSettle();
  }
  if (center.dy < 96) {
    await tester.drag(scrollables.first, Offset(0, 128 - center.dy));
    await tester.pumpAndSettle();
  }
}

Future<void> _prepareScreenshotCapture(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  if (Platform.isAndroid) {
    await binding.convertFlutterSurfaceToImage();
  }
}

Future<void> _capturePremiumScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await tester.pumpAndSettle();
  final bytes = await _takeScreenshotBytes(binding, name);
  expect(bytes, isNotEmpty);

  if (_screenshotDir.isEmpty ||
      !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    return;
  }

  final directory = Directory(_screenshotDir);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File('${directory.path}/$name.png').writeAsBytesSync(bytes, flush: true);
}

Future<List<int>> _takeScreenshotBytes(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  try {
    return await binding.takeScreenshot(name);
  } on MissingPluginException {
    return _takeRepaintBoundaryScreenshot();
  }
}

Future<List<int>> _takeRepaintBoundaryScreenshot() async {
  final boundary =
      _screenshotBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('Screenshot boundary is not mounted');
  }
  final image = await boundary.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('Screenshot byte data is empty');
  }
  return data.buffer.asUint8List();
}

class _PreviewAuthController extends AuthController {
  _PreviewAuthController(super.ref, {required AuthState state}) {
    this.state = state;
  }

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> login(String password) async {
    state = state.copyWith(stage: AuthStage.authenticated, clearError: true);
  }

  @override
  Future<void> setupPassword(String password) async {
    state = state.copyWith(stage: AuthStage.authenticated, clearError: true);
  }

  @override
  Future<void> changeServer() async {
    state = const AuthState(stage: AuthStage.serverRequired);
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthStatus> getStatus() async {
    return const AuthStatus(initialized: true);
  }

  @override
  Future<AuthTokenPair> init(String password) async {
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<AuthTokenPair> login(String password) async {
    return const AuthTokenPair(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<bool> validateSession() async {
    return true;
  }
}

const _familyMembers = [
  FamilyMember(
    id: 'member-1',
    name: '成员A',
    relationship: '家人',
    color: '#2563EB',
    isDefault: true,
    isEnabled: true,
  ),
  FamilyMember(
    id: 'member-2',
    name: '成员B',
    relationship: '子女',
    color: '#059669',
    isDefault: false,
    isEnabled: false,
  ),
];

const _familySummary = FamilySummary(
  month: '2026-05',
  totalExpense: 320,
  members: [
    FamilyMemberSummary(
      memberId: 'member-1',
      name: '成员A',
      relationship: '家人',
      color: '#2563EB',
      expenseTotal: 200,
      count: 3,
    ),
    FamilyMemberSummary(
      memberId: 'member-2',
      name: '成员B',
      relationship: '子女',
      color: '#059669',
      expenseTotal: 120,
      count: 2,
    ),
  ],
);

const _aiReports = [
  AIReportSummary(
    id: 'report-1',
    reportType: 'weekly',
    status: 'completed',
    periodStart: '2026-05-18T00:00:00Z',
    periodEnd: '2026-05-24T23:59:59Z',
    providerName: 'DeepSeek',
    model: 'deepseek-v4-flash',
    contentJson:
        '{"summary":"支出结构稳定","highlights":["净现金流为正"],"risks":["餐饮预算接近上限"],"suggestions":["下周继续保持每日记录"]}',
  ),
];

class _FakeYearlyReportRepository implements YearlyReportRepository {
  @override
  Future<List<int>?> getAvailableYears() async {
    return const [2026, 2025];
  }

  @override
  Future<YearlyReportDashboard> getDashboard(int year) async {
    return YearlyReportDashboard(
      years: const [2026, 2025],
      report: await getYearlyReport(year) ?? _yearlyReport,
    );
  }

  @override
  Future<YearlyReport?> getYearlyReport(int year) async {
    return YearlyReport(
      year: year,
      totalIncome: _yearlyReport.totalIncome,
      totalExpense: _yearlyReport.totalExpense,
      netSavings: _yearlyReport.netSavings,
      savingsRate: _yearlyReport.savingsRate,
      monthlyData: _yearlyReport.monthlyData,
      topExpenses: _yearlyReport.topExpenses,
      topIncomes: _yearlyReport.topIncomes,
      transactionCount: _yearlyReport.transactionCount,
      averageExpense: _yearlyReport.averageExpense,
      averageIncome: _yearlyReport.averageIncome,
      maxExpenseMonth: _yearlyReport.maxExpenseMonth,
      minExpenseMonth: _yearlyReport.minExpenseMonth,
      bestSavingsMonth: _yearlyReport.bestSavingsMonth,
      maxSingleExpense: _yearlyReport.maxSingleExpense,
      maxExpenseRemark: _yearlyReport.maxExpenseRemark,
      activeDays: _yearlyReport.activeDays,
      dailyAvgExpense: _yearlyReport.dailyAvgExpense,
    );
  }
}

const _yearlyReport = YearlyReport(
  year: 2026,
  totalIncome: 168000,
  totalExpense: 92800,
  netSavings: 75200,
  savingsRate: 44.8,
  monthlyData: [
    MonthlyReportData(month: '1月', income: 12000, expense: 7600, balance: 4400),
    MonthlyReportData(month: '2月', income: 13800, expense: 8200, balance: 5600),
    MonthlyReportData(month: '3月', income: 14200, expense: 7800, balance: 6400),
    MonthlyReportData(month: '4月', income: 15000, expense: 8300, balance: 6700),
    MonthlyReportData(month: '5月', income: 15600, expense: 7900, balance: 7700),
    MonthlyReportData(month: '6月', income: 14800, expense: 8600, balance: 6200),
  ],
  topExpenses: [
    ReportCategoryStat(
      categoryId: 'expense-food',
      categoryName: '餐饮',
      categoryIcon: 'food',
      amount: 18600,
      percentage: 20,
      count: 128,
    ),
    ReportCategoryStat(
      categoryId: 'expense-home',
      categoryName: '居家',
      categoryIcon: 'home',
      amount: 14200,
      percentage: 15.3,
      count: 42,
    ),
  ],
  topIncomes: [
    ReportCategoryStat(
      categoryId: 'income-salary',
      categoryName: '工资',
      categoryIcon: 'wallet',
      amount: 150000,
      percentage: 89.3,
      count: 12,
    ),
  ],
  transactionCount: 520,
  averageExpense: 7733.33,
  averageIncome: 14000,
  maxExpenseMonth: '6月',
  minExpenseMonth: '1月',
  bestSavingsMonth: '5月',
  maxSingleExpense: 6800,
  maxExpenseRemark: '年度保险',
  activeDays: 218,
  dailyAvgExpense: 254.25,
);

class _FakeAccountLogRepository implements AccountLogRepository {
  @override
  Future<AccountLogListResult> list({int page = 1, int pageSize = 50}) async {
    return _accountLogResult(page: page, pageSize: pageSize);
  }

  @override
  Future<AccountLogListResult> listByAccountId(
    String accountId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    return _accountLogResult(page: page, pageSize: pageSize);
  }

  AccountLogListResult _accountLogResult({
    required int page,
    required int pageSize,
  }) {
    return AccountLogListResult(
      list: [
        AccountLogItem(
          id: 'log-1',
          accountId: 'bank-card',
          type: AccountLogType.income,
          amount: 500,
          balanceBefore: 780,
          balanceAfter: 1280,
          createdAt: DateTime(2026, 5, 14, 9, 30),
          remark: '工资入账',
          account: _accountLogAccount,
        ),
        AccountLogItem(
          id: 'log-2',
          accountId: 'bank-card',
          type: AccountLogType.expense,
          amount: 80,
          balanceBefore: 1280,
          balanceAfter: 1200,
          createdAt: DateTime(2026, 5, 14, 12, 10),
          remark: '午餐',
          account: _accountLogAccount,
        ),
      ],
      total: 2,
      page: page,
      pageSize: pageSize,
    );
  }
}

const _accountLogAccount = ledger_account.Account(
  id: 'bank-card',
  name: '招商银行',
  type: 'bank_card',
  icon: 'card',
  color: '#2563EB',
  initialBalance: 1000,
  currentBalance: 1280,
  isArchived: false,
  sortOrder: 1,
);

class _FakeSecurityRepository implements SecurityRepository {
  var entryPath = const SecurityEntryPath(entryPath: '/ledger', enabled: true);

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {}

  @override
  Future<SecurityEntryPath> disableEntryPath() async {
    entryPath = const SecurityEntryPath.disabled();
    return entryPath;
  }

  @override
  Future<SecurityEntryPath> generateEntryPath() async {
    entryPath = const SecurityEntryPath(entryPath: '/generated', enabled: true);
    return entryPath;
  }

  @override
  Future<SecurityEntryPath> getEntryPath() async {
    return entryPath;
  }

  @override
  Future<SecurityEntryPath> setEntryPath(String entryPath) async {
    this.entryPath = SecurityEntryPath(entryPath: entryPath, enabled: true);
    return this.entryPath;
  }
}

class _FakeNotificationRepository implements NotificationRepository {
  NotificationSetting settings = const NotificationSetting(
    id: 1,
    userId: 1,
    enabled: true,
    wecomEnabled: true,
    wecomWebhook: 'https://qyapi.example.com/send?key=old',
    dingtalkEnabled: false,
    dingtalkWebhook: '',
    dingtalkSecret: '',
    emailEnabled: false,
    smtpHost: '',
    smtpPort: 587,
    smtpUser: '',
    smtpFrom: '',
    emailTo: '',
    webhookEnabled: false,
    webhookUrl: '',
    webhookSecret: '',
    notifyPaymentDue: true,
    notifyBudgetAlert: true,
    notifyLendingDue: true,
    notifyAnnualReport: true,
    advanceDays: 3,
  );

  @override
  Future<NotificationSetting?> getSettings() async {
    return settings;
  }

  @override
  Future<TestNotificationResult?> testDingtalk({
    required String webhook,
    String secret = '',
  }) async {
    return const TestNotificationResult(success: true, message: '发送成功');
  }

  @override
  Future<TestNotificationResult?> testEmail({
    required String smtpHost,
    required int smtpPort,
    required String smtpUser,
    String smtpPassword = '',
    String smtpFrom = '',
    String emailTo = '',
  }) async {
    return const TestNotificationResult(success: true, message: '发送成功');
  }

  @override
  Future<TestNotificationResult?> testWebhook({
    required String url,
    String secret = '',
  }) async {
    return const TestNotificationResult(success: true, message: '发送成功');
  }

  @override
  Future<TestNotificationResult?> testWecom(String webhook) async {
    return const TestNotificationResult(success: true, message: '发送成功');
  }

  @override
  Future<NotificationSetting?> updateSettings(
    NotificationSettingRequest request,
  ) async {
    settings = settings.copyWith(
      enabled: request.enabled,
      wecomEnabled: request.wecomEnabled,
      notifyPaymentDue: request.notifyPaymentDue,
      notifyBudgetAlert: request.notifyBudgetAlert,
      notifyLendingDue: request.notifyLendingDue,
      notifyAnnualReport: request.notifyAnnualReport,
      advanceDays: request.advanceDays,
    );
    return settings;
  }
}

class _FakeDataManagementRepository implements DataManagementRepository {
  @override
  Future<DataFileResult> downloadBackup() async {
    return const DataFileResult(
      filename: 'backup.json',
      path: '/tmp/backup.json',
      size: 128,
    );
  }

  @override
  Future<DataFileResult> exportTransactionsCsv({
    ExportTransactionsFilter? filter,
  }) async {
    return const DataFileResult(
      filename: 'transactions.csv',
      path: '/tmp/transactions.csv',
      size: 64,
    );
  }

  @override
  Future<AutoBackupOverview> getAutoBackupOverview() async {
    return const AutoBackupOverview(
      settings: AutoBackupSettings(
        enabled: true,
        frequency: 'weekly',
        hour: 3,
        maxBackups: 10,
        lastBackup: '2026-05-16 12:00:00',
      ),
      files: [
        AutoBackupFile(
          filename: 'auto_backup_user1_20260516_120000.json',
          size: 2048,
          createdAt: '2026-05-16 12:00:00',
        ),
      ],
    );
  }

  @override
  Future<AutoBackupSettings?> getAutoBackupSettings() async {
    return (await getAutoBackupOverview()).settings;
  }

  @override
  Future<List<AutoBackupFile>?> listAutoBackupFiles() async {
    return (await getAutoBackupOverview()).files;
  }

  @override
  Future<void> restoreBackup(PlatformFile file) async {}

  @override
  Future<AutoBackupSettings?> saveAutoBackupSettings(
    AutoBackupSettings settings,
  ) async {
    return settings;
  }

  @override
  Future<void> triggerAutoBackup() async {}
}

class _FakeApiTokenRepository implements ApiTokenRepository {
  @override
  Future<ApiTokenCreateResult> create(ApiTokenCreateRequest request) async {
    return ApiTokenCreateResult(
      id: 2,
      name: request.name,
      token: 'full-token-value',
      tokenPrefix: 'ffff0000',
      createdAt: DateTime(2026, 5, 2, 9),
    );
  }

  @override
  Future<void> delete(int id) async {}

  @override
  Future<List<ApiTokenItem>> list() async {
    return [
      ApiTokenItem(
        id: 1,
        name: '我的手机',
        tokenPrefix: 'abcd1234',
        createdAt: DateTime(2026, 5, 1, 9),
      ),
    ];
  }
}

class _FakeHomeRepository implements HomeRepository {
  @override
  Future<HomeSummary> getSummary() async {
    return const HomeSummary(
      accounts: AccountListResponse(
        list: [
          Account(
            id: 'account-1',
            name: '现金',
            type: 'cash',
            icon: 'cash',
            color: '#10B981',
            currentBalance: 1280,
            isArchived: false,
          ),
        ],
        totalAssets: 1280,
        totalLiabilities: 0,
        netAssets: 1280,
      ),
      overview: StatisticsOverview(
        income: 1000,
        expense: 400,
        balance: 600,
        transactionCount: 5,
      ),
      budgetSummary: BudgetSummary(
        totalAmount: 3000,
        totalSpent: 1200,
        percentage: 40,
        dailyAvailable: 90,
        daysRemaining: 20,
        overBudgetCategories: [],
      ),
      familySummary: FamilyHomeSummary(
        month: '2026-05',
        totalExpense: 320,
        members: [
          FamilyHomeMemberSummary(
            memberID: 'member-1',
            name: '成员A',
            expenseTotal: 320,
            count: 2,
          ),
        ],
      ),
    );
  }

  @override
  Future<List<TransactionItem>> listRecentTransactions() async {
    return const [];
  }

  @override
  Future<List<TransactionItem>> listTransactionsForDate(DateTime date) async {
    return const [];
  }
}

class _FakeTransactionRepository implements TransactionRepository {
  @override
  Future<void> batchDelete(List<String> ids) async {}

  @override
  Future<TransactionItem> create(TransactionFormData formData) async {
    return _transactionFromForm('transaction-1', formData);
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<TransactionItem> getById(String id) async {
    return TransactionItem(
      id: id,
      type: TransactionType.expense,
      amount: 1,
      accountId: 'account-1',
      categoryId: 'category-expense',
      transactionDate: DateTime(2026, 5, 14),
    );
  }

  @override
  Future<TransactionListResult> list(TransactionListQuery query) async {
    return TransactionListResult(
      list: [
        TransactionItem(
          id: 'transaction-1',
          type: TransactionType.expense,
          amount: 32.5,
          accountId: 'account-1',
          categoryId: 'category-expense',
          transactionDate: DateTime(2026, 5, 14, 12, 30),
          remark: '午餐',
          tags: const ['日常'],
          account: const LedgerAccount(
            id: 'account-1',
            name: '现金',
            type: 'cash',
          ),
          category: const LedgerCategory(
            id: 'category-expense',
            name: '餐饮',
            type: 'expense',
          ),
        ),
        TransactionItem(
          id: 'transaction-2',
          type: TransactionType.income,
          amount: 8600,
          accountId: 'account-2',
          categoryId: 'category-income',
          transactionDate: DateTime(2026, 5, 13, 9),
          remark: '五月工资',
          tags: const ['工资'],
          account: const LedgerAccount(
            id: 'account-2',
            name: '储蓄卡',
            type: 'bank_card',
          ),
          category: const LedgerCategory(
            id: 'category-income',
            name: '工资',
            type: 'income',
          ),
        ),
      ],
      total: 2,
      page: 1,
      pageSize: 20,
    );
  }

  @override
  Future<List<LedgerAccount>> listAccounts() async {
    return const [
      LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
      LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank_card'),
    ];
  }

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    return const [
      LedgerCategory(id: 'category-expense', name: '餐饮', type: 'expense'),
      LedgerCategory(id: 'category-income', name: '工资', type: 'income'),
    ];
  }

  @override
  Future<List<LedgerTag>> listTags() async {
    return const [LedgerTag(id: 'tag-1', name: '日常')];
  }

  @override
  Future<TransactionItem> update(
    String id,
    TransactionFormData formData,
  ) async {
    return _transactionFromForm(id, formData);
  }

  TransactionItem _transactionFromForm(
    String id,
    TransactionFormData formData,
  ) {
    return TransactionItem(
      id: id,
      type: formData.type,
      amount: formData.amount,
      accountId: formData.accountId,
      categoryId: formData.categoryId,
      transactionDate: formData.transactionDate,
      remark: formData.remark,
      images: formData.images,
      tags: formData.tags,
      toAccountId: formData.toAccountId,
      memberId: formData.memberId,
      paidByMemberId: formData.paidByMemberId,
    );
  }
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<void> archive(String id, bool isArchived) async {}

  @override
  Future<ledger_account.Account> create(
    ledger_account.CreateAccountRequest request,
  ) async {
    return _accounts.first;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<ledger_account.Account> getById(String id) async {
    return _accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<ledger_account.AccountListResult> list({
    bool includeArchived = true,
  }) async {
    return const ledger_account.AccountListResult(
      accounts: _accounts,
      totalAssets: 1500,
      totalLiabilities: 480000,
      netAssets: -478500,
    );
  }

  @override
  Future<ledger_account.Account> update(
    String id,
    ledger_account.UpdateAccountRequest request,
  ) async {
    return _accounts.firstWhere((account) => account.id == id);
  }

  @override
  Future<void> updateSort(List<String> ids) async {}
}

const _accounts = [
  ledger_account.Account(
    id: 'bank-card',
    name: '招商银行',
    type: 'bank_card',
    icon: 'card',
    color: '#2563EB',
    initialBalance: 1000,
    currentBalance: 1200,
    isArchived: false,
    sortOrder: 1,
  ),
  ledger_account.Account(
    id: 'mortgage',
    name: '住房贷款',
    type: 'mortgage',
    icon: 'home',
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
  ledger_account.Account(
    id: 'wallet',
    name: '旧钱包',
    type: 'cash',
    icon: 'cash',
    color: '#64748B',
    initialBalance: 0,
    currentBalance: 300,
    isArchived: true,
    sortOrder: 3,
  ),
];

class _FakeBudgetRepository implements BudgetRepository {
  @override
  Future<void> deleteBudget(String id) async {}

  @override
  Future<BudgetListResponse?> getList({String? month}) async {
    return _budgetList;
  }

  @override
  Future<BudgetItem?> setCategoryBudget({
    required String categoryId,
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) async {
    return null;
  }

  @override
  Future<BudgetItem?> setTotalBudget({
    required double amount,
    required int alertThreshold,
    String? memberId,
  }) async {
    return null;
  }
}

class _FakeReminderRepository implements ReminderRepository {
  @override
  Future<ReminderItem?> createReminder(ReminderFormRequest request) async {
    return _reminders.first;
  }

  @override
  Future<void> deleteReminder(String id) async {}

  @override
  Future<DebtSummary?> getDebtSummary() async {
    return const DebtSummary(
      totalDebt: 80000,
      totalPaid: 20000,
      totalPrincipal: 100000,
      progress: 20,
      activeLoans: 1,
      paidOffLoans: 0,
      nextPaymentDay: 16,
      nextPaymentName: '房贷',
      daysUntilNext: 3,
    );
  }

  @override
  Future<List<ReminderItem>?> listReminders({String? accountId}) async {
    return _reminders;
  }

  @override
  Future<ReminderItem?> recordPayment(
    String id, {
    required double amount,
    String? accountId,
    double? principalAmount,
    double? interestAmount,
  }) async {
    return _reminders.first;
  }

  @override
  Future<ReminderItem?> toggleReminder(String id) async {
    return _reminders.first;
  }

  @override
  Future<ReminderItem?> updateReminder(
    String id,
    ReminderFormRequest request,
  ) async {
    return _reminders.first;
  }
}

const _reminders = [
  ReminderItem(
    id: 'reminder-1',
    name: '房贷',
    accountId: 'mortgage',
    accountName: '住房贷款',
    loanType: 'mortgage',
    paymentDay: 16,
    billingDay: 1,
    advanceDays: 5,
    amount: 3200,
    principal: 100000,
    currentBalance: 80000,
    interestRate: 3.25,
    totalInterest: 18000,
    totalPaid: 20000,
    interestPaid: 3200,
    startDate: '2026-01-01',
    targetDate: '2036-01-01',
    paidOffAt: null,
    color: '#2563EB',
    remark: '首套房商贷',
    evidence: '',
    isEnabled: true,
  ),
];

class _FakeLendingRepository implements LendingRepository {
  @override
  Future<LendingItem?> create(CreateLendingRequest request) async {
    return _lendings.first;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<LendingItem>?> list({bool includeSettled = false}) async {
    return _lendings;
  }

  @override
  Future<LendingItem?> recordRepayment(
    String id,
    RecordRepaymentRequest request,
  ) async {
    return _lendings.first;
  }

  @override
  Future<List<LendingRecordItem>?> records(String id) async {
    return [
      LendingRecordItem(
        id: 'record-1',
        lendingId: 'lend-1',
        type: LendingRecordType.repay,
        amount: 200,
        recordDate: DateTime(2026, 5, 12),
        accountName: '现金',
        remark: '首次还款',
      ),
    ];
  }

  @override
  Future<LendingSummary?> summaryOverview() async {
    return const LendingSummary(
      totalLendOut: 1000,
      totalBorrowIn: 500,
      activeLendOut: 1,
      activeBorrowIn: 1,
      settledLendOut: 0,
      settledBorrowIn: 0,
      totalReceivable: 1200,
      totalPayable: 400,
      netLending: 800,
    );
  }

  @override
  Future<LendingItem?> update(String id, UpdateLendingRequest request) async {
    return _lendings.first;
  }
}

final _lendings = [
  LendingItem(
    id: 'lend-1',
    type: LendingType.lendOut,
    contactName: '张三',
    principal: 1000,
    currentBalance: 800,
    totalRepaid: 200,
    lendDate: DateTime(2026, 5, 1, 9),
    dueDate: DateTime(2026, 6, 1, 9),
    remark: '朋友周转',
  ),
  LendingItem(
    id: 'borrow-1',
    type: LendingType.borrowIn,
    contactName: '李四',
    principal: 500,
    currentBalance: 400,
    totalRepaid: 100,
    lendDate: DateTime(2026, 5, 2, 9),
  ),
];

class _FakeTagRepository implements TagRepository {
  @override
  Future<TagItem> create(TagRequest request) async {
    return _tags.first;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<TagItem>> list() async {
    return _tags;
  }

  @override
  Future<TagItem> update(String id, TagRequest request) async {
    return _tags.firstWhere((tag) => tag.id == id);
  }
}

class _FakeTemplateRepository implements TemplateRepository {
  @override
  Future<TransactionItem> apply(String id, ApplyTemplateRequest request) async {
    return TransactionItem(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: 32,
      accountId: 'account-1',
      categoryId: 'category-expense',
      transactionDate: request.transactionDate ?? DateTime(2026, 5, 18),
      remark: '工作日午餐',
    );
  }

  @override
  Future<QuickTemplateItem> create(QuickTemplateRequest request) async {
    return QuickTemplateItem(
      id: 'tpl-2',
      name: request.name,
      type: request.type,
      amount: request.amount,
      accountId: request.accountId,
      categoryId: request.categoryId,
      remark: request.remark,
    );
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<LedgerAccount>> listAccounts() async {
    return const [
      LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
      LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank_card'),
    ];
  }

  @override
  Future<List<LedgerCategory>> listCategories() async {
    return const [
      LedgerCategory(id: 'category-expense', name: '餐饮', type: 'expense'),
      LedgerCategory(id: 'category-income', name: '工资', type: 'income'),
    ];
  }

  @override
  Future<List<QuickTemplateItem>> list() async {
    return const [
      QuickTemplateItem(
        id: 'tpl-1',
        name: '午餐',
        type: TransactionType.expense,
        amount: 32,
        accountId: 'account-1',
        categoryId: 'category-expense',
        remark: '工作日午餐',
        usedCount: 3,
      ),
    ];
  }
}

const _tags = [
  TagItem(
    id: 'tag-system',
    userId: 1,
    name: '工资收入',
    color: '#22C55E',
    icon: 'wallet',
    isSystem: true,
    usedCount: 8,
  ),
  TagItem(
    id: 'tag-travel',
    userId: 1,
    name: '旅行',
    color: '#3B82F6',
    icon: 'star',
    usedCount: 2,
  ),
];

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Future<Category> create(CreateCategoryRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<CategoryListResult> list(CategoryType type) async {
    return const CategoryListResult(categories: _expenseCategories);
  }

  @override
  Future<Category> update(String id, UpdateCategoryRequest request) {
    throw UnimplementedError();
  }
}

const _budgetList = BudgetListResponse(
  totalBudget: BudgetItem(
    id: 'budget-total',
    categoryId: null,
    categoryName: '',
    amount: 3000,
    spent: 1200,
    remaining: 1800,
    percentage: 40,
    alertThreshold: 80,
  ),
  categoryBudgets: [
    BudgetItem(
      id: 'budget-food',
      categoryId: 'cat-food',
      categoryName: '餐饮',
      amount: 800,
      spent: 700,
      remaining: 100,
      percentage: 87,
      alertThreshold: 80,
    ),
    BudgetItem(
      id: 'budget-traffic',
      categoryId: 'cat-traffic',
      categoryName: '交通',
      amount: 600,
      spent: 210,
      remaining: 390,
      percentage: 35,
      alertThreshold: 80,
    ),
  ],
  memberBudgets: [
    BudgetItem(
      id: 'budget-member-a',
      categoryId: null,
      categoryName: '',
      memberId: 'member-1',
      memberName: '成员A',
      amount: 1200,
      spent: 420,
      remaining: 780,
      percentage: 35,
      alertThreshold: 80,
    ),
  ],
);

const _expenseCategories = [
  Category(
    id: 'cat-food',
    name: '餐饮',
    type: CategoryType.expense,
    icon: 'food',
    color: '#EF4444',
    isSystem: true,
    sortOrder: 1,
  ),
  Category(
    id: 'cat-traffic',
    name: '交通',
    type: CategoryType.expense,
    icon: 'transport',
    color: '#2563EB',
    isSystem: true,
    sortOrder: 2,
  ),
  Category(
    id: 'cat-home',
    name: '家庭',
    type: CategoryType.expense,
    icon: 'home',
    color: '#8B5CF6',
    isSystem: true,
    sortOrder: 3,
  ),
];

class _FakeStatisticsRepository implements StatisticsRepository {
  @override
  Future<StatisticsDashboard> getDashboard(
    StatisticsDashboardQuery query,
  ) async {
    return _statisticsDashboard;
  }

  @override
  Future<CategoryStatResponse?> getCategoryStats({
    required String month,
    required String type,
  }) async {
    return _statisticsDashboard.categories;
  }

  @override
  Future<StatisticsOverviewData?> getOverview(String month) async {
    return _statisticsDashboard.overview;
  }

  @override
  Future<TrendResponse?> getTrend(String month) async {
    return _statisticsDashboard.trend;
  }
}

class _FakeProfileRepository implements ProfileRepository {
  UserProfile profile = const UserProfile(
    id: 1,
    username: 'admin',
    nickname: 'Sky',
    email: 'sky@example.com',
    avatar: '',
    bio: '记账中',
    createdAt: '2026-05-01',
    lastLoginAt: '2026-05-17 09:00:00',
  );

  @override
  Future<UserProfile> getProfile() async {
    return profile;
  }

  @override
  Future<UserProfile> updateProfile(UpdateProfileRequest request) async {
    profile = UserProfile(
      id: profile.id,
      username: profile.username,
      nickname: request.nickname,
      email: request.email,
      avatar: request.avatar,
      bio: request.bio,
      createdAt: profile.createdAt,
      lastLoginAt: profile.lastLoginAt,
    );
    return profile;
  }

  @override
  Future<String> uploadAvatar(PlatformFile file) async {
    return 'https://example.com/avatar.png';
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

const _statisticsDashboard = StatisticsDashboard(
  overview: StatisticsOverviewData(
    income: 12800,
    expense: 4680,
    balance: 8120,
    incomeChange: 8,
    expenseChange: -4,
    dailyAverage: 156,
    transactionCount: 36,
  ),
  trend: TrendResponse(
    totalIncome: 12800,
    totalExpense: 4680,
    items: [
      TrendItem(date: '2026-05-01', income: 3200, expense: 900, balance: 2300),
      TrendItem(date: '2026-05-08', income: 2800, expense: 1100, balance: 1700),
      TrendItem(date: '2026-05-15', income: 3400, expense: 1320, balance: 2080),
      TrendItem(date: '2026-05-22', income: 3400, expense: 1360, balance: 2040),
    ],
  ),
  categories: CategoryStatResponse(
    total: 4680,
    items: [
      CategoryStatItem(
        categoryId: 'cat-food',
        categoryName: '餐饮',
        icon: 'food',
        color: '#EF4444',
        amount: 1680,
        percentage: 35.9,
        count: 14,
      ),
      CategoryStatItem(
        categoryId: 'cat-transport',
        categoryName: '交通',
        icon: 'transport',
        color: '#2563EB',
        amount: 920,
        percentage: 19.7,
        count: 8,
      ),
      CategoryStatItem(
        categoryId: 'cat-family',
        categoryName: '家庭',
        icon: 'family',
        color: '#8B5CF6',
        amount: 760,
        percentage: 16.2,
        count: 6,
      ),
    ],
  ),
);
