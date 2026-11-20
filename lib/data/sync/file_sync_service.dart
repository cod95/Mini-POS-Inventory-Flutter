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
  int deleted = 0;
  int usersChanged = 0;
  bool settingsApplied = false;
  String? assignedDeviceCode;
  String senderName = '';
  final List<String> warnings = [];

  /// True when the import changed something on this phone.
  bool get changedAnything =>
      newProducts + updatedProducts + newSales + updatedSales + appliedMovements + deleted + usersChanged > 0 ||
      settingsApplied;
}

/// The sync engine shared by file sync and Wi-Fi sync.
///
/// A package holds products, stock movements (each with a unique id), sales
/// with their items and deletions. Importing is safe any number of times:
/// rows already known are skipped, stock movements are applied once ever,
/// price edits follow the latest change (ties are broken the same way on
/// both phones) and a sale's status only moves forward.
///
/// The main phone is the hub: only it sends users and store settings, and a
/// main phone never accepts them from anyone.
class FileSyncService {
  FileSyncService(this._db);

  final AppDatabase _db;

  static const String _format = 'quickstock-sync';
  static const int _version = 3;

  // ------------------------------------------------------------- shop code

  Future<String?> getSyncCode() async {
    final row = await settings();
    final code = row.syncCode;
    return (code == null || code.isEmpty) ? null : SyncCrypto.pretty(code);
  }

