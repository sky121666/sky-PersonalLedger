import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/core/config/server_config_service.dart';
import 'package:personal_ledger/core/network/api_client.dart';
import 'package:personal_ledger/core/network/api_exception.dart';
import 'package:personal_ledger/core/network/api_response.dart';
import 'package:personal_ledger/core/storage/secure_storage_service.dart';
import 'package:personal_ledger/features/account_logs/data/account_log_repository.dart';
import 'package:personal_ledger/features/api_tokens/data/api_token_repository.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/home/data/home_repository.dart';
import 'package:personal_ledger/features/lendings/data/lending_repository.dart';
import 'package:personal_ledger/features/notifications/data/notification_repository.dart';
import 'package:personal_ledger/features/profile/data/profile_repository.dart';
import 'package:personal_ledger/features/reminders/data/reminder_repository.dart';
import 'package:personal_ledger/features/reports/data/yearly_report_models.dart';
import 'package:personal_ledger/features/security/data/security_repository.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
import 'package:personal_ledger/features/tags/data/tag_repository.dart';
import 'package:personal_ledger/features/templates/data/template_repository.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';

void main() {
  group('ApiResponseParser', () {
    test('成功响应返回解析后的 data', () {
      final result = ApiResponseParser.parse<String>({
        'code': 0,
        'message': 'ok',
        'data': 'done',
      }, fromJsonT: (json) => 'parsed:$json');

      expect(result, 'parsed:done');
    });

    test('非 Map 响应抛出格式异常', () {
      expect(
        () => ApiResponseParser.parse<String>('invalid'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            '响应格式不正确',
          ),
        ),
      );
    });

    test('业务失败响应保留 code 和 message', () {
      expect(
        () => ApiResponseParser.parse<void>({
          'code': 40001,
          'message': '参数错误',
          'data': null,
        }),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 40001)
              .having((error) => error.message, 'message', '参数错误'),
        ),
      );
    });
  });

  group('ApiClient', () {
    test('网络异常不会向 UI 暴露底层地址或连接细节', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://ledger.example.com/api/v1'))
        ..httpClientAdapter = _FailingNetworkAdapter();
      final client = ApiClient(
        serverConfigService: ServerConfigService(SecureStorageService()),
        dio: dio,
      );

      await expectLater(
        client.get<void>('/health'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.message, 'message', '网络连接失败')
              .having(
                (error) => error.message,
                'message',
                isNot(contains('ledger.example.com')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('token=')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('Connection refused')),
              ),
        ),
      );
    });

    test('首页摘要在家庭摘要接口失败时降级为空家庭数据', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://ledger.example.com/api/v1'))
        ..httpClientAdapter = _HomeSummaryAdapter();
      final client = ApiClient(
        serverConfigService: ServerConfigService(SecureStorageService()),
        dio: dio,
      );
      final repository = HomeRepository(client);

      final summary = await repository.getSummary();

      expect(summary.accounts.activeAccounts, hasLength(1));
      expect(summary.overview.transactionCount, 6);
      expect(summary.budgetSummary.totalAmount, 3000);
      expect(summary.recentTransactions, hasLength(1));
      expect(summary.familySummary.month, isEmpty);
      expect(summary.familySummary.members, isEmpty);
      expect(summary.familySummary.totalExpense, 0);
    });
  });

  group('核心模型解析', () {
    test('ServerConfig 生成 API 基础地址', () {
      const config = ServerConfig(baseUrl: 'https://ledger.example.com');

      expect(config.apiBaseUrl, 'https://ledger.example.com/api/v1');
    });

    test('ServerConfigService 远程地址必须使用 HTTPS', () {
      final service = ServerConfigService(SecureStorageService());

      expect(
        () => service.normalizeServerUrl('ledger.example.com'),
        returnsNormally,
      );
      expect(
        () => service.normalizeServerUrl('http://ledger.example.com'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('远程账本必须使用 HTTPS'),
          ),
        ),
      );
      expect(
        service.normalizeServerUrl('http://localhost:8080'),
        'http://localhost:8080',
      );
      expect(
        service.normalizeServerUrl('http://127.0.0.1:8080'),
        'http://127.0.0.1:8080',
      );
      expect(
        service.normalizeServerUrl('http://192.168.1.10:8080'),
        'http://192.168.1.10:8080',
      );
    });

    test('AuthTokenPair 解析 token 并校验完整性', () {
      final tokenPair = AuthTokenPair.fromJson({
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
        'expires_in': 3600,
      });

      expect(tokenPair.accessToken, 'access-token');
      expect(tokenPair.refreshToken, 'refresh-token');
      expect(tokenPair.expiresIn, 3600);
      expect(tokenPair.isValid, isTrue);
    });

    test('AuthStatus 拒绝非 Map 响应', () {
      expect(
        () => AuthStatus.fromJson(['invalid']),
        throwsA(isA<FormatException>()),
      );
    });

    test('TransactionListResult 解析分页列表和 hasMore', () {
      final result = TransactionListResult.fromJson({
        'list': [
          {
            'id': 't1',
            'type': 'income',
            'amount': '12.5',
            'account_id': 'a1',
            'category_id': 'c1',
            'transaction_date': '2026-05-14T10:20:00Z',
            'tags': '["工资","五月"]',
          },
        ],
        'total': 30,
        'page': 1,
        'page_size': 20,
      });

      expect(result.list, hasLength(1));
      expect(result.list.first.type, TransactionType.income);
      expect(result.list.first.amount, 12.5);
      expect(result.list.first.source, 'manual');
      expect(result.list.first.isSystemSeed, isFalse);
      expect(
        result.list.first.transactionDate,
        DateTime.parse('2026-05-14T10:20:00Z').toLocal(),
      );
      expect(result.list.first.tags, ['工资', '五月']);
      expect(result.hasMore, isTrue);
    });

    test('TransactionItem 识别系统期初余额流水', () {
      final sourceRow = TransactionItem.fromJson({
        'id': 'system-source',
        'type': 'income',
        'amount': 1000,
        'account_id': 'a1',
        'transaction_date': '2026-05-14T10:20:00Z',
        'source': 'system',
        'remark': '账户初始化',
      });
      final remarkRow = TransactionItem.fromJson({
        'id': 'system-remark',
        'type': 'income',
        'amount': 1000,
        'account_id': 'a1',
        'transaction_date': '2026-05-14T10:20:00Z',
        'source': 'manual',
        'remark': '  期初余额: 现金',
      });

      expect(sourceRow.isSystemSeed, isTrue);
      expect(remarkRow.isSystemSeed, isTrue);
    });

    test('附件路径兼容 JSON 和逗号分隔格式', () {
      expect(decodeAttachmentPaths('["a.jpg","b.pdf"]'), ['a.jpg', 'b.pdf']);
      expect(decodeAttachmentPaths(' a.jpg, b.pdf ,, '), ['a.jpg', 'b.pdf']);
      expect(encodeAttachmentPaths(['a.jpg']), '["a.jpg"]');
    });

    test('统计模型解析概览、趋势和分类排行', () {
      final overview = StatisticsOverviewData.fromJson({
        'income': '1200.50',
        'expense': 300,
        'balance': 900.5,
        'income_change': 12.5,
        'expense_change': '-3.4',
        'daily_average': 10,
        'transaction_count': '6',
      });
      final trend = TrendResponse.fromJson({
        'items': [
          {'date': '2026-05-01', 'income': 100, 'expense': '20'},
        ],
        'total_income': 100,
        'total_expense': '20',
      });
      final categories = CategoryStatResponse.fromJson({
        'total': '88.8',
        'items': [
          {
            'category_id': 'c1',
            'category_name': '餐饮',
            'icon': '🍽️',
            'color': '#EF4444',
            'amount': '88.8',
            'percentage': 100,
            'count': 2,
          },
        ],
      });

      expect(overview.income, 1200.5);
      expect(overview.expenseChange, -3.4);
      expect(overview.transactionCount, 6);
      expect(trend.items.single.expense, 20);
      expect(trend.totalExpense, 20);
      expect(categories.total, 88.8);
      expect(categories.items.single.categoryName, '餐饮');
    });

    test('年度报告模型解析月度数据和分类排行', () {
      final report = YearlyReport.fromJson({
        'year': '2026',
        'total_income': '1000',
        'total_expense': 400,
        'net_savings': 600,
        'savings_rate': 60,
        'monthly_data': [
          {'month': '1月', 'income': 1000, 'expense': '400', 'balance': 600},
        ],
        'top_expenses': [
          {
            'category_id': 'c1',
            'category_name': '餐饮',
            'category_icon': '🍽️',
            'amount': 200,
            'percentage': 50,
            'count': '4',
          },
        ],
        'top_incomes': [],
        'transaction_count': 5,
        'average_expense': 33.33,
        'average_income': 83.33,
        'max_expense_month': '1月',
        'min_expense_month': '1月',
        'best_savings_month': '1月',
        'max_single_expense': '100',
        'max_expense_remark': '晚餐',
        'active_days': 3,
        'daily_avg_expense': 133.33,
      });

      expect(report.year, 2026);
      expect(report.monthlyData.single.expense, 400);
      expect(report.topExpenses.single.categoryName, '餐饮');
      expect(report.topExpenses.single.count, 4);
    });

    test('预算模型解析总预算和分类预算', () {
      final result = BudgetListResponse.fromJson({
        'total_budget': {
          'id': 'total',
          'category_id': null,
          'amount': '3000',
          'spent': 1200,
          'remaining': '1800',
          'percentage': 40,
          'alert_threshold': '80',
        },
        'category_budgets': [
          {
            'id': 'budget-1',
            'category_id': 'cat-1',
            'category_name': '餐饮',
            'amount': 800,
            'spent': '700',
            'remaining': 100,
            'percentage': '87',
            'alert_threshold': 80,
          },
        ],
        'member_budgets': [
          {
            'id': 'member-budget-1',
            'member_id': 'member-1',
            'member_name': '家人',
            'category_id': null,
            'amount': 1000,
            'spent': 420,
            'remaining': 580,
            'percentage': 42,
            'alert_threshold': 80,
          },
        ],
      });

      expect(result.totalBudget?.amount, 3000);
      expect(result.categoryBudgets.single.categoryName, '餐饮');
      expect(result.categoryBudgets.single.percentage, 87);
      expect(result.categoryBudgets.single.isNearLimit, isTrue);
      expect(result.memberBudgets.single.memberName, '家人');
      expect(result.memberBudgets.single.remaining, 580);
    });

    test('家庭统计模型解析成员分类拆分', () {
      final result = FamilyStatistics.fromJson({
        'month': '2026-05',
        'total_expense': '320',
        'members': [
          {
            'member_id': 'member-1',
            'name': '家人',
            'relationship': 'spouse',
            'color': '#2563EB',
            'expense_total': 200,
            'count': 3,
            'categories': [
              {
                'category_id': 'category-food',
                'name': '餐饮',
                'color': '#F97316',
                'amount': '160',
                'count': 2,
              },
            ],
          },
        ],
      });

      expect(result.month, '2026-05');
      expect(result.totalExpense, 320);
      expect(result.members.single.name, '家人');
      expect(result.members.single.categories.single.name, '餐饮');
      expect(result.members.single.categories.single.amount, 160);
    });

    test('负债提醒模型解析摘要和还款进度', () {
      final summary = DebtSummary.fromJson({
        'total_debt': '80000',
        'total_paid': 40000,
        'total_principal': 120000,
        'progress': '33.3',
        'active_loans': 1,
        'paid_off_loans': 0,
        'next_payment_day': 10,
        'next_payment_name': '房贷',
        'days_until_next': '3',
      });
      final reminder = ReminderItem.fromJson({
        'id': 'r1',
        'name': '房贷',
        'loan_type': 'mortgage',
        'payment_day': 10,
        'advance_days': 3,
        'amount': '1000',
        'principal': 120000,
        'current_balance': '80000',
        'total_paid': 40000,
        'interest_paid': 0,
        'is_enabled': true,
        'account': {'id': 'a1', 'name': '贷款账户'},
      });

      expect(summary.totalDebt, 80000);
      expect(summary.daysUntilNext, 3);
      expect(reminder.displayName, '房贷');
      expect(reminder.loanTypeLabel, '房贷');
      expect(reminder.progress, closeTo(33.33, 0.01));
      expect(reminder.accountName, '贷款账户');
    });

    test('借贷模型解析汇总和往来记录', () {
      final summary = LendingSummary.fromJson({
        'total_lend_out': '1000',
        'total_borrow_in': 500,
        'active_lend_out': '1',
        'active_borrow_in': 2,
        'settled_lend_out': 0,
        'settled_borrow_in': '1',
        'total_receivable': '800',
        'total_payable': 400,
        'net_lending': '400',
      });
      final item = LendingItem.fromJson({
        'id': 'lend-1',
        'type': 'lend_out',
        'contact_name': '张三',
        'contact_phone': '13800000000',
        'principal': '1000',
        'interest_rate': '3.5',
        'current_balance': 800,
        'total_repaid': '200',
        'lend_date': '2026-05-01T09:00:00Z',
        'due_date': '2026-06-01T09:00:00Z',
        'remark': '朋友周转',
        'is_settled': false,
        'account': {'id': 'a1', 'name': '现金'},
      });

      expect(summary.totalReceivable, 800);
      expect(summary.activeBorrowIn, 2);
      expect(summary.netLending, 400);
      expect(item.type, LendingType.lendOut);
      expect(item.contactName, '张三');
      expect(item.progress, 20);
      expect(item.accountName, '现金');
      expect(item.typeLabel, '借出');
    });

    test('账户流水模型解析分页和余额变动', () {
      final result = AccountLogListResult.fromJson({
        'list': [
          {
            'id': 'log-1',
            'account_id': 'account-1',
            'type': 'transfer_in',
            'amount': '100',
            'balance_before': 500,
            'balance_after': '600',
            'remark': '转入',
            'created_at': '2026-05-01T09:30:00Z',
            'account': {'id': 'account-1', 'name': '现金'},
          },
        ],
        'total': '12',
        'page': '1',
        'page_size': 10,
      });

      expect(result.list, hasLength(1));
      expect(result.total, 12);
      expect(result.hasMore, isTrue);
      expect(result.list.single.type, AccountLogType.transferIn);
      expect(result.list.single.balanceChange, 100);
      expect(result.list.single.account?.name, '现金');
    });

    test('API Token 模型解析列表和创建结果', () {
      final token = ApiTokenItem.fromJson({
        'id': '3',
        'name': '我的手机',
        'token_prefix': 'abcd1234',
        'last_used_at': null,
        'expires_at': '2026-06-01T09:00:00Z',
        'created_at': '2026-05-01T09:00:00Z',
      });
      final created = ApiTokenCreateResult.fromJson({
        'id': 4,
        'name': 'iPhone',
        'token': 'full-token',
        'token_prefix': 'ffff0000',
        'expires_at': null,
        'created_at': '2026-05-02T09:00:00Z',
      });

      expect(token.id, 3);
      expect(token.name, '我的手机');
      expect(token.tokenPrefix, 'abcd1234');
      expect(token.neverExpires, isFalse);
      expect(created.token, 'full-token');
      expect(created.neverExpires, isTrue);
    });

    test('个人资料模型解析显示名和登录时间', () {
      final profile = UserProfile.fromJson({
        'id': '1',
        'username': 'admin',
        'nickname': 'Sky',
        'email': 'sky@example.com',
        'avatar': 'https://example.com/a.png',
        'bio': '记账中',
        'created_at': '2026-05-01',
        'last_login_at': '2026-05-17 09:00:00',
      });

      expect(profile.id, 1);
      expect(profile.displayName, 'Sky');
      expect(profile.email, 'sky@example.com');
      expect(profile.lastLoginAt, '2026-05-17 09:00:00');
    });

    test('标签模型解析系统状态和使用次数', () {
      final tag = TagItem.fromJson({
        'id': 'tag-1',
        'user_id': '1',
        'name': '工资收入',
        'color': '#22C55E',
        'icon': 'wallet',
        'is_system': true,
        'used_count': '8',
        'created_at': '2026-05-01T09:00:00Z',
      });

      expect(tag.id, 'tag-1');
      expect(tag.userId, 1);
      expect(tag.name, '工资收入');
      expect(tag.icon, 'wallet');
      expect(tag.isSystem, isTrue);
      expect(tag.usedCount, 8);
      expect(tag.sourceLabel, '系统标签');
    });

    test('快捷模板模型解析类型、金额和使用次数', () {
      final template = QuickTemplateItem.fromJson({
        'id': 'tpl-1',
        'user_id': 1,
        'name': '午餐',
        'type': 'expense',
        'amount': '32.5',
        'account_id': 'account-1',
        'category_id': 'category-1',
        'remark': '工作日午餐',
        'used_count': '4',
        'last_used_at': '2026-05-18T12:00:00Z',
      });

      expect(template.id, 'tpl-1');
      expect(template.type, TransactionType.expense);
      expect(template.typeLabel, '支出');
      expect(template.amount, 32.5);
      expect(template.usedCount, 4);
      expect(template.lastUsedAt, isNotNull);
    });

    test('安全入口模型解析启用状态和路径', () {
      final enabled = SecurityEntryPath.fromJson({
        'entry_path': '/ledger',
        'enabled': true,
        'message': 'updated',
      });
      final disabled = SecurityEntryPath.fromJson({
        'entry_path': '',
        'enabled': false,
      });

      expect(enabled.entryPath, '/ledger');
      expect(enabled.enabled, isTrue);
      expect(enabled.displayPath, '/ledger');
      expect(disabled.enabled, isFalse);
      expect(disabled.displayPath, '未启用');
    });

    test('通知设置模型解析通道配置和测试结果', () {
      final setting = NotificationSetting.fromJson({
        'id': 1,
        'user_id': 1,
        'enabled': true,
        'wecom_enabled': true,
        'wecom_webhook': 'https://qyapi.example.com/send?key=test',
        'dingtalk_enabled': false,
        'dingtalk_webhook': '',
        'dingtalk_secret': '',
        'email_enabled': true,
        'smtp_host': 'smtp.example.com',
        'smtp_port': '587',
        'smtp_user': 'bot@example.com',
        'smtp_from': 'ledger@example.com',
        'email_to': 'me@example.com',
        'webhook_enabled': false,
        'webhook_url': '',
        'webhook_secret': '',
        'notify_payment_due': true,
        'notify_budget_alert': false,
        'notify_lending_due': true,
        'notify_annual_report': true,
        'advance_days': '5',
      });
      final result = TestNotificationResult.fromJson({
        'success': true,
        'message': '发送成功',
      });

      expect(setting.enabled, isTrue);
      expect(setting.wecomEnabled, isTrue);
      expect(setting.smtpPort, 587);
      expect(setting.notifyBudgetAlert, isFalse);
      expect(setting.advanceDays, 5);
      expect(result.success, isTrue);
      expect(result.message, '发送成功');
    });
  });
}

