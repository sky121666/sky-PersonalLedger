import '../../transactions/data/transaction_models.dart';
import 'quick_ledger_draft.dart';

/// Parses pasted payment text locally. It intentionally requires an explicit
/// income/expense cue so arbitrary numbers (balances, OTP codes, dates) do not
/// become ledger candidates.
class QuickLedgerTextParser {
  const QuickLedgerTextParser._();

  static final _amountPattern = RegExp(
    r'(?:¥|￥)?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(?:元)?',
  );
  static const _incomeWords = ['收款', '到账', '收入', '转入', '退款', '退回', '收到'];
  static const _expenseWords = ['付款', '支付', '消费', '扣款', '支出', '转出'];
  static const _balanceWords = ['余额', '可用', '剩余'];

  static QuickLedgerDraft? parse(String rawText, {DateTime? occurredAt}) {
    final text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      return null;
    }
    final type = _inferType(text);
    if (type == null) {
      return null;
    }
    final amountCandidate = _findAmount(text, type);
    if (amountCandidate == null || amountCandidate.amount <= 0) {
      return null;
    }
    final merchant = _inferMerchant(text, amountCandidate);
    final timestamp = occurredAt ?? DateTime.now();
    final hash = _stableHash(text);
    final hasExplicitMerchant = text.contains('商户') || text.contains('收款方');

    return QuickLedgerDraft(
      id: 'manual-$hash',
      source: QuickLedgerDraftSource.manualPaste,
      sourceName: '文本导入',
      type: type,
      amount: amountCandidate.amount,
      merchant: merchant,
      occurredAt: timestamp,
      confidence: hasExplicitMerchant
          ? 0.88
          : merchant == '待确认交易'
          ? 0.68
          : 0.8,
      rawText: text,
      notificationHash: hash,
    );
  }

  static TransactionType? _inferType(String text) {
    if (_incomeWords.any(text.contains)) {
      return TransactionType.income;
    }
    if (_expenseWords.any(text.contains)) {
      return TransactionType.expense;
    }
    return null;
  }

  static _AmountCandidate? _findAmount(String text, TransactionType type) {
    final directionalWords = type == TransactionType.income
        ? _incomeWords
        : _expenseWords;
    _AmountCandidate? best;
    for (final match in _amountPattern.allMatches(text)) {
      final amount = double.tryParse(
        (match.group(1) ?? '').replaceAll(',', ''),
      );
      if (amount == null || amount <= 0) {
        continue;
      }
      final before = text.substring(
        (match.start - 14).clamp(0, text.length),
        match.start,
      );
      final after = text.substring(
        match.end,
        (match.end + 15).clamp(0, text.length),
      );
      final afterWithoutUnit = after
          .trimLeft()
          .replaceFirst('元', '')
          .trimLeft();
      final isBalance =
          RegExp(r'(?:余额|可用|剩余)\s*[:：]?\s*[¥￥]?\s*$').hasMatch(before) ||
          _balanceWords.any(afterWithoutUnit.startsWith);
      if (isBalance || _looksLikeDateOrTime(text, match)) {
        continue;
      }
      final hasDirectionalCue = directionalWords.any(
        (word) => before.contains(word) || after.contains(word),
      );
      final matchedText = match.group(0) ?? '';
      final amountToken = match.group(1) ?? '';
      final hasCurrencyUnit =
          matchedText.contains('¥') ||
          matchedText.contains('￥') ||
          matchedText.trimRight().endsWith('元');
      final hasAmountLabel = const [
        '金额',
        '实付',
        '合计',
      ].any((label) => before.contains(label) || after.startsWith(label));
      final hasUnlabeledDecimalAmount =
          hasDirectionalCue && amountToken.contains('.');
      if (!hasCurrencyUnit && !hasAmountLabel && !hasUnlabeledDecimalAmount) {
        continue;
      }
      final candidate = _AmountCandidate(
        amount: amount,
        score:
            (hasDirectionalCue ? 4 : 0) +
            (hasCurrencyUnit ? 4 : 0) +
            (hasAmountLabel ? 3 : 0),
        index: match.start,
        matchedText: matchedText,
      );
      if (best == null ||
          candidate.score > best.score ||
          (candidate.score == best.score && candidate.index < best.index)) {
        best = candidate;
      }
    }
    return best;
  }

  static bool _looksLikeDateOrTime(String text, RegExpMatch match) {
    final previous = match.start > 0 ? text[match.start - 1] : '';
    final next = match.end < text.length ? text[match.end] : '';
    return previous == '-' ||
        previous == '/' ||
        previous == ':' ||
        next == '-' ||
        next == '/' ||
        next == ':';
  }

  static String _inferMerchant(String text, _AmountCandidate amount) {
    final explicit = RegExp(
      r'(?:商户|收款方)\s*[:：]?\s*([^，,。;；]{2,32})',
    ).firstMatch(text)?.group(1);
    if (explicit != null) {
      final cleaned = _cleanMerchant(explicit, amount);
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }
    final cleaned = _cleanMerchant(text, amount);
    return cleaned.isEmpty ? '待确认交易' : cleaned;
  }

  static String _cleanMerchant(String value, _AmountCandidate amount) {
    final cleaned = value
        .replaceFirst(amount.matchedText, ' ')
        .replaceAll(RegExp(r'(?:交易)?金额|实付|合计'), ' ')
        .replaceAll(RegExp(r'\d{4}[-/]\d{1,2}[-/]\d{1,2}'), ' ')
        .replaceAll(RegExp(r'\d{1,2}:\d{2}(?::\d{2})?'), ' ')
        .replaceAll(
          RegExp(
            r'(微信支付|支付宝|银行|云闪付|付款成功|支付成功|付款|支付|消费|扣款|收款|到账|收入|支出|退款|退回|收到|转入|转出|转账|通知|提醒|(?:您)?向|给|您已|本次)',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'(余额|可用|剩余)\s*[:：]?\s*[¥￥]?[0-9.,]+.*$'), ' ')
        .replaceAll(RegExp(r'[：:，,。;；|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.substring(0, _min(24, cleaned.length));
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static int _min(int left, int right) => left < right ? left : right;
}

class _AmountCandidate {
  const _AmountCandidate({
    required this.amount,
    required this.score,
    required this.index,
    required this.matchedText,
  });

  final double amount;
  final int score;
  final int index;
  final String matchedText;
}
