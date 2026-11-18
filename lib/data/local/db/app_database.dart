import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Random 128-bit id (hex). Rows that travel between devices (products,
/// sales, sale items, stock movements) carry one so a sync can recognise
/// them without clashing on local auto-increment ids.
String newUuid() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

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

  /// Whether TVA applies to this product. Set per-product when adding/editing
  /// it; only taxable items contribute to the invoice's tax total.
  BoolColumn get taxable => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Sync identity of this product (same on every device).
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();

  /// Last time the product's catalog data (name, price…) was edited. Stock
  /// movements do not touch it, so a sync can tell who edited the price last.
  DateTimeColumn get catalogUpdatedAt => dateTime().nullable()();

  /// Local clock: when this row last changed on THIS phone (by a sale, an
  /// edit or an incoming sync). Lets a sync send only what is new.
  DateTimeColumn get changedAt => dateTime().nullable().clientDefault(DateTime.now)();
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

  TextColumn get uuid => text().nullable().clientDefault(newUuid)();

  DateTimeColumn get changedAt => dateTime().nullable().clientDefault(DateTime.now)();
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

  /// Snapshot of the store's secondary/display currency at the moment of
  /// sale (see AppSettings.secondaryCurrencyCode) — subtotal/total/etc.
  /// above stay expressed in the main currency; this is only used to also
  /// print the converted amount on the receipt.
  TextColumn get secondaryCurrencyCode =>
      text().withDefault(const Constant('LBP'))();

  /// Units of `secondaryCurrencyCode` equal to 1 unit of the sale's main
  /// currency, snapshotted at checkout time so old receipts stay correct
  /// even if the rate is changed later in Settings.
  RealColumn get exchangeRateAtSale => real().withDefault(const Constant(89000))();

  /// Free-text customer/client name typed at checkout, shown on the invoice.
  /// Independent of [customerId] (which is only used for the credit/balance
  /// ledger) — most walk-in sales will leave this blank.
  TextColumn get customerName => text().nullable()();

  /// For return documents (RET-…): the id of the original sale being
  /// returned. Null for ordinary sales.
  IntColumn get originalSaleId => integer().nullable()();

  /// Name of the user (cashier/admin) who made the sale.
  TextColumn get cashierName => text().nullable()();

  TextColumn get uuid => text().nullable().clientDefault(newUuid)();

  DateTimeColumn get changedAt => dateTime().nullable().clientDefault(DateTime.now)();
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

  /// Snapshot of whether TVA applied to this item at the time of sale.
  BoolColumn get taxable => boolean().withDefault(const Constant(false))();

  /// For rows of a return document: the sale item being returned. Used to
  /// know how much of each original line was already returned.
  IntColumn get originalItemId => integer().nullable()();

  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
}

/// Login accounts. `role` is 'admin' or 'cashier'; `secret` is the password
/// (admin) or PIN (cashier).
class UserAccounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get uuid => text().unique()();

  TextColumn get name => text()();

  TextColumn get role => text()();

  TextColumn get secret => text()();

  BoolColumn get active => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Local only (never synced): wrong-password counter and temporary lock.
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();

  DateTimeColumn get lockedUntil => dateTime().nullable()();

  /// True while the account still uses a default password / PIN.
  BoolColumn get mustChangeSecret => boolean().withDefault(const Constant(false))();
}

/// Products deleted on this phone (or learnt from another). Sent along in a
/// sync so the deletion reaches the other phones and the product is not
/// brought back by them.
class DeletedRecords extends Table {
  TextColumn get uuid => text()();

  /// 'product' or 'user'.
  TextColumn get kind => text().withDefault(const Constant('product'))();

  DateTimeColumn get deletedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {uuid};
}

/// What this phone knows about the other phones it syncs with over the
/// network: when it last sent to / received from each of them.
class SyncPeers extends Table {
  TextColumn get deviceId => text()();

  TextColumn get name => text().withDefault(const Constant(''))();

  /// This phone's clock at the start of the last successful send.
  DateTimeColumn get lastPushAt => dateTime().nullable()();

  /// The OTHER phone's clock at the last successful receive.
  DateTimeColumn get lastPullAt => dateTime().nullable()();

  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

class AppSettings extends Table {
  IntColumn get id => integer()();

  TextColumn get storeName => text().withDefault(const Constant('Mini Store'))();

  /// Shown under the store name (settings + receipt).
  TextColumn get storePhone => text().nullable()();

  /// When the store owner last "closed out" the reports/invoice log (a
  /// Z-report style reset). Reports and the invoice list default to
  /// showing only sales from this point forward until changed again.
  DateTimeColumn get lastReportReset => dateTime().nullable()();

  /// Paired Bluetooth thermal printer — set once from Settings.
  TextColumn get printerMacAddress => text().nullable()();
  TextColumn get printerName => text().nullable()();
  TextColumn get printerPaperWidthMm => text().withDefault(const Constant('80'))();

  /// The main currency products are priced in and sold with (e.g. 'USD').
  TextColumn get currency => text().withDefault(const Constant('USD'))();

  /// The second currency shown alongside `currency` on receipts (e.g. 'LBP').
  TextColumn get secondaryCurrencyCode =>
      text().withDefault(const Constant('LBP'))();

  /// Units of `secondaryCurrencyCode` equal to 1 unit of `currency`.
  /// e.g. if currency=USD, secondaryCurrencyCode=LBP, and exchangeRate=89000,
  /// then 1 USD = 89,000 LBP. Stays fixed until manually changed in Settings.
  RealColumn get exchangeRate => real().withDefault(const Constant(89000))();

  BoolColumn get taxEnabled => boolean().withDefault(const Constant(false))();

  RealColumn get taxRate => real().withDefault(const Constant(0.11))();

