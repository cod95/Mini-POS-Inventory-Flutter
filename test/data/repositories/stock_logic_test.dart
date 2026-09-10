import 'package:flutter_test/flutter_test.dart';
import 'package:mini_pos_inventory/core/models/app_models.dart';

int applyStockMovementQty({
  required int currentQty,
  required StockMovementType type,
  required int qtyChange,
}) {
  var newQty = currentQty + qtyChange;
  if (type == StockMovementType.adjust) {
    newQty = qtyChange;
  }
  if (newQty < 0) {
    throw StateError('Stock cannot be negative');
  }
  return newQty;
}

int applySaleStockQty({
  required int currentQty,
  required int soldQty,
  required bool allowNegativeStock,
}) {
  if (!allowNegativeStock && currentQty < soldQty) {
    throw StateError('Insufficient stock');
  }
  return currentQty - soldQty;
}

void main() {
  group('Stock movement logic', () {
    test('add movement increases stock', () {
      final result = applyStockMovementQty(
        currentQty: 10,
        type: StockMovementType.add,
        qtyChange: 5,
      );

      expect(result, 15);
    });

    test('remove movement decreases stock', () {
      final result = applyStockMovementQty(
        currentQty: 10,
        type: StockMovementType.remove,
        qtyChange: -3,
      );

      expect(result, 7);
    });

    test('adjust movement sets absolute quantity', () {
      final result = applyStockMovementQty(
        currentQty: 50,
        type: StockMovementType.adjust,
        qtyChange: 12,
      );

      expect(result, 12);
    });

    test('movement throws when resulting stock is negative', () {
      expect(
        () => applyStockMovementQty(
          currentQty: 2,
          type: StockMovementType.remove,
          qtyChange: -5,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Sale stock update logic', () {
    test('sale decreases stock when enough quantity exists', () {
      final result = applySaleStockQty(
        currentQty: 20,
        soldQty: 6,
        allowNegativeStock: false,
      );

      expect(result, 14);
    });

    test('sale blocks insufficient stock when negative stock is disabled', () {
      expect(
        () => applySaleStockQty(
          currentQty: 1,
          soldQty: 2,
          allowNegativeStock: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('sale allows negative stock when enabled', () {
      final result = applySaleStockQty(
        currentQty: 1,
        soldQty: 3,
        allowNegativeStock: true,
      );

      expect(result, -2);
    });
  });
}
