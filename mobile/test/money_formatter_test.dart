import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/core/formatters/money_formatter.dart';

void main() {
  group('formatMoney', () {
    test('uses stable currency and thousands separators', () {
      expect(formatMoney(13995.5), '¥13,995.50');
      expect(formatMoney(1234567.891), '¥1,234,567.89');
    });

    test('places signs before the currency symbol', () {
      expect(formatMoney(-1200), '-¥1,200.00');
      expect(formatMoney(1200, showPositiveSign: true), '+¥1,200.00');
      expect(formatMoney(-0.0, showPositiveSign: true), '¥0.00');
    });

    test('supports custom currency and precision', () {
      expect(
        formatMoney(1234.5, currencySymbol: r'$', decimalDigits: 0),
        r'$1,235',
      );
      expect(
        formatMoney(1234.5, currencySymbol: '', decimalDigits: 1),
        '1,234.5',
      );
    });

    test('does not expose non-finite values to the UI', () {
      expect(formatMoney(double.nan), '—');
      expect(formatMoney(double.infinity), '—');
    });

    test('rejects unsupported decimal precision', () {
      expect(() => formatMoney(1, decimalDigits: -1), throwsRangeError);
      expect(() => formatMoney(1, decimalDigits: 21), throwsRangeError);
    });
  });
}
