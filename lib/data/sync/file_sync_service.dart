import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/security/sync_crypto.dart';
import '../local/db/app_database.dart';

class SyncImportResult {
  SyncImportResult();

  int newProducts = 0;
  int updatedProducts = 0;
  int newSales = 0;
  int updatedSales = 0;
  int appliedMovements = 0;
  int usersChanged = 0;
  bool settingsApplied = false;
  String? assignedDeviceCode;
  String senderName = '';
  final List<String> warnings = [];
}

/// Syncs two phones through a file (sent over WhatsApp, Bluetooth, USB…).
///
/// The file holds the sender's products, every sale/return with its items and
/// every stock movement (each with a unique id). Importing it is safe to do
/// any number of times: rows already known are skipped, new sales and stock
/// movements are added, price edits follow the latest change, and a sale's
/// status (returned / cancelled) only moves forward.
class FileSyncService {
  FileSyncService(this._db);

  final AppDatabase _db;

  static const String _format = 'quickstock-sync';
  static const int _version = 2;

  // ------------------------------------------------------------- shop code

  Future<String?> getSyncCode() async {
    final row = await _settings();
    final code = row.syncCode;
    return (code == null || code.isEmpty) ? null : SyncCrypto.pretty(code);
  }

  /// Creates a new random shop code (main phone) and stores it.
  Future<String> createSyncCode() async {
    final code = SyncCrypto.generateCode();
    await _storeSyncCode(code);
    return code;
  }

  /// Stores the code typed in from the main phone. Throws FormatException
  /// when it does not look like a shop code.
  Future<void> setSyncCode(String code) async {
    if (!SyncCrypto.isValidCode(code)) throw const FormatException('BAD_CODE');
    await _storeSyncCode(SyncCrypto.pretty(code));
  }

