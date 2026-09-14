import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../domain/entities/app_entities.dart';
import '../../domain/repositories/repositories.dart';

class BluetoothPrinterDevice {
  const BluetoothPrinterDevice({required this.name, required this.macAddress});

  final String name;
  final String macAddress;
}

/// Talks directly to a paired Bluetooth thermal receipt printer using the
/// ESC/POS protocol — this bypasses the OS print dialog entirely, so there
/// is no "A4 by default" problem, and the ticket is generated at exactly
/// the paper width the store owner picked for their printer (58mm / 80mm).
class BluetoothPrinterService {
  static const Map<String, Map<String, String>> _labels = {
    'en': {
      'invoice': 'Invoice',
      'customer': 'Customer',
      'noName': 'No name',
      'totalUsd': 'Total (USD)',
      'totalLbp': 'Total (LBP)',
      'totalAfterTax': 'Total after TVA',
      'itemCount': 'Item count',
      'title': 'Period Report',
      'period': 'Period',
      'invoicesSold': 'Invoices sold',
      'totalSales': 'Total sales',
      'invoicesReturned': 'Invoices returned',
      'totalReturns': 'Total returns',
    },
    'ar': {
      'invoice': 'رقم الفاتورة',
      'customer': 'الزبون',
      'noName': 'بدون اسم',
      'totalUsd': 'المجموع بالدولار',
      'totalLbp': 'المجموع باللبناني',
      'totalAfterTax': 'المجموع بعد TVA',
      'itemCount': 'عدد الأصناف',
      'title': 'تقرير الفترة',
      'period': 'الفترة',
      'invoicesSold': 'عدد الفواتير المباعة',
      'totalSales': 'إجمالي الفواتير المباعة',
      'invoicesReturned': 'عدد الفواتير المرتجعة',
      'totalReturns': 'إجمالي الفواتير المرتجعة',
    },
  };

  Map<String, String> _t(String languageCode) => _labels[languageCode] ?? _labels['en']!;

  /// Same rationale as the PDF receipt: ESC/POS printers don't join Arabic
  /// letters into their connected forms either, so reshape before sending.
  String _shape(String text) => ArabicReshaper.instance.reshape(text);

  /// Requests the Bluetooth permissions Android 12+ needs before any scan
  /// or connect call. Safe to call every time — it's a no-op once granted.
  Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<List<BluetoothPrinterDevice>> pairedDevices() async {
    final granted = await ensurePermissions();
    if (!granted) return const [];
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices
        .map((d) => BluetoothPrinterDevice(name: d.name, macAddress: d.macAdress))
        .toList();
  }

