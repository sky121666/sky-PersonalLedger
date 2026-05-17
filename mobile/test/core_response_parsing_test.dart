import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/auth/auth_token_pair.dart';
import 'package:personal_ledger/core/config/server_config_service.dart';
import 'package:personal_ledger/core/network/api_exception.dart';
import 'package:personal_ledger/core/network/api_response.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/auth/data/auth_repository.dart';
import 'package:personal_ledger/features/budgets/data/budget_repository.dart';
import 'package:personal_ledger/features/lendings/data/lending_repository.dart';
import 'package:personal_ledger/features/reminders/data/reminder_repository.dart';
import 'package:personal_ledger/features/reports/data/yearly_report_models.dart';
import 'package:personal_ledger/features/statistics/data/statistics_models.dart';
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

  group('核心模型解析', () {
    test('ServerConfig 生成 API 基础地址', () {
      const config = ServerConfig(baseUrl: 'https://ledger.example.com');

      expect(config.apiBaseUrl, 'https://ledger.example.com/api/v1');
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
      expect(result.list.first.tags, ['工资', '五月']);
      expect(result.hasMore, isTrue);
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
      });

      expect(result.totalBudget?.amount, 3000);
      expect(result.categoryBudgets.single.categoryName, '餐饮');
      expect(result.categoryBudgets.single.percentage, 87);
      expect(result.categoryBudgets.single.isNearLimit, isTrue);
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
  });
}