class _FailingNetworkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message:
          'Connection refused for https://ledger.example.com/api/v1/health?token=secret',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _HomeSummaryAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final payload = switch (options.path) {
      '/accounts' => _jsonPayload({
        'code': 0,
        'message': 'ok',
        'data': {
          'list': [
            {
              'id': 'account-1',
              'name': '现金',
              'type': 'cash',
              'icon': '💰',
              'color': '#10B981',
              'current_balance': 1280,
              'is_archived': false,
            },
          ],
          'total_assets': 1280,
          'total_liabilities': 0,
          'net_assets': 1280,
        },
      }),
      '/statistics/overview' => _jsonPayload({
        'code': 0,
        'message': 'ok',
        'data': {
          'income': 1600,
          'expense': 420,
          'balance': 1180,
          'transaction_count': 6,
        },
      }),
      '/budgets/summary' => _jsonPayload({
        'code': 0,
        'message': 'ok',
        'data': {
          'total_amount': 3000,
          'total_spent': 1200,
          'percentage': 40,
          'daily_available': 90,
          'days_remaining': 20,
          'over_budget_categories': [],
        },
      }),
      '/transactions' => _jsonPayload({
        'code': 0,
        'message': 'ok',
        'data': {
          'list': [
            {
              'id': 'tx-1',
              'type': 'expense',
              'amount': 28,
              'account_id': 'account-1',
              'category_id': 'category-food',
              'transaction_date': '2026-05-20T09:00:00Z',
              'remark': '午餐',
              'account': {'id': 'account-1', 'name': '现金', 'type': 'cash'},
              'category': {
                'id': 'category-food',
                'name': '餐饮',
                'type': 'expense',
              },
            },
          ],
          'total': 1,
          'page': 1,
          'page_size': 5,
        },
      }),
      '/family/summary' => throw DioException(
        requestOptions: options,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: 404,
          data: 'page not found',
        ),
        type: DioExceptionType.badResponse,
      ),
      _ => _jsonPayload({
        'code': 404,
        'message': 'not found',
        'data': null,
      }, statusCode: 404),
    };

    return payload;
  }

  ResponseBody _jsonPayload(Map<String, Object?> data, {int statusCode = 200}) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