  Future<bool> connect(String macAddress) async {
    await ensurePermissions();
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<void> disconnect() => PrintBluetoothThermal.disconnect;

  PaperSize _paperSize(String widthMm) => widthMm == '58' ? PaperSize.mm58 : PaperSize.mm80;

  Future<bool> printReceipt({
    required SaleView sale,
    required List<SaleItemView> items,
    required String storeName,
    String? storePhone,
    required String header,
    required String footer,
    required String currency,
    required double exchangeRate,
    required String paperWidthMm,
    String languageCode = 'en',
  }) async {
    final t = _t(languageCode);
    final profile = await CapabilityProfile.load();
    final generator = Generator(_paperSize(paperWidthMm), profile);
    final bytes = <int>[];

    final currencyDecimals = currency == 'LBP' ? 0 : 2;
    double toMain(double usdAmount) => currency == 'LBP' ? usdAmount * exchangeRate : usdAmount;
    final preTaxTotal = sale.total - sale.taxTotal;
    final itemCount = items.fold<int>(0, (sum, item) => sum + item.qty);
    final customerLabel = (sale.customerName == null || sale.customerName!.trim().isEmpty)
        ? t['noName']!
        : sale.customerName!.trim();

    bytes.addAll(generator.text(
      _shape(storeName),
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
    ));
    if (storePhone != null && storePhone.trim().isNotEmpty) {
      bytes.addAll(generator.text(_shape(storePhone.trim()), styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(generator.text(_shape(header), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text(_shape('${t['invoice']}: ${sale.invoiceNo}')));
    bytes.addAll(generator.text(sale.createdAt.toString().substring(0, 16)));
    bytes.addAll(generator.text(_shape('${t['customer']}: $customerLabel')));
    bytes.addAll(generator.hr());
    bytes.addAll(
      generator.row([
        PosColumn(text: 'Item', width: 5, styles: const PosStyles(bold: true)),
        PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
        PosColumn(text: 'Price', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
        PosColumn(text: 'Total', width: 3, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]),
    );
    for (final item in items) {
      final name = _shape(item.taxable ? '${item.nameSnapshot} [TVA]' : item.nameSnapshot);
      bytes.addAll(
        generator.row([
          PosColumn(text: name, width: 5),
          PosColumn(text: '${item.qty}', width: 2, styles: const PosStyles(align: PosAlign.center)),
          PosColumn(
            text: toMain(item.priceSnapshot).toStringAsFixed(currencyDecimals),
            width: 2,
            styles: const PosStyles(align: PosAlign.right),
          ),
          PosColumn(
            text: toMain(item.lineTotal).toStringAsFixed(currencyDecimals),
            width: 3,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    bytes.addAll(generator.hr());
    bytes.addAll(_totalRow(generator, _shape(t['totalUsd']!), '${preTaxTotal.toStringAsFixed(2)} USD'));
    bytes.addAll(_totalRow(generator, _shape(t['totalLbp']!), '${(preTaxTotal * exchangeRate).toStringAsFixed(0)} LBP'));
    if (sale.taxTotal > 0) {
      bytes.addAll(_totalRow(
        generator,
        _shape(t['totalAfterTax']!),
        '${toMain(sale.total).toStringAsFixed(currencyDecimals)} $currency',
        bold: true,
      ));
    }
    bytes.addAll(_totalRow(generator, _shape(t['itemCount']!), '$itemCount'));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.text(_shape(footer), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return PrintBluetoothThermal.writeBytes(bytes);
  }

  Future<bool> printPeriodReport({
    required String storeName,
    required DateTime from,
    required DateTime to,
    required int invoiceCount,
    required double totalSales,
    required int returnCount,
    required double totalReturns,
    required List<InventoryReportRow> inventory,
    required String currency,
    required String paperWidthMm,
    String languageCode = 'en',
  }) async {
    final t = _t(languageCode);
    final profile = await CapabilityProfile.load();
    final generator = Generator(_paperSize(paperWidthMm), profile);
    final bytes = <int>[];

    String fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);

    bytes.addAll(generator.text(
      _shape(storeName),
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
    ));
    bytes.addAll(generator.text(_shape(t['title']!), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(_shape('${t['period']}: ${fmtDate(from)} - ${fmtDate(to)}'), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr());
    bytes.addAll(_totalRow(generator, _shape(t['invoicesSold']!), '$invoiceCount'));
    bytes.addAll(_totalRow(generator, _shape(t['totalSales']!), '${totalSales.toStringAsFixed(2)} $currency'));
    bytes.addAll(_totalRow(generator, _shape(t['invoicesReturned']!), '$returnCount'));
    bytes.addAll(_totalRow(generator, _shape(t['totalReturns']!), '${totalReturns.toStringAsFixed(2)} $currency'));
    bytes.addAll(generator.hr());
    for (final row in inventory) {
      bytes.addAll(
        generator.row([
          PosColumn(text: _shape(row.name), width: 9),
          PosColumn(text: '${row.stock}', width: 3, styles: const PosStyles(align: PosAlign.right)),
        ]),
      );
    }
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return PrintBluetoothThermal.writeBytes(bytes);
  }

  List<int> _totalRow(Generator generator, String label, String value, {bool bold = false}) {
    return generator.row([
      PosColumn(text: label, width: 8, styles: PosStyles(bold: bold)),
      PosColumn(text: value, width: 4, styles: PosStyles(bold: bold, align: PosAlign.right)),
    ]);
  }
}
