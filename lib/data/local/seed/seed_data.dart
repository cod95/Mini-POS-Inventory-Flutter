import 'package:drift/drift.dart';

import '../../local/db/app_database.dart';

/// Maps each product SKU to a real Unsplash product image URL.
const _productImageUrls = <String, String>{
  // Beverages
  'BEV001': 'https://images.unsplash.com/photo-1629203851122-3726ecdf080e?w=300&h=300&fit=crop',
  'BEV002': 'https://images.unsplash.com/photo-1567103472471-e7e7da177e22?w=300&h=300&fit=crop',
  'BEV003': 'https://images.unsplash.com/photo-1600271886742-f049cd451bba?w=300&h=300&fit=crop',
  'BEV004': 'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?w=300&h=300&fit=crop',
  'BEV005': 'https://images.unsplash.com/photo-1551024601-bec78aea704b?w=300&h=300&fit=crop',
  // Snacks
  'SNK001': 'https://images.unsplash.com/photo-1576675784201-0e142b423952?w=300&h=300&fit=crop',
  'SNK002': 'https://images.unsplash.com/photo-1481391319762-47dff72954d9?w=300&h=300&fit=crop',
  'SNK003': 'https://images.unsplash.com/photo-1574570069012-f013e2fbc0af?w=300&h=300&fit=crop',
  'SNK004': 'https://images.unsplash.com/photo-1505686994434-e3cc5abf1330?w=300&h=300&fit=crop',
  'SNK005': 'https://images.unsplash.com/photo-1558961363-fa8fdf82db35?w=300&h=300&fit=crop',
  // Dairy
  'DAR001': 'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=300&h=300&fit=crop',
  'DAR002': 'https://images.unsplash.com/photo-1488477181946-6428a0291777?w=300&h=300&fit=crop',
  'DAR003': 'https://images.unsplash.com/photo-1486297678162-eb2a19b0a32d?w=300&h=300&fit=crop',
  'DAR004': 'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?w=300&h=300&fit=crop',
  'DAR005': 'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?w=300&h=300&fit=crop',
  // Household
  'HSH001': 'https://images.unsplash.com/photo-1585512458118-c22fa20dfe17?w=300&h=300&fit=crop',
  'HSH002': 'https://images.unsplash.com/photo-1610557892470-55d9e80c0bce?w=300&h=300&fit=crop',
  'HSH003': 'https://images.unsplash.com/photo-1584464491033-06628f3a6b7b?w=300&h=300&fit=crop',
  // Personal Care
  'PRS001': 'https://images.unsplash.com/photo-1583947215259-38e31be8751f?w=300&h=300&fit=crop',
  'PRS002': 'https://images.unsplash.com/photo-1535585209827-a15fcdbc4c2d?w=300&h=300&fit=crop',
};

class SeedData {
  const SeedData(this.db);

  final AppDatabase db;

  Future<void> ensureSeeded() async {
    final productCount = await db.select(db.products).get().then((rows) => rows.length);
    if (productCount > 0) {
      await _ensureSettings();
      await _ensureProductImages(); // patch any products missing image URLs
      return;
    }

    await _ensureSettings();
    await _seedCategoriesAndProducts();
    await _seedCustomersSuppliers();
  }

  /// Updates existing seeded products that still have a null imagePath.
  Future<void> _ensureProductImages() async {
    for (final entry in _productImageUrls.entries) {
      final rows = await (db.select(db.products)
            ..where((t) => t.sku.equals(entry.key)))
          .get();
      for (final row in rows) {
        if (row.imagePath == null) {
          await (db.update(db.products)..where((t) => t.id.equals(row.id))).write(
            ProductsCompanion(imagePath: Value(entry.value)),
          );
        }
      }
    }
  }

