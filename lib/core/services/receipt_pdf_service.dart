import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/app_entities.dart';
import '../../domain/repositories/repositories.dart';

class ReceiptPdfService {
  ReceiptPdfService({required PrinterService printerService})
      : _printerService = printerService;

  final PrinterService _printerService;

  Future<File> generateReceipt({
    required SaleView sale,
    required List<SaleItemView> items,
    required String storeName,
    required String header,
    required String footer,
    required String currency,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  storeName,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(header)),
              pw.SizedBox(height: 8),
              pw.Text('Invoice: ${sale.invoiceNo}'),
              pw.Text('Date: ${sale.createdAt}'),
              pw.Divider(),
              ...items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text('${item.nameSnapshot} x${item.qty}'),
                      ),
                      pw.Text('${item.lineTotal.toStringAsFixed(2)} $currency'),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              pw.Text('Subtotal: ${sale.subtotal.toStringAsFixed(2)} $currency'),
              pw.Text('Discount: ${sale.discountTotal.toStringAsFixed(2)} $currency'),
              pw.Text('Tax: ${sale.taxTotal.toStringAsFixed(2)} $currency'),
              pw.Text('Total: ${sale.total.toStringAsFixed(2)} $currency'),
              pw.Text('Paid: ${sale.paid.toStringAsFixed(2)} $currency'),
              pw.Text('Change: ${sale.changeAmount.toStringAsFixed(2)} $currency'),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text(footer)),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, '${sale.invoiceNo}.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> sharePdf(File file) {
    return Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> printPdf(File file) {
    return Printing.layoutPdf(onLayout: (_) => file.readAsBytes());
  }

  Future<void> printThroughStub(File file) async {
    final bytes = await file.readAsBytes();
    await _printerService.printReceiptPdfBytes(bytes);
  }
}
