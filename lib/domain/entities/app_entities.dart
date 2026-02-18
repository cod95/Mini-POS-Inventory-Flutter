import 'package:equatable/equatable.dart';

import '../../core/models/app_models.dart';

class ProductView extends Equatable {
  const ProductView({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.categoryId,
    required this.categoryName,
    required this.cost,
    required this.price,
    required this.stockQty,
    required this.lowStockThreshold,
    required this.unit,
    required this.notes,
    this.imagePath,
  });

  final int id;
  final String name;
  final String sku;
  final String? barcode;
  final int? categoryId;
  final String? categoryName;
  final double cost;
  final double price;
  final int stockQty;
  final int lowStockThreshold;
  final String unit;
  final String? notes;
  final String? imagePath;

  bool get isLowStock => stockQty <= lowStockThreshold;

  @override
  List<Object?> get props => [
        id,
        name,
        sku,
        barcode,
        categoryId,
        categoryName,
        cost,
        price,
        stockQty,
        lowStockThreshold,
        unit,
        notes,
        imagePath,
      ];
}

class SaleItemView extends Equatable {
  const SaleItemView({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.nameSnapshot,
    required this.costSnapshot,
    required this.priceSnapshot,
    required this.qty,
    required this.discount,
    required this.lineTotal,
  });

  final int id;
  final int saleId;
  final int productId;
  final String nameSnapshot;
  final double costSnapshot;
  final double priceSnapshot;
  final int qty;
  final double discount;
  final double lineTotal;

  @override
  List<Object?> get props => [
        id,
        saleId,
        productId,
        nameSnapshot,
        costSnapshot,
        priceSnapshot,
        qty,
        discount,
        lineTotal,
      ];
}

class SaleView extends Equatable {
  const SaleView({
    required this.id,
    required this.invoiceNo,
    required this.createdAt,
    required this.customerId,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
    required this.paid,
    required this.changeAmount,
    required this.paymentMethod,
    required this.status,
  });

  final int id;
  final String invoiceNo;
  final DateTime createdAt;
  final int? customerId;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final double paid;
  final double changeAmount;
  final PaymentMethod paymentMethod;
  final SaleStatus status;

  @override
  List<Object?> get props => [
        id,
        invoiceNo,
        createdAt,
        customerId,
        subtotal,
        discountTotal,
        taxTotal,
        total,
        paid,
        changeAmount,
        paymentMethod,
        status,
      ];
}

class SaleDetailView extends Equatable {
  const SaleDetailView({required this.sale, required this.items});

  final SaleView sale;
  final List<SaleItemView> items;

  @override
  List<Object?> get props => [sale, items];
}

class AuthSession extends Equatable {
  const AuthSession({required this.role, required this.loginTime});

  final UserRole role;
  final DateTime loginTime;

  @override
  List<Object?> get props => [role, loginTime];
}
