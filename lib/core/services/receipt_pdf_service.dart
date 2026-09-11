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

  static const Map<String, Map<String, String>> _labels = {
    'en': {
      'invoice': 'Invoice',
      'customer': 'Customer',
      'noName': 'No name',
      'item': 'Item',
      'qty': 'Qty',
      'price': 'Price',
      'total': 'Total',
      'totalUsd': 'Total (USD)',
      'totalLbp': 'Total (LBP)',
      'totalAfterTax': 'Total after TVA',
      'itemCount': 'Item count',
    },
    'ar': {
      'invoice': 'رقم الفاتورة',
      'customer': 'الزبون',
      'noName': 'بدون اسم',
      'item': 'الصنف',
      'qty': 'الكمية',
      'price': 'سعر',
      'total': 'الاجمالي',
      'totalUsd': 'التوتال بالدولار',
      'totalLbp': 'التوتال باللبناني',
      'totalAfterTax': 'التوتال بعد إضافة TVA',
      'itemCount': 'عدد الأصناف',
    },
  };

  /// Fetched once per app run and reused for every receipt after that.
  pw.Font? _arabicFont;

  Future<pw.Font> _loadArabicFont() async {
    return _arabicFont ??= await PdfGoogleFonts.notoNaskhArabicRegular();
  }

  Future<File> generateReceipt({
    required SaleView sale,
    required List<SaleItemView> items,
    required String storeName,
    String? storePhone,
    required String header,
    required String footer,
    required String currency,
    required double exchangeRate,
    required bool taxEnabled,
    String languageCode = 'en',
  }) async {
    final lang = _labels.containsKey(languageCode) ? languageCode : 'en';
    final t = _labels[lang]!;
    final isRtl = lang == 'ar';

    final arabicFont = await _loadArabicFont();
    final theme = pw.ThemeData.withFont(fontFallback: [arabicFont]);

    final customerLabel =
        (sale.customerName == null || sale.customerName!.trim().isEmpty)
            ? t['noName']!
            : sale.customerName!.trim();

    // sale.total / priceSnapshot / lineTotal are always stored in USD.
    // Item rows are shown in the store's chosen main currency; the two
    // total lines below are always explicitly USD and LBP regardless of
    // which one is set as "main", per how the receipt should read.
    double toMain(double usdAmount) => currency == 'LBP' ? usdAmount * exchangeRate : usdAmount;
    String fmtMain(double usdAmount) =>
        '${toMain(usdAmount).toStringAsFixed(currency == 'LBP' ? 0 : 2)} $currency';
    String fmtUsd(double usdAmount) => '${usdAmount.toStringAsFixed(2)} USD';
    String fmtLbp(double usdAmount) => '${(usdAmount * exchangeRate).toStringAsFixed(0)} LBP';

    // sale.total already includes tax; the two currency lines the user asked
    // for are the pre-tax amount, with the tax-inclusive total shown
    // separately on its own line right after (only when TVA is enabled).
    final preTaxTotal = sale.total - sale.taxTotal;

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Store name + phone number right under it.
              pw.Center(
                child: pw.Text(
                  storeName,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              if (storePhone != null && storePhone.trim().isNotEmpty)
                pw.Center(child: pw.Text(storePhone.trim())),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(header)),
              pw.SizedBox(height: 8),
              pw.Text('${t['invoice']}: ${sale.invoiceNo}'),
              pw.Text('${sale.createdAt.toString().substring(0, 16)}'),
              pw.Text('${t['customer']}: $customerLabel'),
              pw.Divider(),
              // Header row: item | qty | price | total
              pw.Row(
                children: [
                  pw.Expanded(flex: 3, child: pw.Text(t['item']!, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(child: pw.Text(t['qty']!, style: pw.TextStyle(fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Expanded(child: pw.Text(t['price']!, style: pw.TextStyle(fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                  pw.Expanded(child: pw.Text(t['total']!, style: pw.TextStyle(fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                ],
              ),
              pw.SizedBox(height: 4),
              // Item rows.
              ...items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 3, child: pw.Text(item.nameSnapshot)),
                      pw.Expanded(child: pw.Text('${item.qty}', textAlign: pw.TextAlign.center)),
                      pw.Expanded(
                        child: pw.Text(toMain(item.priceSnapshot).toStringAsFixed(currency == 'LBP' ? 0 : 2), textAlign: pw.TextAlign.right),
                      ),
                      pw.Expanded(
                        child: pw.Text(toMain(item.lineTotal).toStringAsFixed(currency == 'LBP' ? 0 : 2), textAlign: pw.TextAlign.right),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              // Totals: pre-tax amount in both currencies, then the final
              // tax-inclusive total (only when TVA applies), then item count.
              _totalLine(t['totalUsd']!, fmtUsd(preTaxTotal)),
              _totalLine(t['totalLbp']!, fmtLbp(preTaxTotal)),
              if (taxEnabled)
                _totalLine(t['totalAfterTax']!, fmtMain(sale.total), bold: true),
              _totalLine(t['itemCount']!, items.fold<int>(0, (sum, item) => sum + item.qty).toString()),
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

  pw.Widget _totalLine(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('$label:', style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
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
