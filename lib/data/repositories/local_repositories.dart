import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/models/app_models.dart';
import '../../core/utils/money_calculator.dart';
import '../../data/local/db/app_database.dart';
import '../../domain/entities/app_entities.dart';
import '../../domain/repositories/repositories.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._db);

  final AppDatabase _db;

  @override
  Future<UserRole?> loginAsAdmin(String password) async {
    final settings = await _settings();
    if (settings.adminPassword == password) {
      return UserRole.admin;
    }
    return null;
  }

  @override
  Future<UserRole?> loginWithPin(String pin) async {
    final settings = await _settings();
    if (settings.cashierPin == pin) {
      return UserRole.cashier;
    }
    return null;
  }

  @override
  Future<void> logout() async {}

  Future<AppSetting> _settings() async {
    final row = await (_db.select(_db.appSettings)..where((tbl) => tbl.id.equals(1)))
        .getSingleOrNull();
    if (row != null) {
      return row;
    }
    throw AppException('Settings not found');
  }
}

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<AppSettingsModel> getSettings() async {
    final row = await (_db.select(_db.appSettings)..where((tbl) => tbl.id.equals(1)))
        .getSingleOrNull();
    if (row == null) {
      return AppSettingsModel.fallback;
    }

    return AppSettingsModel(
      storeName: row.storeName,
      currency: row.currency,
      taxEnabled: row.taxEnabled,
      taxRate: row.taxRate,
      receiptHeader: row.receiptHeader,
      receiptFooter: row.receiptFooter,
      language: row.language,
      allowNegativeStock: row.allowNegativeStock,
      cashierPin: row.cashierPin,
      adminPassword: row.adminPassword,
    );
  }

  @override
  Future<void> updateSettings(AppSettingsModel settings) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            id: const Value(1),
            storeName: Value(settings.storeName),
            currency: Value(settings.currency),
            taxEnabled: Value(settings.taxEnabled),
            taxRate: Value(settings.taxRate),
            receiptHeader: Value(settings.receiptHeader),
            receiptFooter: Value(settings.receiptFooter),
            language: Value(settings.language),
            allowNegativeStock: Value(settings.allowNegativeStock),
            cashierPin: Value(settings.cashierPin),
            adminPassword: Value(settings.adminPassword),
          ),
        );
  }
}

class LocalProductRepository implements ProductRepository {
  LocalProductRepository(this._db);

  final AppDatabase _db;