  /// Creates a new random shop code and makes this phone the main phone.
  Future<String> createSyncCode() async {
    final code = SyncCrypto.generateCode();
    await settings();
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(syncCode: Value(code), isMainDevice: const Value(true)),
    );
    return code;
  }

  /// Stores the code typed in from the main phone (this phone is then an
  /// employee phone). Throws FormatException when it is not a shop code.
  Future<void> setSyncCode(String code) async {
    if (!SyncCrypto.isValidCode(code)) throw const FormatException('BAD_CODE');
    await settings();
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(syncCode: Value(SyncCrypto.pretty(code)), isMainDevice: const Value(false)),
    );
  }

  /// Automatic sync on/off and the typed address of the main phone.
  Future<void> updateSyncOptions({bool? autoSync, String? hubAddress, bool clearHubAddress = false}) async {
    await settings();
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(
        autoSync: autoSync == null ? const Value.absent() : Value(autoSync),
        hubAddress: clearHubAddress
            ? const Value(null)
            : (hubAddress == null ? const Value.absent() : Value(hubAddress.trim())),
      ),
    );
  }

  Future<Uint8List> key() async {
    final code = await getSyncCode();
    if (code == null) throw const FormatException('NO_SYNC_CODE');
    return SyncCrypto.deriveKey(code);
  }

  Future<AppSetting> settings() async {
    final row = await (_db.select(_db.appSettings)..where((t) => t.id.equals(1))).getSingle();
    if (row.deviceId != null && row.deviceId!.isNotEmpty) return row;
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(deviceId: Value(newUuid())),
    );
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(1))).getSingle();
  }

  // ------------------------------------------------------------- file sync

  Future<File> exportToFile() async {
    final k = await key();
    final data = await buildPackage();
    final json = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final encrypted = await Isolate.run(
      () => SyncCrypto.encryptSync(Uint8List.fromList(gzip.encode(json)), k),
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

  Future<SyncImportResult> importFromFile(File file) async {
    final raw = await file.readAsBytes();
    if (!SyncCrypto.hasMagic(raw)) {
      throw const FormatException('NOT_A_SYNC_FILE');
    }
    final k = await key();
    final Map<String, dynamic> data;
    try {
      final body = Uint8List.sublistView(raw, SyncCrypto.magic.length);
      final plain = await Isolate.run(
        () => Uint8List.fromList(gzip.decode(SyncCrypto.decryptSync(body, k))),
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
    return importPackage(data);
  }

  // --------------------------------------------------------------- package

  static String _date(DateTime d) => d.toUtc().toIso8601String();

  /// Everything that changed on this phone since [since] (everything when
  /// null). The main phone also adds users and store settings.
  Future<Map<String, dynamic>> buildPackage({DateTime? since}) async {
    final mine = await settings();
    // A little overlap: rows are de-duplicated on arrival.
    final from = since?.subtract(const Duration(seconds: 5));

    final categories = await _db.select(_db.categories).get();
    final categoryName = {for (final c in categories) c.id: c.name};
    final allProducts = await _db.select(_db.products).get();
    final productUuid = {for (final p in allProducts) p.id: p.uuid};

    final products = from == null
        ? allProducts
        : allProducts.where((p) => p.changedAt == null || !p.changedAt!.isBefore(from)).toList();

    final movementQuery = _db.select(_db.stockMovements);
    if (from != null) {
      movementQuery.where((t) => t.changedAt.isBiggerOrEqualValue(from) | t.changedAt.isNull());
    }
    final movements = await movementQuery.get();

    final salesQuery = _db.select(_db.sales);
    if (from != null) {
      salesQuery.where((t) => t.changedAt.isBiggerOrEqualValue(from) | t.changedAt.isNull());
    }
    final sales = await salesQuery.get();
    final allSales = from == null ? sales : await _db.select(_db.sales).get();
    final saleUuid = {for (final s in allSales) s.id: s.uuid};

    final saleIds = sales.map((s) => s.id).toSet();
    final allItems = await _db.select(_db.saleItems).get();
    final itemUuid = {for (final i in allItems) i.id: i.uuid};
    final itemsBySale = <int, List<SaleItem>>{};
    for (final item in allItems) {
      if (saleIds.contains(item.saleId)) {
        itemsBySale.putIfAbsent(item.saleId, () => []).add(item);
      }
    }

    final deletedQuery = _db.select(_db.deletedRecords);
    if (from != null) {
      deletedQuery.where((t) => t.deletedAt.isBiggerOrEqualValue(from));
    }
    final deleted = await deletedQuery.get();

    final data = <String, dynamic>{
      'format': _format,
      'version': _version,
      'deviceId': mine.deviceId,
      'deviceCode': mine.deviceCode,
      'storeName': mine.storeName,
      'exportedAt': _date(DateTime.now()),
      'full': since == null,
      'categories': categories.map((c) => c.name).toList(),
      'deleted': [
        for (final d in deleted) {'uuid': d.uuid, 'kind': d.kind, 'at': _date(d.deletedAt)},
      ],
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
          if (productUuid[m.productId] != null)
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
                  'isFree': i.isFree,
                  'originalItemUuid': i.originalItemId == null ? null : itemUuid[i.originalItemId],
                },
            ],
          },
      ],
    };

    if (mine.isMainDevice) {
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
        'storeName': mine.storeName,
        'storePhone': mine.storePhone,
        'currency': mine.currency,
        'secondaryCurrencyCode': mine.secondaryCurrencyCode,
        'exchangeRate': mine.exchangeRate,
        'taxEnabled': mine.taxEnabled,
        'taxRate': mine.taxRate,
        'receiptHeader': mine.receiptHeader,
        'receiptFooter': mine.receiptFooter,
        'allowNegativeStock': mine.allowNegativeStock,
      };
    }
    return data;
  }

  // ----------------------------------------------------------------- import

  static DateTime _parse(Object? v) => DateTime.tryParse('$v')?.toLocal() ?? DateTime.now();

  /// A clock that runs far ahead must not win every price conflict.
  static DateTime _parseEdit(Object? v) {
    final parsed = _parse(v);
    final limit = DateTime.now().add(const Duration(minutes: 10));
    return parsed.isAfter(limit) ? limit : parsed;
  }

  static bool _isDefaultSecret(String secret) => secret == 'admin123' || secret == '1234';

  /// Same answer on both phones, so a tie never leaves them different.
  static bool _incomingWins(DateTime incoming, DateTime local, String senderId, String myId) {
    if (incoming.isAfter(local)) return true;
    if (incoming.isBefore(local)) return false;
    return senderId.compareTo(myId) > 0;
  }

  static const Map<String, int> _statusRank = {
    'completed': 0,
    'partial': 1,
    'returned': 2,
    'cancelled': 3,
  };

  Future<SyncImportResult> importPackage(Map<String, dynamic> data) {
    return _db.transaction(() async {
      final result = SyncImportResult()..senderName = '${data['storeName'] ?? ''}';
      final mine = await settings();
      final senderId = '${data['deviceId'] ?? ''}';
      final myId = mine.deviceId ?? '';
      final senderCode = '${data['deviceCode'] ?? ''}';
      final senderIsMain = data['fromAdmin'] == true;
      final now = DateTime.now();

      // ---- device code so two phones never issue the same invoice number
      if (senderId != myId && mine.deviceCode == senderCode) {
        final random = Random();
        final code = 'D${10 + random.nextInt(90)}';
        await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
          AppSettingsCompanion(deviceCode: Value(code)),
        );
        result.assignedDeviceCode = code;
      }

      // ---- deletions (own and received)
      final tombstones = <String, DateTime>{
        for (final d in await _db.select(_db.deletedRecords).get()) d.uuid: d.deletedAt,
      };
      for (final raw in (data['deleted'] as List? ?? const [])) {
        final d = raw as Map<String, dynamic>;
        final uuid = '${d['uuid']}';
        final kind = '${d['kind']}';
        final at = _parse(d['at']);
        if (kind == 'user' && !(senderIsMain && !mine.isMainDevice)) continue;
        final known = tombstones[uuid];
        if (known == null || at.isAfter(known)) {
          await _db.into(_db.deletedRecords).insertOnConflictUpdate(
                DeletedRecordsCompanion.insert(
                  uuid: uuid,
                  kind: Value(kind),
                  deletedAt: Value(at),
                ),
              );
          tombstones[uuid] = at;
        }
        if (kind == 'product') {
          final local = await (_db.select(_db.products)..where((t) => t.uuid.equals(uuid)))
              .getSingleOrNull();
          if (local != null && !(local.catalogUpdatedAt ?? local.updatedAt).isAfter(at)) {
            await (_db.delete(_db.products)..where((t) => t.id.equals(local.id))).go();
            result.deleted++;
          }
        } else if (kind == 'user') {
          final local = await (_db.select(_db.userAccounts)..where((t) => t.uuid.equals(uuid)))
              .getSingleOrNull();
          if (local != null) {
            final admins = await (_db.select(_db.userAccounts)
                  ..where((t) => t.role.equals('admin') & t.active.equals(true)))
                .get();
            final lastAdmin = local.role == 'admin' && admins.every((a) => a.id == local.id);
            if (!lastAdmin) {
              await (_db.delete(_db.userAccounts)..where((t) => t.id.equals(local.id))).go();
              result.usersChanged++;
            }
          }
        }
      }

      // ---- users + store settings: only the main phone sends them and the
      // main phone never accepts them.
      if (senderIsMain && !mine.isMainDevice) {
        final localUsers = await _db.select(_db.userAccounts).get();
        final usedNames = {for (final u in localUsers) u.name.toLowerCase(): u.uuid};
        for (final raw in (data['users'] as List? ?? const [])) {
          final u = raw as Map<String, dynamic>;
          final uuid = '${u['uuid']}';
          if (tombstones.containsKey(uuid)) continue;
          final existing = await (_db.select(_db.userAccounts)..where((t) => t.uuid.equals(uuid)))
              .getSingleOrNull();
          final incomingAt = _parseEdit(u['updatedAt']);

          String uniqueName(String wanted) {
            var candidate = wanted;
            var n = 2;
            while (usedNames[candidate.toLowerCase()] != null &&
                usedNames[candidate.toLowerCase()] != uuid) {
              candidate = '$wanted ($n)';
              n++;
            }
            return candidate;
          }

          if (existing == null) {
            final name = uniqueName('${u['name']}');
            usedNames[name.toLowerCase()] = uuid;
            await _db.into(_db.userAccounts).insert(
                  UserAccountsCompanion.insert(
                    uuid: uuid,
                    name: name,
                    role: '${u['role']}',
                    secret: '${u['secret']}',
                    mustChangeSecret: Value(_isDefaultSecret('${u['secret']}')),
                    active: Value(u['active'] == true),
                    updatedAt: Value(incomingAt),
                  ),
                );
            result.usersChanged++;
          } else if (_incomingWins(incomingAt, existing.updatedAt, senderId, myId) &&
              (incomingAt != existing.updatedAt || '${u['secret']}' != existing.secret)) {
            final name = uniqueName('${u['name']}');
            usedNames[name.toLowerCase()] = uuid;
            await (_db.update(_db.userAccounts)..where((t) => t.id.equals(existing.id))).write(
              UserAccountsCompanion(
                name: Value(name),
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
      final skuOwner = {for (final p in localProducts) p.sku.toLowerCase(): p.id};
      final barcodeOwner = {
        for (final p in localProducts)
          if ((p.barcode ?? '').isNotEmpty) p.barcode!.toLowerCase(): p.id,
      };
      final nameOwner = {for (final p in localProducts) p.name.toLowerCase(): p.id};
      final productsById = {for (final p in localProducts) p.id: p};

      // Every local product is reachable by its uuid, even when it is not in
      // this package (its stock movements may be).
      final productIdByUuid = <String, int>{
        for (final p in localProducts) if (p.uuid != null) p.uuid!: p.id,
      };
      // Products first seen (or linked) in this package: their movements in
      // this package are already inside the stock figure that came with them.
      final baselineProducts = <String>{};

      String freeSku(String sku, int? ownId, String uuid) {
        final owner = skuOwner[sku.toLowerCase()];
        if (owner == null || owner == ownId) return sku;
        final short = uuid.length >= 4 ? uuid.substring(0, 4) : uuid;
        var candidate = '$sku-$short';
        var n = 2;
        while (skuOwner.containsKey(candidate.toLowerCase())) {
          candidate = '$sku-$short$n';
          n++;
        }
        return candidate;
      }

      String? freeBarcode(String? barcode, int? ownId) {
        if (barcode == null || barcode.isEmpty) return null;
        final owner = barcodeOwner[barcode.toLowerCase()];
        if (owner == null || owner == ownId) return barcode;
        return null;
      }

      bool sameCatalog(Product local, Map<String, dynamic> p) =>
          local.name == '${p['name']}' &&
          local.sku == '${p['sku']}' &&
          (local.barcode ?? '') == ((p['barcode'] as String?)?.trim() ?? '') &&
          local.cost == (p['cost'] as num).toDouble() &&
          local.price == (p['price'] as num).toDouble() &&
          local.lowStockThreshold == (p['lowStockThreshold'] as num).toInt() &&
          local.unit == '${p['unit']}' &&
          (local.notes ?? '') == ((p['notes'] as String?) ?? '') &&
          local.taxable == (p['taxable'] == true);

      for (final raw in (data['products'] as List? ?? const [])) {
        final p = raw as Map<String, dynamic>;
        final uuid = '${p['uuid']}';
        final name = '${p['name']}';
        final wantedSku = '${p['sku']}';
        final wantedBarcode = (p['barcode'] as String?)?.trim();
        final incomingAt = _parseEdit(p['catalogUpdatedAt']);

        final deletedAt = tombstones[uuid];
        if (deletedAt != null && !incomingAt.isAfter(deletedAt)) continue;

        try {
          final catId = await categoryId(p['category'] as String?);
          final local = byUuid[uuid];

          if (local != null) {
            final localAt = local.catalogUpdatedAt ?? local.updatedAt;
            if (_incomingWins(incomingAt, localAt, senderId, myId) && !sameCatalog(local, p)) {
              final sku = freeSku(wantedSku, local.id, uuid);
              final barcode = freeBarcode(wantedBarcode, local.id);
              await (_db.update(_db.products)..where((t) => t.id.equals(local.id))).write(
                ProductsCompanion(
                  name: Value(name),
                  sku: Value(sku),
                  barcode: Value(barcode),
                  categoryId: Value(catId),
                  cost: Value((p['cost'] as num).toDouble()),
                  price: Value((p['price'] as num).toDouble()),
                  lowStockThreshold: Value((p['lowStockThreshold'] as num).toInt()),
                  unit: Value('${p['unit']}'),
                  notes: Value(p['notes'] as String?),
                  taxable: Value(p['taxable'] == true),
                  catalogUpdatedAt: Value(incomingAt),
                  updatedAt: Value(now),
                ),
              );
              skuOwner.remove(local.sku.toLowerCase());
              skuOwner[sku.toLowerCase()] = local.id;
              if ((local.barcode ?? '').isNotEmpty) barcodeOwner.remove(local.barcode!.toLowerCase());
              if (barcode != null) barcodeOwner[barcode.toLowerCase()] = local.id;
              if (sku != wantedSku || barcode != wantedBarcode && (wantedBarcode ?? '').isNotEmpty) {
                result.warnings.add('"$name": SKU/barcode already used by another product, adjusted');
              }
              result.updatedProducts++;
            }
            continue;
          }

          // Not known by uuid: the same product typed in on both phones?
          final matchId = skuOwner[wantedSku.toLowerCase()] ??
              ((wantedBarcode ?? '').isNotEmpty ? barcodeOwner[wantedBarcode!.toLowerCase()] : null) ??
              nameOwner[name.toLowerCase()];
          final match = matchId == null ? null : productsById[matchId];

          if (match != null) {
            final sku = freeSku(wantedSku, match.id, uuid);
            final barcode = freeBarcode(wantedBarcode, match.id);
            await (_db.update(_db.products)..where((t) => t.id.equals(match.id))).write(
              ProductsCompanion(
                name: Value(name),
                sku: Value(sku),
                barcode: Value(barcode),
                categoryId: Value(catId),
                cost: Value((p['cost'] as num).toDouble()),
                price: Value((p['price'] as num).toDouble()),
                lowStockThreshold: Value((p['lowStockThreshold'] as num).toInt()),
                unit: Value('${p['unit']}'),
                notes: Value(p['notes'] as String?),
                taxable: Value(p['taxable'] == true),
                catalogUpdatedAt: Value(incomingAt),
                updatedAt: Value(now),
                uuid: Value(uuid),
                // The main phone's stock is the truth; an employee phone's
                // figure never overwrites the main phone's.
                stockQty: senderIsMain ? Value((p['stockQty'] as num).toInt()) : const Value.absent(),
              ),
            );
            skuOwner.remove(match.sku.toLowerCase());
            skuOwner[sku.toLowerCase()] = match.id;
            productIdByUuid[uuid] = match.id;
            baselineProducts.add(uuid);
            result.updatedProducts++;
          } else {
            final sku = freeSku(wantedSku, null, uuid);
            final barcode = freeBarcode(wantedBarcode, null);
            final id = await _db.into(_db.products).insert(
                  ProductsCompanion.insert(
                    name: name,
                    sku: sku,
                    barcode: Value(barcode),
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
            skuOwner[sku.toLowerCase()] = id;
            if (barcode != null) barcodeOwner[barcode.toLowerCase()] = id;
            nameOwner[name.toLowerCase()] = id;
            productIdByUuid[uuid] = id;
            baselineProducts.add(uuid);
            result.newProducts++;
            if (sku != wantedSku) {
              result.warnings.add('"$name": SKU $wantedSku already used by another product, now $sku');
            }
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
          final productId = productIdByUuid['${i['productUuid']}'];
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
                  isFree: Value(i['isFree'] == true),
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
      // the order inside the package does not matter).
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
