import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/models/app_models.dart';
import '../../core/security/secret_hasher.dart';
import '../../core/utils/money_calculator.dart';
import '../../data/local/db/app_database.dart';
import '../../domain/entities/app_entities.dart';
import '../../domain/repositories/repositories.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._db);

  final AppDatabase _db;

  AppUser _toUser(UserAccount row) => AppUser(
        id: row.id,
        uuid: row.uuid,
        name: row.name,
        role: UserRoleX.fromValue(row.role),
        active: row.active,
        mustChangeSecret: row.mustChangeSecret,
        lockedUntil: row.lockedUntil,
      );

  @override
  Future<List<AppUser>> getUsers({bool activeOnly = false}) async {
    final rows = await (_db.select(_db.userAccounts)
          ..orderBy([(t) => OrderingTerm.asc(t.role), (t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.where((r) => !activeOnly || r.active).map(_toUser).toList();
  }

  @override
  Future<AppUser?> login(int userId, String secret) async {
    final row = await (_db.select(_db.userAccounts)..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (row == null || !row.active) return null;

    final now = DateTime.now();
    final lockedUntil = row.lockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      throw LoginLockedException(lockedUntil.difference(now).inSeconds + 1);
    }

    final ok = await SecretHasher.verify(secret, row.secret);
    if (!ok) {
      final attempts = row.failedAttempts + 1;
      DateTime? lock;
      if (attempts >= 5) {
        final minutes = min(30, 1 << min(5, attempts - 5));
        lock = now.add(Duration(minutes: minutes));
      }
      await (_db.update(_db.userAccounts)..where((t) => t.id.equals(row.id))).write(
        UserAccountsCompanion(
          failedAttempts: Value(attempts),
          lockedUntil: Value(lock),
        ),
      );
      if (lock != null) throw LoginLockedException(lock.difference(now).inSeconds + 1);
      return null;
    }

    // Old plain-text secrets are replaced by a salted hash on first success.
    final upgraded = SecretHasher.isHashed(row.secret) ? null : await SecretHasher.hash(secret);
    await (_db.update(_db.userAccounts)..where((t) => t.id.equals(row.id))).write(
      UserAccountsCompanion(
        failedAttempts: const Value(0),
        lockedUntil: const Value(null),
        secret: upgraded == null ? const Value.absent() : Value(upgraded),
      ),
    );
    return _toUser(row);
  }

  @override
  Future<void> changeSecret({
    required int userId,
    required String newSecret,
    String? currentSecret,
  }) async {
    final row = await (_db.select(_db.userAccounts)..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (row == null) throw AppException('User not found');
    if (currentSecret != null && !await SecretHasher.verify(currentSecret.trim(), row.secret)) {
      throw AppException('كلمة المرور الحالية غير صحيحة / Current password is wrong');
    }
    final clean = newSecret.trim();
    final problem = SecretPolicy.check(clean, isAdmin: row.role == UserRole.admin.value);
    if (problem != null) throw AppException(problem);
    await (_db.update(_db.userAccounts)..where((t) => t.id.equals(userId))).write(
      UserAccountsCompanion(
        secret: Value(await SecretHasher.hash(clean)),
        mustChangeSecret: const Value(false),
        failedAttempts: const Value(0),
        lockedUntil: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> _activeAdminCount({int? except}) async {
    final rows = await (_db.select(_db.userAccounts)
          ..where((t) => t.role.equals(UserRole.admin.value) & t.active.equals(true)))
        .get();
    return rows.where((r) => r.id != except).length;
  }

  @override
  Future<int> saveUser({
    int? id,
    required String name,
    required UserRole role,
    String? secret,
    bool active = true,
  }) async {
    final cleanName = name.trim();
    final cleanSecret = (secret ?? '').trim();
    if (cleanName.isEmpty) throw AppException('Name is required');
    if (id == null && cleanSecret.isEmpty) throw AppException('Password / PIN is required');
    if (cleanSecret.isNotEmpty) {
      final problem = SecretPolicy.check(cleanSecret, isAdmin: role == UserRole.admin);
      if (problem != null) throw AppException(problem);
    }

    final sameName = await (_db.select(_db.userAccounts)
          ..where((t) => t.name.lower().equals(cleanName.toLowerCase())))
        .get();
    if (sameName.any((u) => u.id != id)) {
      throw AppException('This name is already used');
    }

    if (id == null) {
      return _db.into(_db.userAccounts).insert(
            UserAccountsCompanion.insert(
              uuid: newUuid(),
              name: cleanName,
              role: role.value,
              secret: await SecretHasher.hash(cleanSecret),
              active: Value(active),
            ),
          );
    }

    final existing = await (_db.select(_db.userAccounts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) throw AppException('User not found');

    final staysActiveAdmin = role == UserRole.admin && active;
    if (!staysActiveAdmin && await _activeAdminCount(except: id) == 0) {
      throw AppException('There must be at least one active admin');
    }

    await (_db.update(_db.userAccounts)..where((t) => t.id.equals(id))).write(
      UserAccountsCompanion(
        name: Value(cleanName),
        role: Value(role.value),
        secret: cleanSecret.isEmpty ? const Value.absent() : Value(await SecretHasher.hash(cleanSecret)),
        mustChangeSecret: cleanSecret.isEmpty ? const Value.absent() : const Value(false),
        active: Value(active),
        // Editing an account also unlocks it.
        failedAttempts: const Value(0),
        lockedUntil: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return id;
  }

  @override
  Future<void> deleteUser(int id) async {
    final existing = await (_db.select(_db.userAccounts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) return;
    if (existing.role == UserRole.admin.value && await _activeAdminCount(except: id) == 0) {
      throw AppException('There must be at least one active admin');
    }
    await _db.transaction(() async {
      await (_db.delete(_db.userAccounts)..where((t) => t.id.equals(id))).go();
      await _db.into(_db.deletedRecords).insertOnConflictUpdate(
            DeletedRecordsCompanion.insert(
              uuid: existing.uuid,
              kind: const Value('user'),
              deletedAt: Value(DateTime.now()),
            ),
          );
    });
  }

  @override
  Future<void> logout() async {}
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
      storePhone: row.storePhone,
      currency: row.currency,
      secondaryCurrencyCode: row.secondaryCurrencyCode,
      exchangeRate: row.exchangeRate,
      taxEnabled: row.taxEnabled,
      taxRate: row.taxRate,
      receiptHeader: row.receiptHeader,
      receiptFooter: row.receiptFooter,
      language: row.language,
      allowNegativeStock: row.allowNegativeStock,
      cashierPin: row.cashierPin,
      adminPassword: row.adminPassword,
      lastReportReset: row.lastReportReset,
      printerMacAddress: row.printerMacAddress,
      printerName: row.printerName,
      printerPaperWidthMm: row.printerPaperWidthMm,
    );
  }

  @override
  Future<void> updateSettings(AppSettingsModel settings) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            id: const Value(1),
            storeName: Value(settings.storeName),
            storePhone: Value(settings.storePhone),
            currency: Value(settings.currency),
            secondaryCurrencyCode: Value(settings.secondaryCurrencyCode),
            exchangeRate: Value(settings.exchangeRate),
            taxEnabled: Value(settings.taxEnabled),
            taxRate: Value(settings.taxRate),
            receiptHeader: Value(settings.receiptHeader),
            receiptFooter: Value(settings.receiptFooter),
            language: Value(settings.language),
            allowNegativeStock: Value(settings.allowNegativeStock),
            cashierPin: Value(settings.cashierPin),
            adminPassword: Value(settings.adminPassword),
            lastReportReset: Value(settings.lastReportReset),
            printerMacAddress: Value(settings.printerMacAddress),
            printerName: Value(settings.printerName),
            printerPaperWidthMm: Value(settings.printerPaperWidthMm),
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
    await _db.transaction(() async {
      final row = await (_db.select(_db.products)..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return;
      await (_db.delete(_db.products)..where((tbl) => tbl.id.equals(id))).go();
      final uuid = row.uuid;
      if (uuid != null) {
        // Remember the deletion so a sync takes the product away from the
        // other phones too instead of bringing it back.
        await _db.into(_db.deletedRecords).insertOnConflictUpdate(
              DeletedRecordsCompanion.insert(
                uuid: uuid,
                kind: const Value('product'),
                deletedAt: Value(DateTime.now()),
              ),
            );
      }
    });
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
    final now = DateTime.now();

    if (input.id == null) {
      final id = await _db.into(_db.products).insert(
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
              taxable: Value(input.taxable),
              createdAt: Value(now),
              updatedAt: Value(now),
              catalogUpdatedAt: Value(now),
            ),
          );
      if (input.stockQty != 0) {
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: id,
                type: StockMovementType.add.value,
                qtyChange: input.stockQty,
                reason: const Value('Opening stock'),
                createdAt: Value(now),
              ),
            );
      }
      return id;
    }

    final existing = await (_db.select(_db.products)..where((tbl) => tbl.id.equals(input.id!)))
        .getSingleOrNull();

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
        taxable: Value(input.taxable),
        updatedAt: Value(now),
        catalogUpdatedAt: Value(now),
      ),
    );

    // Every stock change is a movement, so a sync can replay it elsewhere.
    if (existing != null && existing.stockQty != input.stockQty) {
      await _db.into(_db.stockMovements).insert(
            StockMovementsCompanion.insert(
              productId: input.id!,
              type: StockMovementType.adjust.value,
              qtyChange: input.stockQty - existing.stockQty,
              reason: const Value('Edit product'),
              createdAt: Value(now),
            ),
          );
    }

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
      taxable: row.taxable,
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
      // TVA applies only to items individually marked taxable. Use the
      // product's CURRENT taxable flag from the database (productById, just
      // fetched above) rather than the cart's snapshot — the cart item may
      // have been added before the product's TVA toggle was last changed,
      // which would otherwise silently under/over-tax the sale.
      final taxableSubtotal = MoneyCalculator.round2(
        input.items.where((item) => productById[item.productId]?.taxable ?? item.taxable).fold<double>(
              0,
              (sum, item) => sum +
                  MoneyCalculator.lineTotal(
                    unitPrice: item.price,
                    qty: item.qty,
                    itemDiscount: item.discount,
                  ),
            ),
      );
      final tax = MoneyCalculator.tax(
        taxableAmount: taxableSubtotal,
        taxEnabled: true,
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
              customerName: Value(
                (input.customerName == null || input.customerName!.trim().isEmpty)
                    ? null
                    : input.customerName!.trim(),
              ),
              cashierName: Value(input.cashierName),
              subtotal: subtotal,
              discountTotal: discountTotal,
              taxTotal: tax,
              total: total,
              paid: paid,
              changeAmount: change,
              paymentMethod: input.paymentMethod.value,
              status: SaleStatus.completed.value,
              secondaryCurrencyCode: Value(settings?.secondaryCurrencyCode ?? 'LBP'),
              exchangeRateAtSale: Value(settings?.exchangeRate ?? 89000),
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
                taxable: Value(product.taxable),
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
    final returned = await _returnedQtyByItem(saleId);

    return SaleDetailView(
      sale: _toSaleView(sale),
      items: items.map(_toSaleItemView).toList(),
      returnedQtyByItemId: returned,
    );
  }

  /// saleItemId -> total quantity already returned from that line.
  Future<Map<int, int>> _returnedQtyByItem(int saleId) async {
    final returnDocs = await (_db.select(_db.sales)
          ..where((tbl) => tbl.originalSaleId.equals(saleId)))
        .get();
    if (returnDocs.isEmpty) return {};
    final rows = await (_db.select(_db.saleItems)
          ..where((tbl) => tbl.saleId.isIn(returnDocs.map((e) => e.id).toList())))
        .get();
    final map = <int, int>{};
    for (final row in rows) {
      final key = row.originalItemId;
      if (key == null) continue;
      map[key] = (map[key] ?? 0) + row.qty.abs();
    }
    return map;
  }

  @override
  Future<List<SaleSummary>> getInvoices({InvoiceFilter filter = const InvoiceFilter()}) async {
    final sales = await (_db.select(_db.sales)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();
    final query = filter.search?.trim().toLowerCase() ?? '';

    return sales
        .where((sale) {
          final matchesFrom = filter.from == null || !sale.createdAt.isBefore(filter.from!);
          final matchesTo =
              filter.to == null || !sale.createdAt.isAfter(filter.to!.add(const Duration(days: 1)));
          final matchesPayment = filter.paymentMethod == null ||
              sale.paymentMethod == filter.paymentMethod!.value;
          final matchesSearch = query.isEmpty ||
              sale.invoiceNo.toLowerCase().contains(query) ||
              (sale.customerName ?? '').toLowerCase().contains(query);
          return matchesFrom && matchesTo && matchesPayment && matchesSearch;
        })
        .map(
          (sale) => SaleSummary(
            id: sale.id,
            invoiceNo: sale.invoiceNo,
            createdAt: sale.createdAt,
            total: sale.total,
            paymentMethod: PaymentMethodX.fromValue(sale.paymentMethod),
            status: SaleStatusX.fromValue(sale.status),
            customerName: sale.customerName,
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
      if (sale.invoiceNo.startsWith('RET-')) {
        throw AppException('A return document cannot be returned');
      }
      if (sale.status == SaleStatus.cancelled.value) {
        throw AppException('This invoice was cancelled');
      }

      final saleItems = await (_db.select(_db.saleItems)
            ..where((tbl) => tbl.saleId.equals(saleId)))
          .get();
      final saleItemById = {for (final item in saleItems) item.id: item};
      final alreadyReturned = await _returnedQtyByItem(saleId);

      // Amounts already refunded by earlier return documents of this sale.
      final previousReturns = await (_db.select(_db.sales)
            ..where((tbl) => tbl.originalSaleId.equals(saleId)))
          .get();
      final prevNet =
          previousReturns.fold<double>(0, (sum, r) => sum + (-(r.total - r.taxTotal)));
      final prevTax = previousReturns.fold<double>(0, (sum, r) => sum + (-r.taxTotal));

      // The invoice may carry an order-level discount and TVA that are not
      // part of each line: refund them proportionally so that returning
      // everything refunds exactly what the customer paid.
      final netSale = sale.total - sale.taxTotal;
      final factor = sale.subtotal > 0 ? netSale / sale.subtotal : 1.0;
      final taxableBase =
          saleItems.where((i) => i.taxable).fold<double>(0, (sum, i) => sum + i.lineTotal);
      final taxRatio = (taxableBase > 0 && sale.taxTotal > 0) ? sale.taxTotal / taxableBase : 0.0;

      // Validate first.
      final thisReturn = <int, int>{};
      for (final input in items) {
        final original = saleItemById[input.saleItemId];
        if (original == null) {
          throw AppException('Invalid return item');
        }
        final available = original.qty - (alreadyReturned[original.id] ?? 0);
        if (input.qty <= 0 || input.qty > available) {
          throw AppException('Invalid return quantity for ${original.nameSnapshot}');
        }
        thisReturn[original.id] = (thisReturn[original.id] ?? 0) + input.qty;
      }
      for (final entry in thisReturn.entries) {
        final original = saleItemById[entry.key]!;
        final available = original.qty - (alreadyReturned[original.id] ?? 0);
        if (entry.value > available) {
          throw AppException('Invalid return quantity for ${original.nameSnapshot}');
        }
      }

      final remainingAfter = saleItems.fold<int>(
        0,
        (sum, item) =>
            sum + item.qty - (alreadyReturned[item.id] ?? 0) - (thisReturn[item.id] ?? 0),
      );
      final fullyReturned = remainingAfter <= 0;

      final now = DateTime.now();
      final returnInvoice = await _nextReturnInvoiceNo(now);
      final returnSaleId = await _db.into(_db.sales).insert(
            SalesCompanion.insert(
              invoiceNo: returnInvoice,
              createdAt: Value(now),
              customerId: Value(sale.customerId),
              customerName: Value(sale.customerName),
              subtotal: 0,
              discountTotal: 0,
              taxTotal: 0,
              total: 0,
              paid: 0,
              changeAmount: 0,
              paymentMethod: sale.paymentMethod,
              status: SaleStatus.returned.value,
              secondaryCurrencyCode: Value(sale.secondaryCurrencyCode),
              exchangeRateAtSale: Value(sale.exchangeRateAtSale),
              originalSaleId: Value(saleId),
            ),
          );

      double sumBase = 0;
      double sumNet = 0;
      double taxRefund = 0;

      for (final entry in thisReturn.entries) {
        final original = saleItemById[entry.key]!;
        final qty = entry.value;

        final perUnitLine = original.lineTotal / max(1, original.qty);
        final perUnitDiscount = original.discount / max(1, original.qty);
        final base = MoneyCalculator.round2(perUnitLine * qty);
        final discount = MoneyCalculator.round2(perUnitDiscount * qty);

        sumBase += base;
        sumNet += MoneyCalculator.round2(base * factor);
        if (original.taxable) {
          taxRefund += MoneyCalculator.round2(base * taxRatio);
        }

        await _db.into(_db.saleItems).insert(
              SaleItemsCompanion.insert(
                saleId: returnSaleId,
                productId: original.productId,
                nameSnapshot: original.nameSnapshot,
                costSnapshot: original.costSnapshot,
                priceSnapshot: original.priceSnapshot,
                qty: -qty,
                discount: Value(discount),
                lineTotal: -base,
                taxable: Value(original.taxable),
                originalItemId: Value(original.id),
              ),
            );

        final product = await (_db.select(_db.products)
              ..where((tbl) => tbl.id.equals(original.productId)))
            .getSingleOrNull();
        if (product != null) {
          await (_db.update(_db.products)..where((tbl) => tbl.id.equals(product.id))).write(
            ProductsCompanion(
              stockQty: Value(product.stockQty + qty),
              updatedAt: Value(now),
            ),
          );

          await _db.into(_db.stockMovements).insert(
                StockMovementsCompanion.insert(
                  productId: product.id,
                  type: StockMovementType.returnSale.value,
                  qtyChange: qty,
                  reason: Value('Return ${sale.invoiceNo}'),
                  createdAt: Value(now),
                ),
              );
        }
      }

      if (fullyReturned) {
        // Remove rounding drift: the sum of all returns equals the invoice.
        sumNet = MoneyCalculator.round2(netSale - prevNet);
        taxRefund = MoneyCalculator.round2(sale.taxTotal - prevTax);
      }
      sumBase = MoneyCalculator.round2(sumBase);
      sumNet = MoneyCalculator.round2(sumNet);
      taxRefund = MoneyCalculator.round2(taxRefund);
      final returnTotal = -MoneyCalculator.round2(sumNet + taxRefund);

      await (_db.update(_db.sales)..where((tbl) => tbl.id.equals(returnSaleId))).write(
        SalesCompanion(
          subtotal: Value(-sumBase),
          discountTotal: Value(MoneyCalculator.round2(max(0, sumBase - sumNet))),
          taxTotal: Value(-taxRefund),
          total: Value(returnTotal),
          paid: Value(returnTotal),
          status: Value(SaleStatus.returned.value),
        ),
      );

      await (_db.update(_db.sales)..where((tbl) => tbl.id.equals(saleId))).write(
        SalesCompanion(
          status: Value(
            fullyReturned ? SaleStatus.returned.value : SaleStatus.partiallyReturned.value,
          ),
        ),
      );

      return ReturnResult(returnSaleId: returnSaleId, invoiceNo: returnInvoice);
    });
  }

  @override
  Future<void> cancelSale(int saleId) {
    return _db.transaction(() async {
      final sale = await (_db.select(_db.sales)..where((tbl) => tbl.id.equals(saleId)))
          .getSingleOrNull();
      if (sale == null) {
        throw AppException('Sale not found');
      }
      if (sale.invoiceNo.startsWith('RET-')) {
        throw AppException('A return document cannot be cancelled');
      }
      if (sale.status != SaleStatus.completed.value) {
        throw AppException('Only an invoice with no returns can be cancelled');
      }

      final now = DateTime.now();
      final saleItems = await (_db.select(_db.saleItems)
            ..where((tbl) => tbl.saleId.equals(saleId)))
          .get();

      for (final item in saleItems) {
        final product = await (_db.select(_db.products)
              ..where((tbl) => tbl.id.equals(item.productId)))
            .getSingleOrNull();
        if (product == null) continue;
        await (_db.update(_db.products)..where((tbl) => tbl.id.equals(product.id))).write(
          ProductsCompanion(
            stockQty: Value(product.stockQty + item.qty),
            updatedAt: Value(now),
          ),
        );
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: product.id,
                type: StockMovementType.returnSale.value,
                qtyChange: item.qty,
                reason: Value('Cancel ${sale.invoiceNo}'),
                createdAt: Value(now),
              ),
            );
      }

      // Undo the credit balance added at checkout for unpaid sales.
      if (sale.customerId != null && sale.paid < sale.total) {
        final customer = await (_db.select(_db.customers)
              ..where((tbl) => tbl.id.equals(sale.customerId!)))
            .getSingleOrNull();
        if (customer != null) {
          await (_db.update(_db.customers)..where((tbl) => tbl.id.equals(customer.id))).write(
            CustomersCompanion(balance: Value(customer.balance - (sale.total - sale.paid))),
          );
        }
      }

      await (_db.update(_db.sales)..where((tbl) => tbl.id.equals(saleId))).write(
        SalesCompanion(status: Value(SaleStatus.cancelled.value)),
      );
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
      taxable: item.taxable,
    );
  }

  SaleView _toSaleView(Sale sale) {
    return SaleView(
      id: sale.id,
      invoiceNo: sale.invoiceNo,
      createdAt: sale.createdAt,
      customerId: sale.customerId,
      customerName: sale.customerName,
      subtotal: sale.subtotal,
      discountTotal: sale.discountTotal,
      taxTotal: sale.taxTotal,
      total: sale.total,
      paid: sale.paid,
      changeAmount: sale.changeAmount,
      paymentMethod: PaymentMethodX.fromValue(sale.paymentMethod),
      status: SaleStatusX.fromValue(sale.status),
      secondaryCurrencyCode: sale.secondaryCurrencyCode,
      exchangeRateAtSale: sale.exchangeRateAtSale,
      originalSaleId: sale.originalSaleId,
      cashierName: sale.cashierName,
    );
  }

  Future<String> _deviceCode() async {
    final row = await (_db.select(_db.appSettings)..where((tbl) => tbl.id.equals(1)))
        .getSingleOrNull();
    return (row?.deviceCode ?? '').trim();
  }

  Future<String> _nextInvoiceNo(DateTime now) => _nextNumber('INV', now);

  Future<String> _nextReturnInvoiceNo(DateTime now) => _nextNumber('RET', now);

  /// INV-20261118-0001 on the main device, INV-B-20261118-0001 on a device
  /// whose code is "B". Never returns a number that already exists.
  Future<String> _nextNumber(String kind, DateTime now) async {
    final code = await _deviceCode();
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final prefix = code.isEmpty ? '$kind-$datePart-' : '$kind-$code-$datePart-';
    final countExp = _db.sales.id.count();
    final query = _db.selectOnly(_db.sales)
      ..addColumns([countExp])
      ..where(_db.sales.invoiceNo.like('$prefix%'));
    var sequence = ((await query.getSingleOrNull())?.read(countExp) ?? 0) + 1;

    while (true) {
      final candidate = '$prefix${sequence.toString().padLeft(4, '0')}';
      final taken = await (_db.select(_db.sales)..where((tbl) => tbl.invoiceNo.equals(candidate)))
          .getSingleOrNull();
      if (taken == null) return candidate;
      sequence++;
    }
  }
}

class LocalReportsRepository implements ReportsRepository {
  LocalReportsRepository(this._db, this._productRepository);

  final AppDatabase _db;
  final ProductRepository _productRepository;

  /// Money ledger: every document that is not a cancelled invoice. Original
  /// invoices count with their full value and each return document (RET-…,
  /// negative amounts/quantities) cancels its share, so sales, cost and
  /// profit are always NET of returns.
  static bool _isLedgerDoc(Sale sale) => sale.status != SaleStatus.cancelled.value;

  /// Return documents created by returnItems() (RET-… invoice numbers).
  static bool _isReturnDocument(Sale sale) => sale.invoiceNo.startsWith('RET-');

  /// Invoices that still count in "number of invoices": real sales that are
  /// not fully returned and not cancelled.
  static bool _isCountedInvoice(Sale sale) =>
      !_isReturnDocument(sale) &&
      (sale.status == SaleStatus.completed.value ||
          sale.status == SaleStatus.partiallyReturned.value);

  /// Net sale value: after item + order discounts, without TVA. Negative for
  /// return documents.
  static double _netSales(Sale sale) => sale.total - sale.taxTotal;

  /// Cost of goods: negative for returned (negative-qty) rows.
  static double _itemsCost(Iterable<SaleItem> items) =>
      items.fold(0.0, (sum, item) => sum + item.costSnapshot * item.qty);

  @override
  Future<DashboardMetrics> getDashboardMetrics({DateTime? since}) async {
    final allSales = await _db.select(_db.sales).get();
    final sales = allSales
        .where(_isLedgerDoc)
        .where((s) => since == null || !s.createdAt.isBefore(since))
        .toList();
    final saleIds = sales.map((e) => e.id).toSet();
    final allItems = await _db.select(_db.saleItems).get();
    final items = allItems.where((item) => saleIds.contains(item.saleId)).toList();

    final now = DateTime.now();
    bool isToday(DateTime date) =>
        date.year == now.year && date.month == now.month && date.day == now.day;
    bool isMonth(DateTime date) => date.year == now.year && date.month == now.month;

    final todaySalesRows = sales.where((sale) => isToday(sale.createdAt)).toList();
    final monthSalesRows = sales.where((sale) => isMonth(sale.createdAt)).toList();

    final todayIds = todaySalesRows.map((e) => e.id).toSet();
    final monthIds = monthSalesRows.map((e) => e.id).toSet();

    final todayItems = items.where((item) => todayIds.contains(item.saleId));
    final monthItems = items.where((item) => monthIds.contains(item.saleId));

    final todaySales = todaySalesRows.fold(0.0, (sum, e) => sum + _netSales(e));
    final monthSales = monthSalesRows.fold(0.0, (sum, e) => sum + _netSales(e));

    // Profit = Net sales - Cost (both already net of returns).
    final todayProfit = MoneyCalculator.round2(todaySales - _itemsCost(todayItems));
    final monthProfit = MoneyCalculator.round2(monthSales - _itemsCost(monthItems));

    final qtyMap = <String, int>{};
    for (final item in monthItems) {
      qtyMap[item.nameSnapshot] = (qtyMap[item.nameSnapshot] ?? 0) + item.qty;
    }
    final bestSellers = qtyMap.entries
        .where((entry) => entry.value > 0)
        .map((entry) => BestSellerMetric(productName: entry.key, qty: entry.value))
        .toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));

    return DashboardMetrics(
      todaySales: MoneyCalculator.round2(todaySales),
      todayInvoices: todaySalesRows.where(_isCountedInvoice).length,
      monthSales: MoneyCalculator.round2(monthSales),
      monthInvoices: monthSalesRows.where(_isCountedInvoice).length,
      todayProfit: todayProfit,
      monthProfit: monthProfit,
      bestSellers: bestSellers.take(5).toList(),
    );
  }

  @override
  Future<PeriodSummary> periodSummary({DateTime? from, DateTime? to}) async {
    final allSales = await _db.select(_db.sales).get();
    final inRange = allSales.where((sale) {
      final fromOk = from == null || !sale.createdAt.isBefore(from);
      final toOk = to == null || !sale.createdAt.isAfter(to.add(const Duration(days: 1)));
      return fromOk && toOk;
    }).toList();

    final ledger = inRange.where(_isLedgerDoc).toList();
    final returns = inRange.where(_isReturnDocument).toList();

    final ledgerIds = ledger.map((e) => e.id).toSet();
    final items = ledgerIds.isEmpty
        ? const <SaleItem>[]
        : await (_db.select(_db.saleItems)..where((tbl) => tbl.saleId.isIn(ledgerIds.toList()))).get();

    return PeriodSummary(
      invoiceCount: ledger.where(_isCountedInvoice).length,
      totalSales: MoneyCalculator.round2(ledger.fold(0.0, (sum, e) => sum + _netSales(e))),
      totalCost: MoneyCalculator.round2(_itemsCost(items)),
      returnCount: returns.length,
      totalReturns: MoneyCalculator.round2(returns.fold(0.0, (sum, e) => sum + _netSales(e).abs())),
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
        .where(_isLedgerDoc)
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
        qty: (existing?.qty ?? 0) + item.qty,
        total: MoneyCalculator.round2((existing?.total ?? 0) + item.lineTotal),
      );
    }

    final list = metrics.values.where((m) => m.qty != 0).toList()..sort((a, b) => b.total.compareTo(a.total));
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
