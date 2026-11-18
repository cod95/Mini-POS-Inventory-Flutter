import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/app_entities.dart';

/// One data row read from the products sheet.
class ProductSheetRow {
  const ProductSheetRow({
    required this.rowNumber,
    required this.name,
    this.sku = '',
    this.barcode = '',
    this.category = '',
    this.cost,
    this.price,
    this.stock,
    this.lowStock,
    this.unit = '',
    this.taxable,
  });

  /// 1-based row number as the user sees it in Excel.
  final int rowNumber;
  final String name;
  final String sku;
  final String barcode;
  final String category;
  final double? cost;
  final double? price;
  final int? stock;
  final int? lowStock;
  final String unit;
  final bool? taxable;
}

class ProductSheetReadResult {
  const ProductSheetReadResult({required this.rows, required this.errors});

  final List<ProductSheetRow> rows;
  final List<String> errors;
}

/// Reads and writes .xlsx files: products template/export/import and a
/// sales export. Amounts handed in/out are already in the store's currency;
/// the caller does the USD conversion.
class ExcelService {
  static const String productsSheet = 'Products';

  /// Column order of the products sheet. Do not reorder: the import reads by
  /// position.
  static const List<String> productHeaders = [
    'Name / الاسم *',
    'SKU / الرمز',
    'Barcode / الباركود',
    'Category / القسم',
    'Cost / التكلفة',
    'Price / السعر',
    'Stock / الكمية',
    'Low stock alert / حد التنبيه',
    'Unit / الوحدة',
    'TVA (yes/no) / ضريبة (نعم/لا)',
  ];

  // ---------------------------------------------------------------- writing

  Future<File> buildProductsTemplate({required String currency}) async {
    final excel = Excel.createExcel();
    final sheet = excel[productsSheet];
    sheet.appendRow(productHeaders.map<CellValue?>((h) => TextCellValue(h)).toList());
    _styleHeader(sheet, productHeaders.length);
    _setWidths(sheet, const [28, 16, 20, 18, 12, 12, 12, 16, 12, 18]);

    final help = excel['Instructions / تعليمات'];
    final lines = <String>[
      'HOW TO FILL / طريقة التعبئة',
      '1) Fill the "Products" sheet, one product per row, starting at row 2. / عبّي صفحة Products، منتج بكل سطر، من السطر 2.',
      '2) Only Name is required. / الاسم هو الحقل الوحيد المطلوب.',
      '3) Cost and Price are in $currency. / التكلفة والسعر بعملة $currency.',
      '4) Stock = quantity you have now (whole number). / الكمية = الموجود حالياً (رقم صحيح).',
      '5) TVA: write yes or no (نعم / لا). / الضريبة: اكتب نعم أو لا.',
      '6) Category is created automatically if it does not exist. / القسم بينعمل لحاله إذا مش موجود.',
      '7) If SKU / Barcode / Name matches an existing product it is UPDATED, otherwise a new product is created. / إذا الرمز أو الباركود أو الاسم مطابق لمنتج موجود بيتعدّل، وإلا بينضاف جديد.',
      '8) Do not change the column order or delete the header row. / لا تغيّر ترتيب الأعمدة ولا تمسح سطر العناوين.',
      '',
      'EXAMPLE / مثال:',
      'Coffee | COF-01 | 6221234567890 | Drinks | 0.5 | 1.5 | 40 | 5 | piece | no',
    ];
    for (final line in lines) {
      help.appendRow([TextCellValue(line)]);
    }
    help.setColumnWidth(0, 120);

    excel.delete('Sheet1');
    excel.setDefaultSheet(productsSheet);
    return _save(excel, 'products_template');
  }