  TextColumn get receiptHeader => text().withDefault(const Constant('Thank you!'))();

  TextColumn get receiptFooter =>
      text().withDefault(const Constant('Visit us again'))();

  TextColumn get language => text().withDefault(const Constant('en'))();

  BoolColumn get allowNegativeStock => boolean().withDefault(const Constant(false))();

  TextColumn get cashierPin => text().withDefault(const Constant('1234'))();

  TextColumn get adminPassword => text().withDefault(const Constant('admin123'))();

  /// Random id of this phone/installation (used by sync).
  TextColumn get deviceId => text().nullable()();

  /// Short code put in this device's invoice numbers (e.g. 'B' gives
  /// INV-B-20261118-0001) so two phones never issue the same number. Empty
  /// on the main device.
  TextColumn get deviceCode => text().withDefault(const Constant(''))();

  /// Shop code shared by the phones of one shop. Encrypts everything that
  /// leaves the phone during sync. Local only, never inside a sync package.
  TextColumn get syncCode => text().nullable()();

  /// The phone of the shop owner. It is the hub: other phones send it their
  /// sales and receive products, prices, users and settings from it.
  BoolColumn get isMainDevice => boolean().withDefault(const Constant(false))();

  /// Sync over the shop's Wi-Fi automatically while the app is open.
  BoolColumn get autoSync => boolean().withDefault(const Constant(true))();

  /// Typed address of the main phone when automatic discovery is blocked by
  /// the router (e.g. 192.168.1.20).
  TextColumn get hubAddress => text().nullable()();

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
    UserAccounts,
    DeletedRecords,
    SyncPeers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor}) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(products, products.imagePath);
          }
          if (from < 3) {
            await m.addColumn(appSettings, appSettings.secondaryCurrencyCode);
            await m.addColumn(appSettings, appSettings.exchangeRate);
            await m.addColumn(sales, sales.secondaryCurrencyCode);
            await m.addColumn(sales, sales.exchangeRateAtSale);
          }
          if (from < 4) {
            await m.addColumn(appSettings, appSettings.storePhone);
            await m.addColumn(sales, sales.customerName);
          }
          if (from < 5) {
            await m.addColumn(products, products.taxable);
            await m.addColumn(saleItems, saleItems.taxable);
          }
          if (from < 6) {
            await m.addColumn(appSettings, appSettings.lastReportReset);
          }
          if (from < 7) {
            await m.addColumn(appSettings, appSettings.printerMacAddress);
            await m.addColumn(appSettings, appSettings.printerName);
            await m.addColumn(appSettings, appSettings.printerPaperWidthMm);
          }
          if (from < 8) {
            await m.addColumn(sales, sales.originalSaleId);
            await m.addColumn(saleItems, saleItems.originalItemId);
          }
          if (from < 9) {
            await m.createTable(userAccounts);
            await m.addColumn(sales, sales.cashierName);
          }
          if (from < 10) {
            await m.addColumn(products, products.uuid);
            await m.addColumn(products, products.catalogUpdatedAt);
            await m.addColumn(stockMovements, stockMovements.uuid);
            await m.addColumn(sales, sales.uuid);
            await m.addColumn(saleItems, saleItems.uuid);
            await m.addColumn(appSettings, appSettings.deviceId);
            await m.addColumn(appSettings, appSettings.deviceCode);
            for (final table in ['products', 'stock_movements', 'sales', 'sale_items']) {
              await customStatement(
                "UPDATE $table SET uuid = lower(hex(randomblob(16))) WHERE uuid IS NULL",
              );
            }
            await customStatement('UPDATE products SET catalog_updated_at = updated_at');
          }
          if (from < 11) {
            await m.addColumn(userAccounts, userAccounts.failedAttempts);
            await m.addColumn(userAccounts, userAccounts.lockedUntil);
            await m.addColumn(userAccounts, userAccounts.mustChangeSecret);
            await m.addColumn(appSettings, appSettings.syncCode);
            await customStatement(
              "UPDATE user_accounts SET must_change_secret = 1 WHERE secret IN ('admin123', '1234')",
            );
          }
          if (from < 12) {
            await m.addColumn(products, products.changedAt);
            await m.addColumn(stockMovements, stockMovements.changedAt);
            await m.addColumn(sales, sales.changedAt);
            await m.addColumn(appSettings, appSettings.isMainDevice);
            await m.addColumn(appSettings, appSettings.autoSync);
            await m.addColumn(appSettings, appSettings.hubAddress);
            await m.createTable(deletedRecords);
            await m.createTable(syncPeers);
            for (final table in ['products', 'stock_movements', 'sales']) {
              await customStatement(
                "UPDATE $table SET changed_at = CAST(strftime('%s','now') AS INTEGER)",
              );
            }
          }
        },
        beforeOpen: (details) async {
          // Keep "changed on this phone" up to date for every edit, wherever
          // in the code it happens.
          for (final table in ['products', 'sales']) {
            await customStatement(
              'CREATE TRIGGER IF NOT EXISTS trg_${table}_touch AFTER UPDATE ON $table '
              'WHEN NEW.changed_at IS OLD.changed_at '
              'BEGIN UPDATE $table SET changed_at = CAST(strftime(\'%s\',\'now\') AS INTEGER) '
              'WHERE id = NEW.id; END;',
            );
          }
          // A row can never be stored twice under the same sync id.
          for (final spec in const [
            ['idx_products_uuid', 'products'],
            ['idx_movements_uuid', 'stock_movements'],
            ['idx_sales_uuid', 'sales'],
            ['idx_sale_items_uuid', 'sale_items'],
          ]) {
            try {
              await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS ${spec[0]} ON ${spec[1]}(uuid)',
              );
            } catch (_) {
              // Never block the app from opening over an index.
            }
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