  Future<void> _ensureSettings() async {
    await db.into(db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            id: const Value(1),
            storeName: const Value('Mini Mart'),
            currency: const Value('EGP'),
            taxEnabled: const Value(false),
            taxRate: const Value(0.14),
            receiptHeader: const Value('Mini Mart - Welcome'),
            receiptFooter: const Value('Thank you for shopping with us'),
            language: const Value('en'),
            allowNegativeStock: const Value(false),
            cashierPin: const Value('1234'),
            adminPassword: const Value('admin123'),
          ),
        );
  }

  Future<void> _seedCategoriesAndProducts() async {
    final categories = ['Beverages', 'Snacks', 'Dairy', 'Household', 'Personal Care'];

    final categoryIds = <String, int>{};

    for (final name in categories) {
      final id = await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(name: name), mode: InsertMode.insertOrIgnore);
      if (id > 0) {
        categoryIds[name] = id;
      }
    }

    final existing = await db.select(db.categories).get();
    for (final category in existing) {
      categoryIds[category.name] = category.id;
    }

    final now = DateTime.now();
    final products = <ProductsCompanion>[
      // Beverages
      _product(name: 'Coca Cola 330ml',     sku: 'BEV001', barcode: '622300136001', categoryId: categoryIds['Beverages'],    cost: 8,   price: 12,  stockQty: 50, lowStockThreshold: 10),
      _product(name: 'Pepsi 330ml',         sku: 'BEV002', barcode: '622300136002', categoryId: categoryIds['Beverages'],    cost: 8,   price: 12,  stockQty: 42, lowStockThreshold: 10),
      _product(name: 'Orange Juice 1L',     sku: 'BEV003', barcode: '622300136003', categoryId: categoryIds['Beverages'],    cost: 18,  price: 25,  stockQty: 15, lowStockThreshold: 5),
      _product(name: 'Mineral Water 600ml', sku: 'BEV004', barcode: '622300136004', categoryId: categoryIds['Beverages'],    cost: 4,   price: 6,   stockQty: 100, lowStockThreshold: 20),
      _product(name: 'Energy Drink',        sku: 'BEV005', barcode: '622300136005', categoryId: categoryIds['Beverages'],    cost: 22,  price: 30,  stockQty: 12, lowStockThreshold: 5),
      // Snacks
      _product(name: 'Potato Chips Large',  sku: 'SNK001', barcode: '622300236001', categoryId: categoryIds['Snacks'],       cost: 9,   price: 15,  stockQty: 35, lowStockThreshold: 8),
      _product(name: 'Chocolate Bar',       sku: 'SNK002', barcode: '622300236002', categoryId: categoryIds['Snacks'],       cost: 7,   price: 10,  stockQty: 60, lowStockThreshold: 12),
      _product(name: 'Mixed Nuts 200g',     sku: 'SNK003', barcode: '622300236003', categoryId: categoryIds['Snacks'],       cost: 28,  price: 40,  stockQty: 9,  lowStockThreshold: 6),
      _product(name: 'Popcorn Salted',      sku: 'SNK004', barcode: '622300236004', categoryId: categoryIds['Snacks'],       cost: 11,  price: 18,  stockQty: 20, lowStockThreshold: 6),
      _product(name: 'Cookies Pack',        sku: 'SNK005', barcode: '622300236005', categoryId: categoryIds['Snacks'],       cost: 14,  price: 22,  stockQty: 28, lowStockThreshold: 7),
      // Dairy
      _product(name: 'Full Cream Milk 1L',  sku: 'DAR001', barcode: '622300336001', categoryId: categoryIds['Dairy'],        cost: 24,  price: 32,  stockQty: 18, lowStockThreshold: 6),
      _product(name: 'Yogurt Cup',          sku: 'DAR002', barcode: '622300336002', categoryId: categoryIds['Dairy'],        cost: 6,   price: 9,   stockQty: 40, lowStockThreshold: 10),
      _product(name: 'Cheddar Cheese 250g', sku: 'DAR003', barcode: '622300336003', categoryId: categoryIds['Dairy'],        cost: 45,  price: 62,  stockQty: 7,  lowStockThreshold: 4),
      _product(name: 'Butter 200g',         sku: 'DAR004', barcode: '622300336004', categoryId: categoryIds['Dairy'],        cost: 36,  price: 50,  stockQty: 10, lowStockThreshold: 4),
      _product(name: 'Eggs Tray 30',        sku: 'DAR005', barcode: '622300336005', categoryId: categoryIds['Dairy'],        cost: 120, price: 145, stockQty: 11, lowStockThreshold: 3, unit: 'tray'),
      // Household
      _product(name: 'Dish Soap 750ml',     sku: 'HSH001', barcode: '622300436001', categoryId: categoryIds['Household'],    cost: 22,  price: 32,  stockQty: 16, lowStockThreshold: 5),
      _product(name: 'Laundry Powder 1kg',  sku: 'HSH002', barcode: '622300436002', categoryId: categoryIds['Household'],    cost: 48,  price: 63,  stockQty: 14, lowStockThreshold: 5),
      _product(name: 'Paper Towels 2 Rolls',sku: 'HSH003', barcode: '622300436003', categoryId: categoryIds['Household'],    cost: 26,  price: 39,  stockQty: 8,  lowStockThreshold: 4),
      // Personal Care
      _product(name: 'Toothpaste 125ml',    sku: 'PRS001', barcode: '622300536001', categoryId: categoryIds['Personal Care'],cost: 19,  price: 28,  stockQty: 25, lowStockThreshold: 6),
      _product(name: 'Shampoo 400ml',       sku: 'PRS002', barcode: '622300536002', categoryId: categoryIds['Personal Care'],cost: 42,  price: 58,  stockQty: 13, lowStockThreshold: 4),
    ];

    await db.batch((batch) {
      for (final product in products) {
        batch.insert(db.products, product, mode: InsertMode.insertOrIgnore);
      }
    });

    // Immediately apply image URLs to newly inserted products
    await _ensureProductImages();

    final allProducts = await db.select(db.products).get();
    await db.batch((batch) {
      for (final product in allProducts) {
        batch.insert(
          db.stockMovements,
          StockMovementsCompanion.insert(
            productId: product.id,
            type: 'add',
            qtyChange: product.stockQty,
            reason: const Value('Initial stock seed'),
            createdAt: Value(now),
          ),
        );
      }
    });
  }

  Future<void> _seedCustomersSuppliers() async {
    await db.batch((batch) {
      batch.insertAll(db.customers, [
        CustomersCompanion.insert(
          name: 'Walk-in Customer',
          phone: const Value('01000000000'),
          notes: const Value('Default customer'),
          balance: const Value(0),
        ),
        CustomersCompanion.insert(
          name: 'Ahmed Ali',
          phone: const Value('01011223344'),
          notes: const Value('Regular customer'),
          balance: const Value(0),
        ),
        CustomersCompanion.insert(
          name: 'Sara Mohamed',
          phone: const Value('01155667788'),
          notes: const Value('Prefers card payment'),
          balance: const Value(30),
        ),
      ], mode: InsertMode.insertOrIgnore);

      batch.insertAll(db.suppliers, [
        SuppliersCompanion.insert(name: 'Cairo Wholesale', phone: const Value('0223456789')),
        SuppliersCompanion.insert(name: 'Delta Distributors', phone: const Value('0402233445')),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  ProductsCompanion _product({
    required String name,
    required String sku,
    required String barcode,
    required int? categoryId,
    required double cost,
    required double price,
    required int stockQty,
    required int lowStockThreshold,
    String unit = 'piece',
  }) {
    final now = DateTime.now();
    return ProductsCompanion.insert(
      name: name,
      sku: sku,
      barcode: Value(barcode),
      categoryId: Value(categoryId),
      cost: cost,
      price: price,
      stockQty: stockQty,
      lowStockThreshold: Value(lowStockThreshold),
      unit: Value(unit),
      imagePath: Value(_productImageUrls[sku]),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }
}
