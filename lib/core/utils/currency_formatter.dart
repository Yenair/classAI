/// NGN (Naira) currency formatting utilities.
///
/// Formats amounts as NGN currency strings with proper Nigerian locale:
/// - `₦5,000.00` for 5000
/// - `₦1,250.50` for 1250.50
/// - `₦0.00` for 0
///
/// The Nigerian currency code is NGN and the symbol is ₦.
/// Paystack uses kobo (1 NGN = 100 kobo), so amounts in kobo
/// are divided by 100 before formatting.
class CurrencyFormatter {
  /// Format an amount in Naira (NGN) as a display string.
  ///
  /// Example: `formatNaira(5000)` returns `"₦5,000.00"`
  static String formatNaira(num amount) {
    final isNegative = amount < 0;
    final absolute = amount.abs();
    final whole = absolute.floor();
    final fraction = ((absolute - whole) * 100).round();

    // Format with thousands separator
    final wholeStr = _formatWithCommas(whole);
    final fractionStr = fraction.toString().padLeft(2, '0');

    return '${isNegative ? '-' : ''}₦$wholeStr.$fractionStr';
  }

  /// Format an amount in kobo (Paystack units) as NGN display string.
  ///
  /// Example: `formatKobo(500000)` returns `"₦5,000.00"`
  static String formatKobo(int kobo) {
    return formatNaira(kobo / 100);
  }

  /// Format an amount as compact NGN (no decimal for round numbers).
  ///
  /// Example: `formatNairaCompact(5000)` returns `"₦5,000"`
  /// Example: `formatNairaCompact(1250.50)` returns `"₦1,250.50"`
  static String formatNairaCompact(num amount) {
    final isNegative = amount < 0;
    final absolute = amount.abs();
    final whole = absolute.floor();
    final fraction = ((absolute - whole) * 100).round();
    final wholeStr = _formatWithCommas(whole);

    if (fraction == 0) {
      return '${isNegative ? '-' : ''}₦$wholeStr';
    }
    final fractionStr = fraction.toString().padLeft(2, '0');
    return '${isNegative ? '-' : ''}₦$wholeStr.$fractionStr';
  }

  /// Convert Naira amount to kobo (for Paystack API).
  static int toKobo(num amountNaira) {
    return (amountNaira * 100).round();
  }

  /// Convert kobo amount to Naira.
  static double toNaira(int kobo) {
    return kobo / 100.0;
  }

  /// Format with thousands commas.
  static String _formatWithCommas(int value) {
    final str = value.toString();
    if (str.length <= 3) return str;

    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
      count++;
    }
    return buffer.toString().split('').reversed.join('');
  }
}