  Future<void> _storeSyncCode(String code) async {
    await _settings();
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(syncCode: Value(code)),
    );
  }

  Future<Uint8List> _key() async {
    final code = await getSyncCode();
    if (code == null) throw const FormatException('NO_SYNC_CODE');
    return SyncCrypto.deriveKey(code);
  }

  // ----------------------------------------------------------------- export

  Future<File> exportToFile({required bool includeAdminData}) async {
    final key = await _key();
    final data = await _buildPackage(includeAdminData: includeAdminData);
    final json = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final encrypted = await Isolate.run(
      () => SyncCrypto.encryptSync(Uint8List.fromList(gzip.encode(json)), key),
    );
    final bytes = <int>[...SyncCrypto.magic, ...encrypted];

    final dir = await getTemporaryDirectory();
    final code = (data['deviceCode'] as String).isEmpty ? 'main' : data['deviceCode'];
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
    final file = File(p.join(dir.path, 'quickstock_sync_${code}_$stamp.qsync'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareFile(File file) => Share.shareXFiles([XFile(file.path)]);

  Future<AppSetting> _settings() async {
    final row = await (_db.select(_db.appSettings)..where((t) => t.id.equals(1))).getSingle();
    if (row.deviceId != null && row.deviceId!.isNotEmpty) return row;
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(deviceId: Value(newUuid())),
    );
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(1))).getSingle();
  }

  static String _date(DateTime d) => d.toUtc().toIso8601String();

  Future<Map<String, dynamic>> _buildPackage({required bool includeAdminData}) async {
    final settings = await _settings();
    final categories = await _db.select(_db.categories).get();
    final categoryName = {for (final c in categories) c.id: c.name};
    final products = await _db.select(_db.products).get();
    final productUuid = {for (final p in products) p.id: p.uuid};
    final movements = await _db.select(_db.stockMovements).get();
    final sales = await _db.select(_db.sales).get();
    final items = await _db.select(_db.saleItems).get();

    final saleUuid = {for (final s in sales) s.id: s.uuid};
    final itemUuid = {for (final i in items) i.id: i.uuid};
    final itemsBySale = <int, List<SaleItem>>{};
    for (final item in items) {
      itemsBySale.putIfAbsent(item.saleId, () => []).add(item);
    }

    final data = <String, dynamic>{
      'format': _format,
      'version': _version,
      'deviceId': settings.deviceId,
      'deviceCode': settings.deviceCode,
      'storeName': settings.storeName,
      'exportedAt': _date(DateTime.now()),
      'categories': categories.map((c) => c.name).toList(),
      'products': [
        for (final p in products)
          {
            'uuid': p.uuid,
            'name': p.name,
            'sku': p.sku,
            'barcode': p.barcode,
            'category': p.categoryId == null ? null : categoryName[p.categoryId],
            'cost': p.cost,
            'price': p.price,
            'stockQty': p.stockQty,
            'lowStockThreshold': p.lowStockThreshold,
            'unit': p.unit,
            'notes': p.notes,
            'taxable': p.taxable,
            'catalogUpdatedAt': _date(p.catalogUpdatedAt ?? p.updatedAt),
          },
      ],
      'movements': [
        for (final m in movements)
          {
            'uuid': m.uuid,
            'productUuid': productUuid[m.productId],
            'type': m.type,
            'qtyChange': m.qtyChange,
            'reason': m.reason,
            'createdAt': _date(m.createdAt),
          },
      ],
      'sales': [
        for (final s in sales)
          {
            'uuid': s.uuid,
            'invoiceNo': s.invoiceNo,
            'createdAt': _date(s.createdAt),
            'customerName': s.customerName,
            'cashierName': s.cashierName,
            'subtotal': s.subtotal,
            'discountTotal': s.discountTotal,
            'taxTotal': s.taxTotal,
            'total': s.total,
            'paid': s.paid,
            'changeAmount': s.changeAmount,
            'paymentMethod': s.paymentMethod,
            'status': s.status,
            'secondaryCurrencyCode': s.secondaryCurrencyCode,
            'exchangeRateAtSale': s.exchangeRateAtSale,
            'originalSaleUuid': s.originalSaleId == null ? null : saleUuid[s.originalSaleId],
            'items': [
              for (final i in itemsBySale[s.id] ?? const <SaleItem>[])
                {
                  'uuid': i.uuid,
                  'productUuid': productUuid[i.productId],
                  'name': i.nameSnapshot,
                  'cost': i.costSnapshot,
                  'price': i.priceSnapshot,
                  'qty': i.qty,
                  'discount': i.discount,
                  'lineTotal': i.lineTotal,
                  'taxable': i.taxable,
                  'originalItemUuid': i.originalItemId == null ? null : itemUuid[i.originalItemId],
                },
            ],
          },
      ],
    };

    if (includeAdminData) {
      final users = await _db.select(_db.userAccounts).get();
      data['fromAdmin'] = true;
      data['users'] = [
        for (final u in users)
          {
            'uuid': u.uuid,
            'name': u.name,
            'role': u.role,
            'secret': u.secret,
            'active': u.active,
            'updatedAt': _date(u.updatedAt),
          },
      ];
      data['settings'] = {
        'storeName': settings.storeName,
        'storePhone': settings.storePhone,
        'currency': settings.currency,
        'secondaryCurrencyCode': settings.secondaryCurrencyCode,
        'exchangeRate': settings.exchangeRate,
        'taxEnabled': settings.taxEnabled,
        'taxRate': settings.taxRate,
        'receiptHeader': settings.receiptHeader,
        'receiptFooter': settings.receiptFooter,
        'allowNegativeStock': settings.allowNegativeStock,
      };
    }
    return data;
  }

  // ----------------------------------------------------------------- import

  Future<SyncImportResult> importFromFile(File file) async {
    final raw = await file.readAsBytes();
    if (!SyncCrypto.hasMagic(raw)) {
      throw const FormatException('NOT_A_SYNC_FILE');
    }
    final key = await _key();
    final Map<String, dynamic> data;
    try {
      final body = Uint8List.sublistView(raw, SyncCrypto.magic.length);
      final plain = await Isolate.run(
        () => Uint8List.fromList(gzip.decode(SyncCrypto.decryptSync(body, key))),
      );
      data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } on SyncDecryptException {
      throw const FormatException('WRONG_CODE');
    } catch (_) {
      throw const FormatException('NOT_A_SYNC_FILE');
    }
    if (data['format'] != _format) {
      throw const FormatException('NOT_A_SYNC_FILE');
    }
    return _import(data);
  }

  static bool _isDefaultSecret(String secret) => secret == 'admin123' || secret == '1234';

  static DateTime _parse(Object? v) => DateTime.tryParse('$v')?.toLocal() ?? DateTime.now();

  static const Map<String, int> _statusRank = {
    'completed': 0,
    'partial': 1,
    'returned': 2,
    'cancelled': 3,
  };

  Future<SyncImportResult> _import(Map<String, dynamic> data) {
    return _db.transaction(() async {
      final result = SyncImportResult()..senderName = '${data['storeName'] ?? ''}';
      final mySettings = await _settings();
      final senderCode = '${data['deviceCode'] ?? ''}';

      // ---- device code so the two phones never issue the same number
      if (data['deviceId'] != mySettings.deviceId &&
          (mySettings.deviceCode == senderCode)) {
        final random = Random();
        final code = 'D${10 + random.nextInt(90)}';
        await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
          AppSettingsCompanion(deviceCode: Value(code)),
        );
        result.assignedDeviceCode = code;
      }

      // ---- users + store settings (admin packages only)
      if (data['fromAdmin'] == true) {
        for (final raw in (data['users'] as List? ?? const [])) {
          final u = raw as Map<String, dynamic>;
          final uuid = '${u['uuid']}';
          final existing = await (_db.select(_db.userAccounts)..where((t) => t.uuid.equals(uuid)))
              .getSingleOrNull();
          final incomingAt = _parse(u['updatedAt']);
          if (existing == null) {
            await _db.into(_db.userAccounts).insert(
                  UserAccountsCompanion.insert(
                    uuid: uuid,
                    name: '${u['name']}',
                    role: '${u['role']}',
                    secret: '${u['secret']}',
                    mustChangeSecret: Value(_isDefaultSecret('${u['secret']}')),
                    active: Value(u['active'] == true),
                    updatedAt: Value(incomingAt),
                  ),
                );
            result.usersChanged++;
          } else if (incomingAt.isAfter(existing.updatedAt)) {
            await (_db.update(_db.userAccounts)..where((t) => t.id.equals(existing.id))).write(
              UserAccountsCompanion(
                name: Value('${u['name']}'),
                role: Value('${u['role']}'),
                secret: Value('${u['secret']}'),
                mustChangeSecret: Value(_isDefaultSecret('${u['secret']}')),
                active: Value(u['active'] == true),
                updatedAt: Value(incomingAt),
              ),
            );
            result.usersChanged++;
          }
        }

        final s = data['settings'] as Map<String, dynamic>?;
        if (s != null) {
          await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
            AppSettingsCompanion(
              storeName: Value('${s['storeName']}'),
              storePhone: Value(s['storePhone'] as String?),
              currency: Value('${s['currency']}'),
              secondaryCurrencyCode: Value('${s['secondaryCurrencyCode']}'),
              exchangeRate: Value((s['exchangeRate'] as num).toDouble()),
              taxEnabled: Value(s['taxEnabled'] == true),
              taxRate: Value((s['taxRate'] as num).toDouble()),
              receiptHeader: Value('${s['receiptHeader']}'),
              receiptFooter: Value('${s['receiptFooter']}'),
              allowNegativeStock: Value(s['allowNegativeStock'] == true),
            ),
          );
          result.settingsApplied = true;
        }
      }

      // ---- categories
      final categoryIds = <String, int>{};
      for (final c in await _db.select(_db.categories).get()) {
        categoryIds[c.name.toLowerCase()] = c.id;
      }
      Future<int?> categoryId(String? name) async {
        if (name == null || name.trim().isEmpty) return null;
        final key = name.trim().toLowerCase();
        final existing = categoryIds[key];
        if (existing != null) return existing;
        final id = await _db.into(_db.categories).insert(CategoriesCompanion.insert(name: name.trim()));
        categoryIds[key] = id;
        return id;
      }

      // ---- products
      final localProducts = await _db.select(_db.products).get();
      final byUuid = {for (final p in localProducts) if (p.uuid != null) p.uuid!: p};
      final bySku = {for (final p in localProducts) p.sku.toLowerCase(): p};
      final byBarcode = {
        for (final p in localProducts)
          if ((p.barcode ?? '').isNotEmpty) p.barcode!.toLowerCase(): p,
      };
      final byName = {for (final p in localProducts) p.name.toLowerCase(): p};

      final productIdByUuid = <String, int>{};
      // Products first seen in this package take the sender's stock as their
      // starting point; their movements in this package are already inside it.
      final baselineProducts = <String>{};

      for (final raw in (data['products'] as List? ?? const [])) {
        final p = raw as Map<String, dynamic>;
        final uuid = '${p['uuid']}';
        final name = '${p['name']}';
        final sku = '${p['sku']}';
        final barcode = (p['barcode'] as String?)?.trim();
        final incomingAt = _parse(p['catalogUpdatedAt']);
        final catId = await categoryId(p['category'] as String?);

        ProductsCompanion catalog({bool withStock = false}) => ProductsCompanion(
              name: Value(name),
              sku: Value(sku),
              barcode: Value((barcode == null || barcode.isEmpty) ? null : barcode),
              categoryId: Value(catId),
              cost: Value((p['cost'] as num).toDouble()),
              price: Value((p['price'] as num).toDouble()),
              lowStockThreshold: Value((p['lowStockThreshold'] as num).toInt()),
              unit: Value('${p['unit']}'),
              notes: Value(p['notes'] as String?),
              taxable: Value(p['taxable'] == true),
              catalogUpdatedAt: Value(incomingAt),
              updatedAt: Value(DateTime.now()),
              stockQty: withStock ? Value((p['stockQty'] as num).toInt()) : const Value.absent(),
            );

        try {
          final local = byUuid[uuid];
          if (local != null) {
            productIdByUuid[uuid] = local.id;
            final localAt = local.catalogUpdatedAt ?? local.updatedAt;
            if (incomingAt.isAfter(localAt)) {
              await (_db.update(_db.products)..where((t) => t.id.equals(local.id))).write(catalog());
              result.updatedProducts++;
            }
            continue;
          }

          final match = bySku[sku.toLowerCase()] ??
              ((barcode ?? '').isNotEmpty ? byBarcode[barcode!.toLowerCase()] : null) ??
              byName[name.toLowerCase()];

          if (match != null) {
            // Same product created separately on each phone: link them.
            await (_db.update(_db.products)..where((t) => t.id.equals(match.id))).write(
              catalog(withStock: true).copyWith(uuid: Value(uuid)),
            );
            productIdByUuid[uuid] = match.id;
            baselineProducts.add(uuid);
            result.updatedProducts++;
          } else {
            final id = await _db.into(_db.products).insert(
                  ProductsCompanion.insert(
                    name: name,
                    sku: sku,
                    barcode: Value((barcode == null || barcode.isEmpty) ? null : barcode),
                    categoryId: Value(catId),
                    cost: (p['cost'] as num).toDouble(),
                    price: (p['price'] as num).toDouble(),
                    stockQty: (p['stockQty'] as num).toInt(),
                    lowStockThreshold: Value((p['lowStockThreshold'] as num).toInt()),
                    unit: Value('${p['unit']}'),
                    notes: Value(p['notes'] as String?),
                    taxable: Value(p['taxable'] == true),
                    catalogUpdatedAt: Value(incomingAt),
                    uuid: Value(uuid),
                  ),
                );
            productIdByUuid[uuid] = id;
            baselineProducts.add(uuid);
            result.newProducts++;
          }
        } catch (e) {
          result.warnings.add('Product "$name": $e');
        }
      }

      // ---- stock movements (each applied once, ever)
      final knownMovements = <String>{
        for (final m in await _db.select(_db.stockMovements).get())
          if (m.uuid != null) m.uuid!,
      };
      for (final raw in (data['movements'] as List? ?? const [])) {
        final m = raw as Map<String, dynamic>;
        final uuid = '${m['uuid']}';
        if (knownMovements.contains(uuid)) continue;
        final productUuid = '${m['productUuid']}';
        final productId = productIdByUuid[productUuid];
        if (productId == null) continue;

        final qty = (m['qtyChange'] as num).toInt();
        await _db.into(_db.stockMovements).insert(
              StockMovementsCompanion.insert(
                productId: productId,
                type: '${m['type']}',
                qtyChange: qty,
                reason: Value(m['reason'] as String?),
                createdAt: Value(_parse(m['createdAt'])),
                uuid: Value(uuid),
              ),
            );
        knownMovements.add(uuid);
        if (!baselineProducts.contains(productUuid)) {
          await _db.customUpdate(
            'UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?',
            variables: [Variable<int>(qty), Variable<int>(productId)],
            updates: {_db.products},
          );
          result.appliedMovements++;
        }
      }

      // ---- sales
      final localSales = await _db.select(_db.sales).get();
      final saleByUuid = {for (final s in localSales) if (s.uuid != null) s.uuid!: s};
      final usedNumbers = {for (final s in localSales) s.invoiceNo};
      final saleIdByUuid = {for (final s in localSales) if (s.uuid != null) s.uuid!: s.id};
      final itemIdByUuid = <String, int>{
        for (final i in await _db.select(_db.saleItems).get())
          if (i.uuid != null) i.uuid!: i.id,
      };

      final newLinks = <({int saleId, String? originalSaleUuid})>[];
      final newItemLinks = <({int itemId, String originalItemUuid})>[];

      for (final raw in (data['sales'] as List? ?? const [])) {
        final s = raw as Map<String, dynamic>;
        final uuid = '${s['uuid']}';
        final status = '${s['status']}';

        final local = saleByUuid[uuid];
        if (local != null) {
          final incomingRank = _statusRank[status] ?? 0;
          final localRank = _statusRank[local.status] ?? 0;
          if (incomingRank > localRank) {
            await (_db.update(_db.sales)..where((t) => t.id.equals(local.id))).write(
              SalesCompanion(status: Value(status)),
            );
            result.updatedSales++;
          }
          continue;
        }

        var invoiceNo = '${s['invoiceNo']}';
        if (usedNumbers.contains(invoiceNo)) {
          final suffix = senderCode.isEmpty ? 'X' : senderCode;
          var candidate = '$invoiceNo-$suffix';
          var n = 2;
          while (usedNumbers.contains(candidate)) {
            candidate = '$invoiceNo-$suffix$n';
            n++;
          }
          invoiceNo = candidate;
        }
        usedNumbers.add(invoiceNo);

        final saleId = await _db.into(_db.sales).insert(
              SalesCompanion.insert(
                invoiceNo: invoiceNo,
                createdAt: Value(_parse(s['createdAt'])),
                customerName: Value(s['customerName'] as String?),
                cashierName: Value(s['cashierName'] as String?),
                subtotal: (s['subtotal'] as num).toDouble(),
                discountTotal: (s['discountTotal'] as num).toDouble(),
                taxTotal: (s['taxTotal'] as num).toDouble(),
                total: (s['total'] as num).toDouble(),
                paid: (s['paid'] as num).toDouble(),
                changeAmount: (s['changeAmount'] as num).toDouble(),
                paymentMethod: '${s['paymentMethod']}',
                status: status,
                secondaryCurrencyCode: Value('${s['secondaryCurrencyCode']}'),
                exchangeRateAtSale: Value((s['exchangeRateAtSale'] as num).toDouble()),
                uuid: Value(uuid),
              ),
            );
        saleIdByUuid[uuid] = saleId;
        newLinks.add((saleId: saleId, originalSaleUuid: s['originalSaleUuid'] as String?));

        for (final rawItem in (s['items'] as List? ?? const [])) {
          final i = rawItem as Map<String, dynamic>;
          final productId = productIdByUuid['${i['productUuid']}'] ??
              (await (_db.select(_db.products)..where((t) => t.uuid.equals('${i['productUuid']}')))
                      .getSingleOrNull())
                  ?.id;
          if (productId == null) {
            result.warnings.add('Invoice $invoiceNo: product "${i['name']}" not found, line skipped');
            continue;
          }
          final itemUuid = '${i['uuid']}';
          final itemId = await _db.into(_db.saleItems).insert(
                SaleItemsCompanion.insert(
                  saleId: saleId,
                  productId: productId,
                  nameSnapshot: '${i['name']}',
                  costSnapshot: (i['cost'] as num).toDouble(),
                  priceSnapshot: (i['price'] as num).toDouble(),
                  qty: (i['qty'] as num).toInt(),
                  discount: Value((i['discount'] as num).toDouble()),
                  lineTotal: (i['lineTotal'] as num).toDouble(),
                  taxable: Value(i['taxable'] == true),
                  uuid: Value(itemUuid),
                ),
              );
          itemIdByUuid[itemUuid] = itemId;
          final originalItemUuid = i['originalItemUuid'] as String?;
          if (originalItemUuid != null) {
            newItemLinks.add((itemId: itemId, originalItemUuid: originalItemUuid));
          }
        }
        result.newSales++;
      }

      // Return documents point at their original sale/item (second pass so
      // the order inside the file does not matter).
      for (final link in newLinks) {
        final originalUuid = link.originalSaleUuid;
        if (originalUuid == null) continue;
        final originalId = saleIdByUuid[originalUuid];
        if (originalId == null) continue;
        await (_db.update(_db.sales)..where((t) => t.id.equals(link.saleId))).write(
          SalesCompanion(originalSaleId: Value(originalId)),
        );
      }
      for (final link in newItemLinks) {
        final originalId = itemIdByUuid[link.originalItemUuid];
        if (originalId == null) continue;
        await (_db.update(_db.saleItems)..where((t) => t.id.equals(link.itemId))).write(
          SaleItemsCompanion(originalItemId: Value(originalId)),
        );
      }

      return result;
    });
  }
}
