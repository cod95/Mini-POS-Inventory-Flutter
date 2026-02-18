import 'package:equatable/equatable.dart';

enum UserRole { admin, cashier }

enum StockMovementType { add, remove, adjust, purchase, sale, returnSale }

enum PaymentMethod { cash, card, split }

enum SaleStatus { completed, returned }

extension PaymentMethodX on PaymentMethod {
  String get value {
    switch (this) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.split:
        return 'split';
    }
  }

  static PaymentMethod fromValue(String value) {
    return PaymentMethod.values.firstWhere(
      (method) => method.value == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

extension SaleStatusX on SaleStatus {
  String get value {
    switch (this) {
      case SaleStatus.completed:
        return 'completed';
      case SaleStatus.returned:
        return 'returned';
    }
  }

  static SaleStatus fromValue(String value) {
    return SaleStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => SaleStatus.completed,
    );
  }
}

extension UserRoleX on UserRole {
  String get value {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.cashier:
        return 'cashier';
    }
  }

  static UserRole fromValue(String value) {
    return UserRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => UserRole.cashier,
    );
  }
}

extension StockMovementTypeX on StockMovementType {
  String get value {
    switch (this) {
      case StockMovementType.add:
        return 'add';
      case StockMovementType.remove:
        return 'remove';
      case StockMovementType.adjust:
        return 'adjust';
      case StockMovementType.purchase:
        return 'purchase';
      case StockMovementType.sale:
        return 'sale';
      case StockMovementType.returnSale:
        return 'return';
    }
  }

  static StockMovementType fromValue(String value) {
    return StockMovementType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => StockMovementType.adjust,
    );
  }
}

class AppSettingsModel extends Equatable {
  const AppSettingsModel({
    required this.storeName,
    required this.currency,
    required this.taxEnabled,
    required this.taxRate,
    required this.receiptHeader,
    required this.receiptFooter,
    required this.language,
    required this.allowNegativeStock,
    required this.cashierPin,
    required this.adminPassword,
  });

  final String storeName;
  final String currency;
  final bool taxEnabled;
  final double taxRate;
  final String receiptHeader;
  final String receiptFooter;
  final String language;
  final bool allowNegativeStock;
  final String cashierPin;
  final String adminPassword;

  AppSettingsModel copyWith({
    String? storeName,
    String? currency,
    bool? taxEnabled,
    double? taxRate,
    String? receiptHeader,
    String? receiptFooter,
    String? language,
    bool? allowNegativeStock,
    String? cashierPin,
    String? adminPassword,
  }) {
    return AppSettingsModel(
      storeName: storeName ?? this.storeName,
      currency: currency ?? this.currency,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      taxRate: taxRate ?? this.taxRate,
      receiptHeader: receiptHeader ?? this.receiptHeader,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      language: language ?? this.language,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      cashierPin: cashierPin ?? this.cashierPin,
      adminPassword: adminPassword ?? this.adminPassword,
    );
  }

  static const fallback = AppSettingsModel(
    storeName: 'Mini Store',
    currency: 'EGP',
    taxEnabled: false,
    taxRate: 0.14,
    receiptHeader: 'Thank you!',
    receiptFooter: 'Visit us again',
    language: 'en',
    allowNegativeStock: false,
    cashierPin: '1234',
    adminPassword: 'admin123',
  );

  @override
  List<Object?> get props => [
        storeName,
        currency,
        taxEnabled,
        taxRate,
        receiptHeader,
        receiptFooter,
        language,
        allowNegativeStock,
        cashierPin,
        adminPassword,
      ];
}

class ProductUpsertInput extends Equatable {
  const ProductUpsertInput({
    this.id,
    required this.name,
    required this.sku,
    this.barcode,
    this.categoryId,
    required this.cost,
    required this.price,
    required this.stockQty,
    this.lowStockThreshold = 5,
    this.unit = 'piece',
    this.notes,
    this.imagePath,
  });

  final int? id;
  final String name;
  final String sku;
  final String? barcode;
  final int? categoryId;
  final double cost;
  final double price;
  final int stockQty;
  final int lowStockThreshold;
  final String unit;
  final String? notes;
  final String? imagePath;

  @override
  List<Object?> get props => [
        id,
        name,
        sku,
        barcode,
        categoryId,
        cost,
        price,
        stockQty,
        lowStockThreshold,
        unit,
        notes,
        imagePath,
      ];
}

class StockMovementInput extends Equatable {
  const StockMovementInput({
    required this.productId,
    required this.type,
    required this.qtyChange,
    this.reason,
    this.supplierId,
    this.unitCost,
  });

  final int productId;
  final StockMovementType type;
  final int qtyChange;
  final String? reason;
  final int? supplierId;
  final double? unitCost;

  @override
  List<Object?> get props => [
        productId,
        type,
        qtyChange,
        reason,
        supplierId,
        unitCost,
      ];
}