  @override
  Future<int> addCategory(String name) {
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(name: name.trim()),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> addStockMovement(StockMovementInput input) async {
    await _db.transaction(() async {
      final product = await (_db.select(_db.products)
            ..where((tbl) => tbl.id.equals(input.productId)))
          .getSingleOrNull();

      if (product == null) {
        throw AppException('Product not found');
      }

      var newQty = product.stockQty + input.qtyChange;
      if (input.type == StockMovementType.adjust) {
        newQty = input.qtyChange;
      }

      if (newQty < 0) {
        throw AppException('Stock cannot be negative');
      }

      await (_db.update(_db.products)..where((tbl) => tbl.id.equals(product.id))).write(
        ProductsCompanion(
          stockQty: Value(newQty),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await _db.into(_db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: product.id,
              type: input.type.value,
              qtyChange: input.type == StockMovementType.adjust
                  ? newQty - product.stockQty
                  : input.qtyChange,
              reason: Value(input.reason),
              createdAt: Value(DateTime.now()),
            ),
          );

      if (input.type == StockMovementType.purchase && input.unitCost != null) {
        await _db.into(_db.purchases).insert(
              PurchasesCompanion.insert(
                supplierId: Value(input.supplierId),
                productId: input.productId,
                qty: max(0, input.qtyChange),
                unitCost: input.unitCost!,
                notes: Value(input.reason),
              ),
            );
      }
    });
  }

  @override
  Future<void> deleteCategory(int id) async {
    await (_db.delete(_db.categories)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<void> deleteProduct(int id) async {
    await (_db.delete(_db.products)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<ProductView?> findByBarcode(String barcode) async {
    final row = await (_db.select(_db.products)..where((tbl) => tbl.barcode.equals(barcode)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _toProductView(row);
  }

  @override
  Future<List<CategoryModel>> getCategories() async {
    final rows = await (_db.select(_db.categories)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map((e) => CategoryModel(id: e.id, name: e.name)).toList();
  }

  @override
  Future<ProductView?> getProduct(int id) async {
    final row = await (_db.select(_db.products)..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _toProductView(row);
  }

  @override
  Future<List<ProductView>> getProducts({ProductFilter filter = const ProductFilter()}) async {
    final rows = await (_db.select(_db.products)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    final categoryMap = await _categoryMap();

    return rows
        .where((p) {
          final matchesSearch = filter.search.trim().isEmpty ||
              p.name.toLowerCase().contains(filter.search.trim().toLowerCase()) ||
              p.sku.toLowerCase().contains(filter.search.trim().toLowerCase()) ||
              (p.barcode?.contains(filter.search.trim()) ?? false);
          final matchesCategory = filter.categoryId == null || p.categoryId == filter.categoryId;
          final matchesLowStock = !filter.lowStockOnly || p.stockQty <= p.lowStockThreshold;
          return matchesSearch && matchesCategory && matchesLowStock;
        })
        .map((row) => _toProductView(row, categoryName: categoryMap[row.categoryId]))
        .toList();
  }

  @override
  Future<List<ProductView>> getPopularProducts() async {
    final rows = await (_db.select(_db.products)
          ..orderBy([(t) => OrderingTerm.desc(t.stockQty)])
          ..limit(8))
        .get();
    final categoryMap = await _categoryMap();
    return rows
        .map((row) => _toProductView(row, categoryName: categoryMap[row.categoryId]))
        .toList();
  }

  @override
  Future<List<ProductView>> getLowStockProducts() async {
    final rows = await _db.select(_db.products).get();
    final categoryMap = await _categoryMap();
    return rows
        .where((row) => row.stockQty <= row.lowStockThreshold)
        .map((row) => _toProductView(row, categoryName: categoryMap[row.categoryId]))
        .toList();
  }

  @override
  Future<void> updateCategory(CategoryModel category) {
    return (_db.update(_db.categories)..where((tbl) => tbl.id.equals(category.id))).write(
      CategoriesCompanion(name: Value(category.name.trim())),
    );
  }

  @override
  Future<int> upsertProduct(ProductUpsertInput input) async {
    if (input.id == null) {
      return _db.into(_db.products).insert(
            ProductsCompanion.insert(
              name: input.name.trim(),
              sku: input.sku.trim(),
              barcode: Value(input.barcode?.trim()),
              categoryId: Value(input.categoryId),
              cost: input.cost,
              price: input.price,
              stockQty: input.stockQty,
              lowStockThreshold: Value(input.lowStockThreshold),
              unit: Value(input.unit),
              notes: Value(input.notes),
              imagePath: Value(input.imagePath),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }

    await (_db.update(_db.products)..where((tbl) => tbl.id.equals(input.id!))).write(
      ProductsCompanion(
        name: Value(input.name.trim()),
        sku: Value(input.sku.trim()),
        barcode: Value(input.barcode?.trim()),
        categoryId: Value(input.categoryId),
        cost: Value(input.cost),
        price: Value(input.price),
        stockQty: Value(input.stockQty),
        lowStockThreshold: Value(input.lowStockThreshold),
        unit: Value(input.unit),
        notes: Value(input.notes),
        imagePath: Value(input.imagePath),
        updatedAt: Value(DateTime.now()),
      ),
    );

    return input.id!;
  }

  Future<Map<int, String>> _categoryMap() async {
    final rows = await _db.select(_db.categories).get();
    return {for (final c in rows) c.id: c.name};
  }

  ProductView _toProductView(Product row, {String? categoryName}) {
    return ProductView(
      id: row.id,
      name: row.name,
      sku: row.sku,
      barcode: row.barcode,
      categoryId: row.categoryId,
      categoryName: categoryName,
      cost: row.cost,
      price: row.price,
      stockQty: row.stockQty,
      lowStockThreshold: row.lowStockThreshold,
      unit: row.unit,
      notes: row.notes,
      imagePath: row.imagePath,
    );
  }
}

class LocalSalesRepository implements SalesRepository {
  LocalSalesRepository(this._db);

  final AppDatabase _db;

  @override
  Future<SaleCheckoutResult> checkout(SaleCheckoutInput input) async {
    if (input.items.isEmpty) {
      throw AppException('Cart is empty');
    }

    return _db.transaction(() async {
      final settings = await (_db.select(_db.appSettings)
            ..where((tbl) => tbl.id.equals(1)))
          .getSingleOrNull();
      final allowNegativeStock = settings?.allowNegativeStock ?? false;

      final now = DateTime.now();
      final productIds = input.items.map((e) => e.productId).toSet().toList();
      final products = await (_db.select(_db.products)
            ..where((tbl) => tbl.id.isIn(productIds)))
          .get();
      final productById = {for (final product in products) product.id: product};

      for (final item in input.items) {
        final product = productById[item.productId];
        if (product == null) {
          throw AppException('Product ${item.name} no longer exists');
        }
        if (!allowNegativeStock && product.stockQty < item.qty) {
          throw AppException('Insufficient stock for ${item.name}');
        }
      }

      final lineTotals = input.items
          .map(
            (item) => MoneyCalculator.lineTotal(
              unitPrice: item.price,
              qty: item.qty,
              itemDiscount: item.discount,
            ),
          )
          .toList();

      final subtotal = MoneyCalculator.subtotal(lineTotals);
      final itemDiscountTotal =
          MoneyCalculator.round2(input.items.fold(0, (sum, item) => sum + item.discount));
      final tax = MoneyCalculator.tax(
        taxableAmount: max(0, subtotal - input.orderDiscount),
        taxEnabled: input.taxEnabled,
        taxRate: input.taxRate,
      );
      final total = MoneyCalculator.orderTotal(
        subtotal: subtotal,
        orderDiscount: input.orderDiscount,
        tax: tax,
      );
      final discountTotal = MoneyCalculator.round2(itemDiscountTotal + input.orderDiscount);
      final paid = input.paid;
      final change = MoneyCalculator.round2(max(0, paid - total));

      final invoiceNo = await _nextInvoiceNo(now);

      final saleId = await _db.into(_db.sales).insert(
            SalesCompanion.insert(
              invoiceNo: invoiceNo,
              createdAt: Value(now),
              customerId: Value(input.customerId),
              subtotal: subtotal,
              discountTotal: discountTotal,
              taxTotal: tax,
              total: total,
              paid: paid,
              changeAmount: change,
              paymentMethod: input.paymentMethod.value,
              status: SaleStatus.completed.value,
            ),
          );

      for (var i = 0; i < input.items.length; i++) {
        final item = input.items[i];
        final product = productById[item.productId]!;

        await _db.into(_db.saleItems).insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: item.productId,
                nameSnapshot: item.name,
                costSnapshot: item.cost,
                priceSnapshot: item.price,
                qty: item.qty,
                discount: Value(item.discount),
                lineTotal: lineTotals[i],
              ),
            );

        await (_db.update(_db.products)..where((tbl) => tbl.id.equals(product.id))).write(
          ProductsCompanion(
            stockQty: Value(product.stockQty - item.qty),
            updatedAt: Value(now),
          ),
        );

        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: product.id,
                type: StockMovementType.sale.value,
                qtyChange: -item.qty,
                reason: Value('Sale $invoiceNo'),
                createdAt: Value(now),
              ),
            );
      }

      if (input.customerId != null && paid < total) {
        final customer = await (_db.select(_db.customers)
              ..where((tbl) => tbl.id.equals(input.customerId!)))
            .getSingleOrNull();
        if (customer != null) {
          await (_db.update(_db.customers)..where((tbl) => tbl.id.equals(customer.id))).write(
            CustomersCompanion(balance: Value(customer.balance + (total - paid))),
          );
        }
      }

      return SaleCheckoutResult(
        saleId: saleId,
        invoiceNo: invoiceNo,
        total: total,
        paid: paid,
        change: change,
      );
    });
  }

  @override
  Future<SaleDetailView?> getInvoiceDetail(int saleId) async {
    final sale = await (_db.select(_db.sales)..where((tbl) => tbl.id.equals(saleId)))
        .getSingleOrNull();
    if (sale == null) {
      return null;
    }
    final items = await (_db.select(_db.saleItems)
          ..where((tbl) => tbl.saleId.equals(saleId)))
        .get();

    return SaleDetailView(
      sale: _toSaleView(sale),
      items: items.map(_toSaleItemView).toList(),
    );
  }

  @override
  Future<List<SaleSummary>> getInvoices({InvoiceFilter filter = const InvoiceFilter()}) async {
    final sales = await (_db.select(_db.sales)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();

    return sales
        .where((sale) {
          final matchesFrom = filter.from == null || !sale.createdAt.isBefore(filter.from!);
          final matchesTo =
              filter.to == null || !sale.createdAt.isAfter(filter.to!.add(const Duration(days: 1)));
          final matchesPayment = filter.paymentMethod == null ||
              sale.paymentMethod == filter.paymentMethod!.value;
          return matchesFrom && matchesTo && matchesPayment;
        })
        .map(
          (sale) => SaleSummary(
            id: sale.id,
            invoiceNo: sale.invoiceNo,
            createdAt: sale.createdAt,
            total: sale.total,
            paymentMethod: PaymentMethodX.fromValue(sale.paymentMethod),
            status: SaleStatusX.fromValue(sale.status),
          ),
        )
        .toList();
  }

  @override
  Future<ReturnResult> returnItems({required int saleId, required List<ReturnItemInput> items}) {
    if (items.isEmpty) {
      throw AppException('Select at least one item');
    }

    return _db.transaction(() async {
      final sale = await (_db.select(_db.sales)..where((tbl) => tbl.id.equals(saleId)))
          .getSingleOrNull();
      if (sale == null) {
        throw AppException('Sale not found');
      }

      final saleItems = await (_db.select(_db.saleItems)
            ..where((tbl) => tbl.saleId.equals(saleId)))
          .get();
      final saleItemById = {for (final item in saleItems) item.id: item};

      double totalReturn = 0;
      double discountReturn = 0;
      final now = DateTime.now();

      final returnInvoice = await _nextReturnInvoiceNo(now);
      final returnSaleId = await _db.into(_db.sales).insert(
            SalesCompanion.insert(
              invoiceNo: returnInvoice,
              createdAt: Value(now),
              customerId: Value(sale.customerId),
              subtotal: 0,
              discountTotal: 0,
              taxTotal: 0,
              total: 0,
              paid: 0,
              changeAmount: 0,
              paymentMethod: sale.paymentMethod,
              status: SaleStatus.returned.value,
            ),
          );

      for (final returnInput in items) {
        final original = saleItemById[returnInput.saleItemId];
        if (original == null) {
          throw AppException('Invalid return item');
        }
        if (returnInput.qty <= 0 || returnInput.qty > original.qty.abs()) {
          throw AppException('Invalid return quantity for ${original.nameSnapshot}');
        }

        final perUnitLine = original.lineTotal / max(1, original.qty.abs());
        final perUnitDiscount = original.discount / max(1, original.qty.abs());
        final returnLineTotal = MoneyCalculator.round2(-perUnitLine * returnInput.qty);
        final returnDiscount = MoneyCalculator.round2(perUnitDiscount * returnInput.qty);

        totalReturn += returnLineTotal;
        discountReturn += returnDiscount;

        await _db.into(_db.saleItems).insert(
              SaleItemsCompanion.insert(
                saleId: returnSaleId,
                productId: original.productId,
                nameSnapshot: original.nameSnapshot,
                costSnapshot: original.costSnapshot,
                priceSnapshot: original.priceSnapshot,
                qty: -returnInput.qty,
                discount: Value(returnDiscount),
                lineTotal: returnLineTotal,
              ),
            );

        final product = await (_db.select(_db.products)
              ..where((tbl) => tbl.id.equals(original.productId)))
            .getSingleOrNull();
        if (product != null) {
          await (_db.update(_db.products)..where((tbl) => tbl.id.equals(product.id))).write(
            ProductsCompanion(
              stockQty: Value(product.stockQty + returnInput.qty),
              updatedAt: Value(now),
            ),
          );

          await _db.into(_db.stockMovements).insert(
                StockMovementsCompanion.insert(
                  productId: product.id,
                  type: StockMovementType.returnSale.value,
                  qtyChange: returnInput.qty,
                  reason: Value('Return ${sale.invoiceNo}'),
                  createdAt: Value(now),
                ),
              );
        }
      }

      await (_db.update(_db.sales)..where((tbl) => tbl.id.equals(returnSaleId))).write(
        SalesCompanion(
          subtotal: Value(totalReturn),
          discountTotal: Value(discountReturn),
          taxTotal: const Value(0),
          total: Value(totalReturn),
          status: Value(SaleStatus.returned.value),
        ),
      );

      await (_db.update(_db.sales)..where((tbl) => tbl.id.equals(saleId))).write(
        SalesCompanion(status: Value(SaleStatus.returned.value)),
      );

      return ReturnResult(returnSaleId: returnSaleId, invoiceNo: returnInvoice);
    });
  }

  SaleItemView _toSaleItemView(SaleItem item) {
    return SaleItemView(
      id: item.id,
      saleId: item.saleId,
      productId: item.productId,
      nameSnapshot: item.nameSnapshot,
      costSnapshot: item.costSnapshot,
      priceSnapshot: item.priceSnapshot,
      qty: item.qty,
      discount: item.discount,
      lineTotal: item.lineTotal,
    );
  }

  SaleView _toSaleView(Sale sale) {
    return SaleView(
      id: sale.id,
      invoiceNo: sale.invoiceNo,
      createdAt: sale.createdAt,
      customerId: sale.customerId,
      subtotal: sale.subtotal,
      discountTotal: sale.discountTotal,
      taxTotal: sale.taxTotal,
      total: sale.total,
      paid: sale.paid,
      changeAmount: sale.changeAmount,
      paymentMethod: PaymentMethodX.fromValue(sale.paymentMethod),
      status: SaleStatusX.fromValue(sale.status),
    );
  }

  Future<String> _nextInvoiceNo(DateTime now) async {
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final countExp = _db.sales.id.count();
    final query = _db.selectOnly(_db.sales)
      ..addColumns([countExp])
      ..where(_db.sales.invoiceNo.like('INV-$datePart-%'));
    final count = (await query.getSingleOrNull())?.read(countExp) ?? 0;
    final sequence = (count + 1).toString().padLeft(4, '0');
    return 'INV-$datePart-$sequence';
  }

  Future<String> _nextReturnInvoiceNo(DateTime now) async {
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final countExp = _db.sales.id.count();
    final query = _db.selectOnly(_db.sales)
      ..addColumns([countExp])
      ..where(_db.sales.invoiceNo.like('RET-$datePart-%'));
    final count = (await query.getSingleOrNull())?.read(countExp) ?? 0;
    final sequence = (count + 1).toString().padLeft(4, '0');
    return 'RET-$datePart-$sequence';
  }
}

class LocalReportsRepository implements ReportsRepository {
  LocalReportsRepository(this._db, this._productRepository);

  final AppDatabase _db;
  final ProductRepository _productRepository;

  @override
  Future<DashboardMetrics> getDashboardMetrics() async {
    final sales = await _db.select(_db.sales).get();
    final items = await _db.select(_db.saleItems).get();

    final now = DateTime.now();
    bool isToday(DateTime date) =>
        date.year == now.year && date.month == now.month && date.day == now.day;
    bool isMonth(DateTime date) => date.year == now.year && date.month == now.month;

    final todaySalesRows = sales.where((sale) => isToday(sale.createdAt));
    final monthSalesRows = sales.where((sale) => isMonth(sale.createdAt));

    final todayIds = todaySalesRows.map((e) => e.id).toSet();
    final monthIds = monthSalesRows.map((e) => e.id).toSet();

    final todayItems = items.where((item) => todayIds.contains(item.saleId));
    final monthItems = items.where((item) => monthIds.contains(item.saleId));

    final todayProfit = MoneyCalculator.round2(
      todayItems.fold(
        0.0,
        (sum, item) =>
            sum +
            MoneyCalculator.profitForLine(
              priceSnapshot: item.priceSnapshot,
              costSnapshot: item.costSnapshot,
              qty: item.qty,
              discount: item.discount,
            ),
      ),
    );

    final monthProfit = MoneyCalculator.round2(
      monthItems.fold(
        0.0,
        (sum, item) =>
            sum +
            MoneyCalculator.profitForLine(
              priceSnapshot: item.priceSnapshot,
              costSnapshot: item.costSnapshot,
              qty: item.qty,
              discount: item.discount,
            ),
      ),
    );

    final qtyMap = <String, int>{};
    for (final item in monthItems) {
      qtyMap[item.nameSnapshot] = (qtyMap[item.nameSnapshot] ?? 0) + item.qty.abs();
    }
    final bestSellers = qtyMap.entries
        .map((entry) => BestSellerMetric(productName: entry.key, qty: entry.value))
        .toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));

    return DashboardMetrics(
      todaySales: MoneyCalculator.round2(todaySalesRows.fold(0.0, (sum, e) => sum + e.total)),
      todayInvoices: todayIds.length,
      monthSales: MoneyCalculator.round2(monthSalesRows.fold(0.0, (sum, e) => sum + e.total)),
      monthInvoices: monthIds.length,
      todayProfit: todayProfit,
      monthProfit: monthProfit,
      bestSellers: bestSellers.take(5).toList(),
    );
  }

  @override
  Future<List<InventoryReportRow>> inventoryReportRows() async {
    final products = await _productRepository.getProducts();
    return products
        .map(
          (p) => InventoryReportRow(
            name: p.name,
            sku: p.sku,
            category: p.categoryName ?? '-',
            stock: p.stockQty,
            cost: p.cost,
            price: p.price,
            lowStock: p.isLowStock,
          ),
        )
        .toList();
  }

  @override
  Future<List<ProductView>> lowStockProducts() => _productRepository.getLowStockProducts();

  @override
  Future<List<SalesByProductMetric>> salesByProduct({DateTime? from, DateTime? to}) async {
    final sales = await _db.select(_db.sales).get();
    final saleIds = sales
        .where((sale) {
          final fromOk = from == null || !sale.createdAt.isBefore(from);
          final toOk = to == null || !sale.createdAt.isAfter(to.add(const Duration(days: 1)));
          return fromOk && toOk;
        })
        .map((e) => e.id)
        .toSet();

    final items = await (_db.select(_db.saleItems)
          ..where((tbl) => tbl.saleId.isIn(saleIds.toList())))
        .get();

    final metrics = <int, SalesByProductMetric>{};
    for (final item in items) {
      final existing = metrics[item.productId];
      metrics[item.productId] = SalesByProductMetric(
        productId: item.productId,
        productName: item.nameSnapshot,
        qty: (existing?.qty ?? 0) + item.qty.abs(),
        total: MoneyCalculator.round2((existing?.total ?? 0) + item.lineTotal),
      );
    }

    final list = metrics.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  @override
  Future<List<SalesReportRow>> salesReportRows({DateTime? from, DateTime? to}) async {
    final sales = await _db.select(_db.sales).get();
    return sales
        .where((sale) {
          final fromOk = from == null || !sale.createdAt.isBefore(from);
          final toOk = to == null || !sale.createdAt.isAfter(to.add(const Duration(days: 1)));
          return fromOk && toOk;
        })
        .map(
          (sale) => SalesReportRow(
            invoiceNo: sale.invoiceNo,
            date: sale.createdAt,
            total: sale.total,
            paymentMethod: sale.paymentMethod,
            status: sale.status,
          ),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }
}

class LocalPartyRepository implements PartyRepository {
  LocalPartyRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> deleteCustomer(int id) {
    return (_db.delete(_db.customers)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<void> deleteSupplier(int id) {
    return (_db.delete(_db.suppliers)..where((tbl) => tbl.id.equals(id))).go();
  }

  @override
  Future<List<CustomerModel>> getCustomers() async {
    final rows = await (_db.select(_db.customers)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows
        .map(
          (e) => CustomerModel(
            id: e.id,
            name: e.name,
            phone: e.phone,
            notes: e.notes,
            balance: e.balance,
          ),
        )
        .toList();
  }

  @override
  Future<List<SupplierModel>> getSuppliers() async {
    final rows = await (_db.select(_db.suppliers)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map((e) => SupplierModel(id: e.id, name: e.name, phone: e.phone)).toList();
  }

  @override
  Future<int> upsertCustomer({
    int? id,
    required String name,
    String? phone,
    String? notes,
    double balance = 0,
  }) async {
    if (id == null) {
      return _db.into(_db.customers).insert(
            CustomersCompanion.insert(
              name: name,
              phone: Value(phone),
              notes: Value(notes),
              balance: Value(balance),
            ),
          );
    }

    await (_db.update(_db.customers)..where((tbl) => tbl.id.equals(id))).write(
      CustomersCompanion(
        name: Value(name),
        phone: Value(phone),
        notes: Value(notes),
        balance: Value(balance),
      ),
    );
    return id;
  }

  @override
  Future<int> upsertSupplier({int? id, required String name, String? phone}) async {
    if (id == null) {
      return _db
          .into(_db.suppliers)
          .insert(SuppliersCompanion.insert(name: name, phone: Value(phone)));
    }

    await (_db.update(_db.suppliers)..where((tbl) => tbl.id.equals(id))).write(
      SuppliersCompanion(name: Value(name), phone: Value(phone)),
    );
    return id;
  }
}
