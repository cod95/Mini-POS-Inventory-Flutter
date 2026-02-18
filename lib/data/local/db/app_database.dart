import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get sku => text().unique()();

  TextColumn get barcode => text().nullable().unique()();

  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();

  RealColumn get cost => real()();

  RealColumn get price => real()();

  IntColumn get stockQty => integer()();

  IntColumn get lowStockThreshold => integer().withDefault(const Constant(5))();

  TextColumn get unit => text().withDefault(const Constant('piece'))();

  TextColumn get notes => text().nullable()();

  TextColumn get imagePath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().unique()();
}

class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  TextColumn get type => text()();

  IntColumn get qtyChange => integer()();

  TextColumn get reason => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get phone => text().nullable()();

  TextColumn get notes => text().nullable()();

  RealColumn get balance => real().withDefault(const Constant(0))();
}

class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get phone => text().nullable()();
}

class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get supplierId =>
      integer().nullable().references(Suppliers, #id, onDelete: KeyAction.setNull)();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  IntColumn get qty => integer()();

  RealColumn get unitCost => real()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get invoiceNo => text().unique()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get customerId =>
      integer().nullable().references(Customers, #id, onDelete: KeyAction.setNull)();

  RealColumn get subtotal => real()();

  RealColumn get discountTotal => real()();

  RealColumn get taxTotal => real()();

  RealColumn get total => real()();

  RealColumn get paid => real()();

  RealColumn get changeAmount => real()();

  TextColumn get paymentMethod => text()();

  TextColumn get status => text()();
}

class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();

  TextColumn get nameSnapshot => text()();

  RealColumn get costSnapshot => real()();

  RealColumn get priceSnapshot => real()();

  IntColumn get qty => integer()();

  RealColumn get discount => real().withDefault(const Constant(0))();

  RealColumn get lineTotal => real()();
}

class AppSettings extends Table {
  IntColumn get id => integer()();

  TextColumn get storeName => text().withDefault(const Constant('Mini Store'))();

  TextColumn get currency => text().withDefault(const Constant('EGP'))();

  BoolColumn get taxEnabled => boolean().withDefault(const Constant(false))();

  RealColumn get taxRate => real().withDefault(const Constant(0.14))();

  TextColumn get receiptHeader => text().withDefault(const Constant('Thank you!'))();

  TextColumn get receiptFooter =>
      text().withDefault(const Constant('Visit us again'))();

  TextColumn get language => text().withDefault(const Constant('en'))();

  BoolColumn get allowNegativeStock => boolean().withDefault(const Constant(false))();

  TextColumn get cashierPin => text().withDefault(const Constant('1234'))();

  TextColumn get adminPassword => text().withDefault(const Constant('admin123'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Products,
    Categories,
    StockMovements,
    Customers,
    Suppliers,
    Purchases,
    Sales,
    SaleItems,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(products, products.imagePath);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'mini_pos_inventory.sqlite'));
    return NativeDatabase(file);
  });
}
