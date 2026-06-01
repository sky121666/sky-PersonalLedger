import 'package:flutter/material.dart';

class LedgerIcon extends StatelessWidget {
  const LedgerIcon({
    required this.icon,
    super.key,
    this.size = 20,
    this.color,
    this.fallback = Icons.account_balance_wallet_outlined,
    this.semanticLabel,
  });

  final String icon;
  final double size;
  final Color? color;
  final IconData fallback;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final value = icon.trim();
    final Widget iconWidget;
    if (_isEmojiIcon(value)) {
      iconWidget = Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: size, height: 1),
      );
    } else {
      iconWidget = Icon(
        _ledgerIconData(value, fallback),
        size: size,
        color: color,
      );
    }
    final label = semanticLabel?.trim();
    if (label == null || label.isEmpty) {
      return iconWidget;
    }
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: iconWidget),
    );
  }
}

class LedgerIconLabel extends StatelessWidget {
  const LedgerIconLabel({
    required this.icon,
    required this.label,
    super.key,
    this.fallback = Icons.category_outlined,
    this.semanticLabel,
  });

  final String icon;
  final String label;
  final IconData fallback;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveLabel = semanticLabel?.trim().isNotEmpty == true
        ? semanticLabel!.trim()
        : label;
    return Semantics(
      label: effectiveLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LedgerIcon(icon: icon, size: 18, fallback: fallback),
            const SizedBox(width: 8),
            Text(label, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

IconData _ledgerIconData(String icon, IconData fallback) {
  return switch (icon) {
    'banknote' || 'banknot' || 'cash' => Icons.payments_outlined,
    'landmark' || 'bank_card' || 'savings' => Icons.account_balance_outlined,
    'credit-card' || 'credit_card' || 'credit' => Icons.credit_card,
    'circle-dot' || 'alipay' => Icons.radio_button_checked,
    'message-circle' || 'wechat' => Icons.chat_bubble_outline,
    'message-square' || 'qq_pay' => Icons.chat_outlined,
    'shopping-bag' ||
    'jd_pay' ||
    'consumer_loan' => Icons.shopping_bag_outlined,
    'smartphone' || 'apple_pay' => Icons.smartphone_outlined,
    'flower-2' || 'huabei' => Icons.local_florist_outlined,
    'scroll' || 'baitiao' => Icons.receipt_long_outlined,
    'building-2' || 'loan' => Icons.account_balance,
    'home' || 'house' || 'mortgage' => Icons.house_outlined,
    'car' || 'car_loan' => Icons.directions_car_outlined,
    'wallet' ||
    'payable' ||
    'receivable' => Icons.account_balance_wallet_outlined,
    'trending-up' || 'investment' => Icons.trending_up,
    'pie-chart' || 'fund' => Icons.pie_chart_outline,
    'bar-chart-2' || 'stock' => Icons.bar_chart,
    'bitcoin' || 'crypto' => Icons.currency_bitcoin,
    'ticket' || 'prepaid' => Icons.confirmation_number_outlined,
    'clipboard-list' => Icons.checklist_outlined,
    'file-text' => Icons.description_outlined,
    'repeat' => Icons.repeat,
    'receipt' => Icons.receipt_long_outlined,
    'calendar' => Icons.calendar_month_outlined,
    'star' => Icons.star_outline,
    'label' => Icons.label_outline,
    _ => fallback,
  };
}

bool _isEmojiIcon(String value) {
  if (value.isEmpty) {
    return false;
  }
  return value.runes.any(_isEmojiRune);
}

bool _isEmojiRune(int rune) {
  return (rune >= 0x1F000 && rune <= 0x1FAFF) ||
      (rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x2300 && rune <= 0x23FF) ||
      rune == 0x2B50 ||
      rune == 0x2B55 ||
      rune == 0x3030 ||
      rune == 0x303D ||
      rune == 0x3297 ||
      rune == 0x3299;
}
