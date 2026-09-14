import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/repositories/repositories.dart';

class FileExportService {
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
    final isRtl = lang == 'ar';
    final arabicFont = await PdfGoogleFonts.notoNaskhArabicRegular();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicFont, fontFallback: [arabicFont]);

    String fmtDate(DateTime d) => d.toIso8601String().substring(0, 10);

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (context) => [
          pw.Center(
            child: pw.Text(storeName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Center(child: pw.Text(t['title']!, style: const pw.TextStyle(fontSize: 13))),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text('${t['period']}: ${fmtDate(from)} → ${fmtDate(to)}')),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            children: [
              _summaryRow(t['invoicesSold']!, '$invoiceCount'),
              _summaryRow(t['totalSales']!, '${totalSales.toStringAsFixed(2)} $currency'),
              _summaryRow(t['invoicesReturned']!, '$returnCount'),
              _summaryRow(t['totalReturns']!, '${totalReturns.toStringAsFixed(2)} $currency'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(t['inventory']!, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1)},
            children: [
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(t['product']!, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(t['stock']!, style: pw.TextStyle(fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                  ),
                ],
              ),
              ...inventory.map(
                (row) => pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(row.name)),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('${row.stock}', textAlign: pw.TextAlign.center),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