  Future<File> buildProductsExport({
    required List<ProductView> products,
    required String currency,
    required double Function(double usd) toStoreCurrency,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[productsSheet];
    sheet.appendRow(productHeaders.map<CellValue?>((h) => TextCellValue(h)).toList());
    _styleHeader(sheet, productHeaders.length);
    _setWidths(sheet, const [28, 16, 20, 18, 12, 12, 12, 16, 12, 18]);

    final decimals = currency == 'LBP' ? 0 : 2;
    double money(double usd) => double.parse(toStoreCurrency(usd).toStringAsFixed(decimals));

    for (final product in products) {
      sheet.appendRow([
        TextCellValue(product.name),
        TextCellValue(product.sku),
        TextCellValue(product.barcode ?? ''),
        TextCellValue(product.categoryName ?? ''),
        DoubleCellValue(money(product.cost)),
        DoubleCellValue(money(product.price)),
        IntCellValue(product.stockQty),
        IntCellValue(product.lowStockThreshold),
        TextCellValue(product.unit),
        TextCellValue(product.taxable ? 'yes' : 'no'),
      ]);
    }

    excel.delete('Sheet1');
    excel.setDefaultSheet(productsSheet);
    return _save(excel, 'inventory');
  }

  /// Two sheets: Invoices (one row per invoice/return) and Items (one row
  /// per line). Totals are written in USD and LBP using each invoice's own
  /// exchange rate.
  Future<File> buildSalesExport(List<SaleDetailView> invoices) async {
    final excel = Excel.createExcel();

    final head = excel['Invoices'];
    head.appendRow([
      'Invoice', 'Date', 'Customer', 'Type', 'Status', 'Payment',
      'Subtotal USD', 'Discount USD', 'TVA USD', 'Total USD', 'Total LBP',
    ].map<CellValue?>((h) => TextCellValue(h)).toList());
    _styleHeader(head, 11);
    _setWidths(head, const [20, 18, 20, 10, 14, 10, 12, 12, 10, 12, 14]);

    final items = excel['Items'];
    items.appendRow([
      'Invoice', 'Date', 'Item', 'Qty', 'Price USD', 'Cost USD', 'Line total USD', 'TVA',
    ].map<CellValue?>((h) => TextCellValue(h)).toList());
    _styleHeader(items, 8);
    _setWidths(items, const [20, 18, 28, 8, 12, 12, 14, 8]);

    for (final detail in invoices) {
      final sale = detail.sale;
      final date = _formatDate(sale.createdAt);
      head.appendRow([
        TextCellValue(sale.invoiceNo),
        TextCellValue(date),
        TextCellValue(sale.customerName ?? ''),
        TextCellValue(sale.isReturnDocument ? 'return' : 'sale'),
        TextCellValue(sale.status.name),
        TextCellValue(sale.paymentMethod.name),
        DoubleCellValue(_r2(sale.subtotal)),
        DoubleCellValue(_r2(sale.discountTotal)),
        DoubleCellValue(_r2(sale.taxTotal)),
        DoubleCellValue(_r2(sale.total)),
        DoubleCellValue(sale.total * sale.exchangeRateAtSale),
      ]);
      for (final item in detail.items) {
        items.appendRow([
          TextCellValue(sale.invoiceNo),
          TextCellValue(date),
          TextCellValue(item.nameSnapshot),
          IntCellValue(item.qty),
          DoubleCellValue(_r2(item.priceSnapshot)),
          DoubleCellValue(_r2(item.costSnapshot)),
          DoubleCellValue(_r2(item.lineTotal)),
          TextCellValue(item.taxable ? 'yes' : 'no'),
        ]);
      }
    }

    excel.delete('Sheet1');
    excel.setDefaultSheet('Invoices');
    return _save(excel, 'sales');
  }

  Future<void> share(File file) => Share.shareXFiles([XFile(file.path)]);

  // ---------------------------------------------------------------- reading

  Future<ProductSheetReadResult> readProducts(File file) async {
    final bytes = await file.readAsBytes();
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      return const ProductSheetReadResult(
        rows: [],
        errors: ['The file is not a valid .xlsx Excel file / الملف مش Excel صحيح (.xlsx)'],
      );
    }

    final sheet = excel.tables[productsSheet] ??
        (excel.tables.values.isEmpty ? null : excel.tables.values.first);
    if (sheet == null) {
      return const ProductSheetReadResult(rows: [], errors: ['No sheet found / ما في صفحة']);
    }

    final rows = <ProductSheetRow>[];
    final errors = <String>[];
    final all = sheet.rows;

    // Row 0 is the header row.
    for (var i = 1; i < all.length; i++) {
      final cells = all[i];
      String text(int col) => col < cells.length ? _cellText(cells[col]) : '';
      double? number(int col, String label) {
        final raw = text(col);
        if (raw.isEmpty) return null;
        final parsed = _parseNumber(raw);
        if (parsed == null) {
          errors.add('Row ${i + 1}: "$raw" is not a number ($label)');
        }
        return parsed;
      }

      final name = text(0);
      final isEmpty = List.generate(productHeaders.length, text).every((v) => v.isEmpty);
      if (isEmpty) continue;
      if (name.isEmpty) {
        errors.add('Row ${i + 1}: name is empty — skipped / الاسم فاضي، انتخطى');
        continue;
      }

      final cost = number(4, 'cost');
      final price = number(5, 'price');
      final stock = number(6, 'stock');
      final low = number(7, 'low stock');
      final taxRaw = text(9);

      rows.add(
        ProductSheetRow(
          rowNumber: i + 1,
          name: name,
          sku: text(1),
          barcode: text(2),
          category: text(3),
          cost: cost,
          price: price,
          stock: stock?.round(),
          lowStock: low?.round(),
          unit: text(8),
          taxable: taxRaw.isEmpty ? null : _parseYes(taxRaw),
        ),
      );
    }
    return ProductSheetReadResult(rows: rows, errors: errors);
  }

  // ---------------------------------------------------------------- helpers

  static String _cellText(Data? data) {
    final value = data?.value;
    if (value == null) return '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) {
      final d = value.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return value.toString().trim();
  }

  static double? _parseNumber(String raw) {
    final cleaned = raw.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(cleaned);
  }

  static bool _parseYes(String raw) {
    final v = raw.trim().toLowerCase();
    return const {'yes', 'y', 'true', '1', 'x', 'نعم', 'ايه', 'أيه', 'ايوه', 'أيوه', 'اي'}.contains(v);
  }

  static double _r2(double v) => double.parse(v.toStringAsFixed(2));

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static void _styleHeader(Sheet sheet, int columns) {
    for (var c = 0; c < columns; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('FFDDEBF7'));
    }
  }

  static void _setWidths(Sheet sheet, List<double> widths) {
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  Future<File> _save(Excel excel, String baseName) async {
    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('Could not create the Excel file');
    }
    final dir = await getTemporaryDirectory();
    final stamp = _formatDate(DateTime.now()).replaceAll(RegExp(r'[: ]'), '-');
    final file = File(p.join(dir.path, '${baseName}_$stamp.xlsx'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
