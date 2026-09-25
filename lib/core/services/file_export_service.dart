import 'dart:io';

import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/repositories/repositories.dart';

class FileExportService {
  pw.Font? _arabicFont;

  Future<pw.Font> _loadArabicFont() async {
    if (_arabicFont != null) return _arabicFont!;
    final data = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
    return _arabicFont = pw.Font.ttf(data);
  }

  Future<File> exportSalesCsv(List<SalesReportRow> rows) async {
    final csvRows = <List<dynamic>>[
      ['invoice_no', 'date', 'total', 'payment_method', 'status'],
      ...rows.map(
        (row) => [
          row.invoiceNo,
          row.date.toIso8601String(),
          row.total.toStringAsFixed(2),
          row.paymentMethod,
          row.status,
        ],
      ),
    ];

    return _writeCsv('sales_report', csvRows);
  }

  Future<File> exportInventoryCsv(List<InventoryReportRow> rows) async {
    final csvRows = <List<dynamic>>[
      ['name', 'sku', 'category', 'stock', 'cost', 'price', 'low_stock'],
      ...rows.map(
        (row) => [
          row.name,
          row.sku,
          row.category,
          row.stock,
          row.cost.toStringAsFixed(2),
          row.price.toStringAsFixed(2),
          row.lowStock,
        ],
      ),
    ];

    return _writeCsv('inventory_report', csvRows);
  }

  Future<void> shareFile(File file) {
    return Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> printFile(File file) {
    return Printing.layoutPdf(onLayout: (_) => file.readAsBytes());
  }

  static const Map<String, Map<String, String>> _periodLabels = {
    'en': {
      'title': 'Period Report',
      'period': 'Period',
      'invoicesSold': 'Invoices sold',
      'totalSales': 'Total sales',
      'totalCost': 'Total cost',
      'totalProfit': 'Total profit',
      'invoicesReturned': 'Invoices returned',
      'totalReturns': 'Total returns',
      'inventory': 'Remaining inventory',
      'product': 'Product',
      'stock': 'Stock',
    },
    'ar': {
      'title': 'تقرير الفترة',
      'period': 'الفترة',
      'invoicesSold': 'عدد الفواتير المباعة',
      'totalSales': 'إجمالي المبيعات',
      'totalCost': 'إجمالي الكلفة',
      'totalProfit': 'إجمالي الربح',
      'invoicesReturned': 'عدد الفواتير المرتجعة',
      'totalReturns': 'إجمالي المرتجعات',
      'inventory': 'جردة المخزون المتبقي',
      'product': 'الصنف',
      'stock': 'الكمية المتبقية',
    },
  };

  static final RegExp _arabicPattern =
      RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

  /// Same approach as the (working) receipt: each text picks its own
  /// direction from its content, and Arabic is shaped (letters joined).
  /// Product names are printed exactly as stored — never translated.
  pw.Widget _dirText(String text, pw.TextStyle style, {pw.TextAlign? textAlign}) {
    final isArabic = _arabicPattern.hasMatch(text);
    return pw.Directionality(
      textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      child: pw.Text(
        isArabic ? ArabicReshaper.instance.reshape(text) : text,
        style: style,
        textAlign: textAlign,
      ),
    );
  }

  Future<File> generatePeriodReportPdf({
    required String storeName,
    required DateTime from,
    required DateTime to,
    required int invoiceCount,
    required double totalSales,
    required double totalCost,
    required double totalProfit,
    required int returnCount,
    required double totalReturns,
    required List<InventoryReportRow> inventory,
    required String currency,
    String languageCode = 'en',
  }) async {
    final lang = _periodLabels.containsKey(languageCode) ? languageCode : 'en';
    final t = _periodLabels[lang]!;
    final isRtl = lang == 'ar';
    final arabicFont = await _loadArabicFont();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicFont, fontFallback: [arabicFont]);

    String fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);
    final decimals = currency == 'LBP' ? 0 : 2;
    String money(double v) => '${v.toStringAsFixed(decimals)} $currency';

    const normal = pw.TextStyle(fontSize: 8.5);
    final bold = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    // Arabic report: label column on the right, like a normal Arabic table.
    List<pw.Widget> cells(pw.Widget label, pw.Widget value) => isRtl ? [value, label] : [label, value];
    final labelAlign = isRtl ? pw.TextAlign.right : pw.TextAlign.left;

    pw.TableRow summaryRow(String label, String value, {bool strong = false}) => pw.TableRow(
          children: cells(
            pw.Padding(padding: const pw.EdgeInsets.all(4), child: _dirText(label, strong ? bold : normal, textAlign: labelAlign)),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(value, style: strong ? bold : normal, textAlign: pw.TextAlign.center),
            ),
          ),
        );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        // Receipt-width roll paper, matching the invoice — not A4.
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 8,
          marginRight: 8,
          marginTop: 8,
          marginBottom: 8,
        ),
        // Page stays LTR; each text sets its own direction via _dirText.
        textDirection: pw.TextDirection.ltr,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: _dirText(storeName, pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
            pw.Center(child: _dirText(t['title']!, const pw.TextStyle(fontSize: 10))),
            pw.SizedBox(height: 3),
            // Label and dates are separate widgets (no arrow glyph — the
            // bundled font has none, it printed as a black box).
            pw.Center(
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: cells(
                  _dirText('${t['period']}:', normal),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 3),
                    child: pw.Text('${fmtDate(from)} - ${fmtDate(to)}', style: normal),
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              columnWidths: isRtl
                  ? const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(3)}
                  : const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
              children: [
                summaryRow(t['invoicesSold']!, '$invoiceCount'),
                summaryRow(t['totalSales']!, money(totalSales)),
                summaryRow(t['totalCost']!, money(totalCost)),
                summaryRow(t['totalProfit']!, money(totalProfit), strong: true),
                summaryRow(t['invoicesReturned']!, '$returnCount'),
                summaryRow(t['totalReturns']!, money(totalReturns)),
              ],
            ),
            pw.SizedBox(height: 12),
            _dirText(t['inventory']!, pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold), textAlign: labelAlign),
            pw.SizedBox(height: 5),
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              columnWidths: isRtl
                  ? const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(4)}
                  : const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1)},
              children: [
                pw.TableRow(
                  children: cells(
                    pw.Padding(padding: const pw.EdgeInsets.all(3), child: _dirText(t['product']!, bold, textAlign: labelAlign)),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: _dirText(t['stock']!, bold, textAlign: pw.TextAlign.center),
                    ),
                  ),
                ),
                ...inventory.map(
                  (row) => pw.TableRow(
                    children: cells(
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: _dirText(row.name, normal, textAlign: labelAlign)),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Text('${row.stock}', style: normal, textAlign: pw.TextAlign.center),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'period_report_${DateTime.now().millisecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> _writeCsv(String prefix, List<List<dynamic>> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(dir.path, fileName));
    final csv = const ListToCsvConverter().convert(rows);
    return file.writeAsString(csv);
  }
}
