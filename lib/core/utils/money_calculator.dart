import 'dart:math';

class MoneyCalculator {
  const MoneyCalculator._();

  static double round2(double value) => (value * 100).roundToDouble() / 100;

  static double lineTotal({
    required double unitPrice,
    required int qty,
    required double itemDiscount,
  }) {
    final raw = (unitPrice * qty) - itemDiscount;
    return round2(max(0, raw));
  }

  static double subtotal(List<double> lineTotals) {
    return round2(lineTotals.fold(0, (sum, line) => sum + line));
  }

  static double tax({
    required double taxableAmount,
    required bool taxEnabled,
    required double taxRate,
  }) {
    if (!taxEnabled) {
      return 0;
    }
    return round2(max(0, taxableAmount) * taxRate);
  }

  static double orderTotal({
    required double subtotal,
    required double orderDiscount,
    required double tax,
  }) {
    final raw = subtotal - orderDiscount + tax;
    return round2(max(0, raw));
  }

  static double profitForLine({
    required double priceSnapshot,
    required double costSnapshot,
    required int qty,
    required double discount,
  }) {
    final gross = (priceSnapshot - costSnapshot) * qty;
    return round2(gross - discount);
  }
}
