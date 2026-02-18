import 'package:flutter_test/flutter_test.dart';
import 'package:mini_pos_inventory/core/utils/money_calculator.dart';

void main() {
  group('MoneyCalculator', () {
    test('line total applies quantity and item discount', () {
      final total = MoneyCalculator.lineTotal(
        unitPrice: 25,
        qty: 3,
        itemDiscount: 10,
      );

      expect(total, 65);
    });

    test('line total never goes negative', () {
      final total = MoneyCalculator.lineTotal(
        unitPrice: 10,
        qty: 1,
        itemDiscount: 20,
      );

      expect(total, 0);
    });

    test('subtotal sums line totals with rounding', () {
      final subtotal = MoneyCalculator.subtotal([10.105, 20.106, 5.004]);

      expect(subtotal, 35.22);
    });

    test('tax is zero when disabled', () {
      final tax = MoneyCalculator.tax(
        taxableAmount: 100,
        taxEnabled: false,
        taxRate: 0.14,
      );

      expect(tax, 0);
    });

    test('order total applies order discount and tax', () {
      final total = MoneyCalculator.orderTotal(
        subtotal: 200,
        orderDiscount: 15,
        tax: 25.9,
      );

      expect(total, 210.9);
    });

    test('profit for line uses snapshot prices and discount', () {
      final profit = MoneyCalculator.profitForLine(
        priceSnapshot: 40,
        costSnapshot: 25,
        qty: 4,
        discount: 6,
      );

      expect(profit, 54);
    });
  });
}
