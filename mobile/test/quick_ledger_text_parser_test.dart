import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_draft.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_repository.dart';
import 'package:personal_ledger/features/smart_quick_ledger/data/quick_ledger_text_parser.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';

void main() {
  group('QuickLedgerTextParser', () {
    test('识别支出金额和商户', () {
      final draft = QuickLedgerTextParser.parse(
        '微信支付 向瑞幸咖啡付款 38.90 元',
        occurredAt: DateTime(2026, 7, 31, 9, 30),
      );

      expect(draft, isNotNull);
      expect(draft?.type, TransactionType.expense);
      expect(draft?.amount, 38.9);
      expect(draft?.merchant, '瑞幸咖啡');
      expect(draft?.source, QuickLedgerDraftSource.manualPaste);
    });

    test('识别收入金额', () {
      final draft = QuickLedgerTextParser.parse('支付宝收款到账 88.66 元');

      expect(draft, isNotNull);
      expect(draft?.type, TransactionType.income);
      expect(draft?.amount, 88.66);
    });

    test('优先提取交易金额并排除余额', () {
      final draft = QuickLedgerTextParser.parse(
        '微信支付 付款 38.90 元，余额 1,234.56 元',
      );

      expect(draft, isNotNull);
      expect(draft?.type, TransactionType.expense);
      expect(draft?.amount, 38.9);
    });

    test('支持千分位金额', () {
      final draft = QuickLedgerTextParser.parse('银行收入到账 ¥12,345.67 元');

      expect(draft, isNotNull);
      expect(draft?.type, TransactionType.income);
      expect(draft?.amount, 12345.67);
    });

    test('没有收支方向词时拒绝生成候选', () {
      final draft = QuickLedgerTextParser.parse('账户余额 1,234.56 元');

      expect(draft, isNull);
    });

    test('不会把日期或支付验证码当作金额', () {
      final datedDraft = QuickLedgerTextParser.parse(
        '支付通知 2026-07-31，商户：瑞幸咖啡，金额 38.90 元',
      );

      expect(datedDraft, isNotNull);
      expect(datedDraft?.amount, 38.9);
      expect(QuickLedgerTextParser.parse('支付验证码 123456，请勿泄露'), isNull);
    });

    test('重复导入同一文本只保留一个候选', () {
      final controller = QuickLedgerDraftController(
        transactionWriter: _UnusedQuickLedgerWriter(),
      );
      addTearDown(controller.dispose);

      final first = controller.importText(' 微信支付   付款 18.00 元 ');
      final second = controller.importText('微信支付 付款 18.00 元');

      expect(second.id, first.id);
      expect(controller.state, hasLength(1));
      expect(controller.state.single.id, first.id);
      expect(controller.state.single.amount, 18);
    });
  });
}

class _UnusedQuickLedgerWriter implements QuickLedgerTransactionWriter {
  @override
  Future<List<LedgerAccount>> listAccounts() async => const [];

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async => const [];

  @override
  Future<TransactionItem> create(TransactionFormData formData) {
    throw UnsupportedError('重复导入测试不应创建交易');
  }
}
