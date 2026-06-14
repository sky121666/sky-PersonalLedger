import '../../transactions/data/transaction_models.dart';

enum QuickLedgerDraftSource {
  androidNotification,
  iosShortcut,
  share,
  ocr;

  String get label {
    return switch (this) {
      QuickLedgerDraftSource.androidNotification => '通知',
      QuickLedgerDraftSource.iosShortcut => '快捷指令',
      QuickLedgerDraftSource.share => '分享导入',
      QuickLedgerDraftSource.ocr => '截图识别',
    };
  }
}

class QuickLedgerDraft {
  const QuickLedgerDraft({
    required this.id,
    required this.source,
    required this.sourceName,
    required this.type,
    required this.amount,
    required this.merchant,
    required this.occurredAt,
    required this.confidence,
    this.suggestedAccountId,
    this.suggestedAccountName = '',
    this.suggestedCategoryId,
    this.suggestedCategoryName = '',
    this.rawText = '',
    this.notificationHash = '',
  });

  final String id;
  final QuickLedgerDraftSource source;
  final String sourceName;
  final TransactionType type;
  final double amount;
  final String merchant;
  final DateTime occurredAt;
  final double confidence;
  final String? suggestedAccountId;
  final String suggestedAccountName;
  final String? suggestedCategoryId;
  final String suggestedCategoryName;
  final String rawText;
  final String notificationHash;

  String get typeLabel => type.label;

  bool get isHighConfidence => confidence >= 0.85;

  TransactionFormData toFormData({
    required String accountId,
    String? categoryId,
  }) {
    return TransactionFormData(
      type: type,
      amount: amount,
      accountId: accountId,
      categoryId: type == TransactionType.transfer ? null : categoryId,
      transactionDate: occurredAt,
      remark: merchant,
      tags: [source.label],
    );
  }
}
