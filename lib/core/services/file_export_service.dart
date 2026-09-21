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
      'totalSales': 'إجمالي الفواتير المباعة',
      'invoicesReturned': 'عدد الفواتير المرتجعة',
      'totalReturns': 'إجمالي الفواتير المرتجعة',
      'inventory': 'جردة المخزون المتبقي',
      'product': 'الصنف',
      'stock': 'الكمية المتبقية',
    },
  };

  Future<File> generatePeriodReportPdf({
    required String storeName,
    required DateTime from,
    required DateTime to,
    required int invoiceCount,
    required double totalSales,
    required int returnCount,
    required double totalReturns,
    required List<InventoryReportRow> inventory,
    required String currency,
    String languageCode = 'en',
  }) async {
    final lang = _periodLabels.containsKey(languageCode) ? languageCode : 'en';
    final t = _periodLabels[lang]!;
    final arabicFont = await _loadArabicFont();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicFont, fontFallback: [arabicFont]);

    // Same rationale as the receipt: pdf reorders RTL text on its own but
    // doesn't join Arabic letters into their connected forms — shape (glyph
    // substitution only, doesn't move characters) so it composes with pdf's
    // own reordering instead of fighting it. Works regardless of language.
    String shape(String text) => ArabicReshaper.instance.reshape(text);

    String fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);

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
        // Always LTR at the page level — pdf's own bidi pass reorders any
        // embedded Arabic run correctly on its own; forcing the whole page
        // RTL here would double up with that and scramble the shaped text.
        textDirection: pw.TextDirection.ltr,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
          pw.Center(
            child: pw.Text(shape(storeName), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Center(child: pw.Text(shape(t['title']!), style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(height: 3),
          pw.Center(child: pw.Text(shape('${t['period']}: ${fmtDate(from)} → ${fmtDate(to)}'), style: const pw.TextStyle(fontSize: 8.5))),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(width: 0.4),
            children: [
              _summaryRow(shape(t['invoicesSold']!), '$invoiceCount'),
              _summaryRow(shape(t['totalSales']!), '${totalSales.toStringAsFixed(2)} $currency'),
              _summaryRow(shape(t['invoicesReturned']!), '$returnCount'),
              _summaryRow(shape(t['totalReturns']!), '${totalReturns.toStringAsFixed(2)} $currency'),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(shape(t['inventory']!), style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Table(
            border: pw.TableBorder.all(width: 0.4),
            columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1)},
            children: [
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(shape(t['product']!), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(shape(t['stock']!), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                  ),
                ],
              ),
              ...inventory.map(
                (row) => pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(shape(row.name), style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text('${row.stock}', style: const pw.TextStyle(fontSize: 8.5), textAlign: pw.TextAlign.center),
                    ),
                  ],
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

  pw.TableRow _summaryRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(label)),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(value)),
      ],
    );
  }

  Future<File> _writeCsv(String prefix, List<List<dynamic>> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(dir.path, fileName));
    final csv = const ListToCsvConverter().convert(rows);
    return file.writeAsString(csv);
  }
}