class ProductFilter extends Equatable {
  const ProductFilter({
    this.search = '',
    this.categoryId,
    this.lowStockOnly = false,
  });

  final String search;
  final int? categoryId;
  final bool lowStockOnly;

  ProductFilter copyWith({
    String? search,
    int? categoryId,
    bool? lowStockOnly,
    bool clearCategory = false,
  }) {
    return ProductFilter(
      search: search ?? this.search,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    );
  }

  @override
  List<Object?> get props => [search, categoryId, lowStockOnly];
}

class CategoryModel extends Equatable {
  const CategoryModel({required this.id, required this.name});

  final int id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

class CustomerModel extends Equatable {
  const CustomerModel({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    required this.balance,
  });

  final int id;
  final String name;
  final String? phone;
  final String? notes;
  final double balance;

  @override
  List<Object?> get props => [id, name, phone, notes, balance];
}

class SupplierModel extends Equatable {
  const SupplierModel({required this.id, required this.name, this.phone});

  final int id;
  final String name;
  final String? phone;

  @override
  List<Object?> get props => [id, name, phone];
}

class InvoiceFilter extends Equatable {
  const InvoiceFilter({
    this.from,
    this.to,
    this.paymentMethod,
  });

  final DateTime? from;
  final DateTime? to;
  final PaymentMethod? paymentMethod;

  @override
  List<Object?> get props => [from, to, paymentMethod];
}

class SaleSummary extends Equatable {
  const SaleSummary({
    required this.id,
    required this.invoiceNo,
    required this.createdAt,
    required this.total,
    required this.paymentMethod,
    required this.status,
  });

  final int id;
  final String invoiceNo;
  final DateTime createdAt;
  final double total;
  final PaymentMethod paymentMethod;
  final SaleStatus status;

  @override
  List<Object?> get props => [id, invoiceNo, createdAt, total, paymentMethod, status];
}

class ReturnItemInput extends Equatable {
  const ReturnItemInput({required this.saleItemId, required this.qty});

  final int saleItemId;
  final int qty;

  @override
  List<Object?> get props => [saleItemId, qty];
}

class CartItem extends Equatable {
  const CartItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.cost,
    required this.price,
    required this.qty,
    this.discount = 0,
  });

  final int productId;
  final String name;
  final String sku;
  final String? barcode;
  final double cost;
  final double price;
  final int qty;
  final double discount;

  CartItem copyWith({
    int? qty,
    double? discount,
    double? price,
  }) {
    return CartItem(
      productId: productId,
      name: name,
      sku: sku,
      barcode: barcode,
      cost: cost,
      price: price ?? this.price,
      qty: qty ?? this.qty,
      discount: discount ?? this.discount,
    );
  }

  @override
  List<Object?> get props => [
        productId,
        name,
        sku,
        barcode,
        cost,
        price,
        qty,
        discount,
      ];
}

class DashboardMetrics extends Equatable {
  const DashboardMetrics({
    required this.todaySales,
    required this.todayInvoices,
    required this.monthSales,
    required this.monthInvoices,
    required this.todayProfit,
    required this.monthProfit,
    required this.bestSellers,
  });

  final double todaySales;
  final int todayInvoices;
  final double monthSales;
  final int monthInvoices;
  final double todayProfit;
  final double monthProfit;
  final List<BestSellerMetric> bestSellers;

  static const empty = DashboardMetrics(
    todaySales: 0,
    todayInvoices: 0,
    monthSales: 0,
    monthInvoices: 0,
    todayProfit: 0,
    monthProfit: 0,
    bestSellers: [],
  );

  @override
  List<Object?> get props => [
        todaySales,
        todayInvoices,
        monthSales,
        monthInvoices,
        todayProfit,
        monthProfit,
        bestSellers,
      ];
}

class BestSellerMetric extends Equatable {
  const BestSellerMetric({required this.productName, required this.qty});

  final String productName;
  final int qty;

  @override
  List<Object?> get props => [productName, qty];
}

class SalesByProductMetric extends Equatable {
  const SalesByProductMetric({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.total,
  });

  final int productId;
  final String productName;
  final int qty;
  final double total;

  @override
  List<Object?> get props => [productId, productName, qty, total];
}

class SaleCheckoutInput extends Equatable {
  const SaleCheckoutInput({
    required this.items,
    required this.orderDiscount,
    required this.taxEnabled,
    required this.taxRate,
    required this.paid,
    required this.paymentMethod,
    this.customerId,
  });

  final List<CartItem> items;
  final double orderDiscount;
  final bool taxEnabled;
  final double taxRate;
  final double paid;
  final PaymentMethod paymentMethod;
  final int? customerId;

  @override
  List<Object?> get props => [
        items,
        orderDiscount,
        taxEnabled,
        taxRate,
        paid,
        paymentMethod,
        customerId,
      ];
}
