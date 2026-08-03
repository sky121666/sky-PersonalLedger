/// Formats a monetary value with a stable sign, currency symbol, thousands
/// separators, and fixed decimal precision.
String formatMoney(
  num value, {
  String currencySymbol = '¥',
  int decimalDigits = 2,
  bool showPositiveSign = false,
}) {
  if (!value.isFinite) {
    return '—';
  }
  if (decimalDigits < 0 || decimalDigits > 20) {
    throw RangeError.range(decimalDigits, 0, 20, 'decimalDigits');
  }

  final normalized = value == 0 ? 0 : value;
  final fixed = normalized.abs().toStringAsFixed(decimalDigits);
  final parts = fixed.split('.');
  final integer = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < integer.length; index++) {
    if (index > 0 && (integer.length - index) % 3 == 0) {
      grouped.write(',');
    }
    grouped.write(integer[index]);
  }

  final sign = normalized < 0
      ? '-'
      : showPositiveSign && normalized > 0
      ? '+'
      : '';
  final fraction = decimalDigits == 0 ? '' : '.${parts.last}';
  return '$sign$currencySymbol$grouped$fraction';
}
