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

  String get platformValue {
    return switch (this) {
      QuickLedgerDraftSource.androidNotification => 'android_notification',
      QuickLedgerDraftSource.iosShortcut => 'ios_shortcut',
      QuickLedgerDraftSource.share => 'share',
      QuickLedgerDraftSource.ocr => 'ocr',
    };
  }

  static QuickLedgerDraftSource fromPlatformValue(String value) {
    return switch (value) {
      'ios_shortcut' => QuickLedgerDraftSource.iosShortcut,
      'share' => QuickLedgerDraftSource.share,
      'ocr' => QuickLedgerDraftSource.ocr,
      _ => QuickLedgerDraftSource.androidNotification,
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

  factory QuickLedgerDraft.fromJson(Map<String, dynamic> json) {
    final occurredAtRaw = json['occurred_at'];
    final occurredAt = occurredAtRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(occurredAtRaw)
        : DateTime.tryParse('${json['occurred_at']}') ?? DateTime.now();
    return QuickLedgerDraft(
      id: json['id'] as String? ?? '',
      source: QuickLedgerDraftSource.fromPlatformValue(
        json['source'] as String? ?? '',
      ),
      sourceName: json['source_name'] as String? ?? '支付通知',
      type: TransactionType.fromValue(json['type'] as String? ?? 'expense'),
      amount: _toDouble(json['amount']),
      merchant: json['merchant'] as String? ?? '未识别商户',
      occurredAt: occurredAt,
      confidence: _toDouble(json['confidence']),
      suggestedAccountId: json['suggested_account_id'] as String?,
      suggestedAccountName: json['suggested_account_name'] as String? ?? '',
      suggestedCategoryId: json['suggested_category_id'] as String?,
      suggestedCategoryName: json['suggested_category_name'] as String? ?? '',
      rawText: json['raw_text'] as String? ?? '',
      notificationHash: json['notification_hash'] as String? ?? '',
    );
  }
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}
