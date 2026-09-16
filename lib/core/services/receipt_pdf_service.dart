import 'dart:io';

import 'package:arabic_reshaper/arabic_reshaper.dart';
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

  // Column headers are always shown in English regardless of the app
  // language, per how the receipt should read — this keeps the table
  // compact and never lets a header wrap onto two lines.
  static const _colItem = 'Item';
  static const _colQty = 'Qty';
  static const _colPrice = 'Price';
  static const _colTotal = 'Total';

  static const Map<String, Map<String, String>> _labels = {
    'en': {
      'invoice': 'Invoice',
      'customer': 'Customer',
      'noName': 'No name',
      'totalUsd': 'Total (USD)',
      'totalLbp': 'Total (LBP)',
      'totalAfterTax': 'Total after TVA',
      'itemCount': 'Item count',
    },
    'ar': {
      'invoice': 'رقم الفاتورة',
      'customer': 'الزبون',
      'noName': 'بدون اسم',
      'totalUsd': 'المجموع بالدولار',
      'totalLbp': 'المجموع باللبناني',
      'totalAfterTax': 'المجموع بعد TVA',
      'itemCount': 'عدد الأصناف',
    },
  };

  static const double _baseFontSize = 8.5;
  static const double _headerFontSize = 8;
  static const double _titleFontSize = 13;

  // Matches any Arabic-script codepoint, basic block + presentation forms.
  static final RegExp _arabicPattern =
      RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

  static bool _hasArabic(String text) => _arabicPattern.hasMatch(text);

  /// Fetched once per app run and reused for every receipt after that.
  pw.Font? _arabicFont;

  Future<pw.Font> _loadArabicFont() async {
    return _arabicFont ??= await PdfGoogleFonts.notoNaskhArabicRegular();
  }

  /// `arabic_reshaper` joins Arabic letters into their correct connected
  /// presentation forms, but it does NOT reorder anything — it keeps the
  /// characters in logical (reading) order. The `pdf` package does not
  /// reliably auto-detect and reorder an embedded Arabic run inside a
  /// paragraph, so instead of relying on that, each piece of text picks
  /// its OWN direction here based on whether it actually contains Arabic —
  /// independent of the invoice's overall language. That's what lets store
  /// name, item names, and labels each be Arabic or Latin in any
  /// combination and still render correctly.
  pw.Widget _shapedText(
    String text,
    pw.TextStyle style, {
    pw.TextAlign? textAlign,
  }) {
    final isArabic = _hasArabic(text);
    final content = isArabic ? ArabicReshaper.instance.reshape(text) : text;
    return pw.Directionality(
      textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      child: pw.Text(content, style: style, textAlign: textAlign),
    );
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

    final arabicFont = await _loadArabicFont();
    final theme = pw.ThemeData.withFont(
      base: arabicFont,
      bold: arabicFont,
      fontFallback: [arabicFont],
    );

    final customerLabel =
        (sale.customerName == null || sale.customerName!.trim().isEmpty)
            ? t['noName']!
            : sale.customerName!.trim();

    // sale.total / priceSnapshot / lineTotal are always stored in USD.
    // Item rows are shown in the store's chosen main currency; the two
    // total lines below are always explicitly USD and LBP regardless of
    // which one is set as "main".
    final currencyDecimals = currency == 'LBP' ? 0 : 2;
    double toMain(double usdAmount) => currency == 'LBP' ? usdAmount * exchangeRate : usdAmount;
    String fmtMain(double usdAmount) => '${toMain(usdAmount).toStringAsFixed(currencyDecimals)} $currency';
    String fmtUsd(double usdAmount) => '${usdAmount.toStringAsFixed(2)} USD';
    String fmtLbp(double usdAmount) => '${(usdAmount * exchangeRate).toStringAsFixed(0)} LBP';

    // sale.total already includes tax (computed only from items individually
    // marked taxable); the two currency lines are the pre-tax amount, with
    // the tax-inclusive total shown separately right after (TVA-enabled sales
    // only).
    final preTaxTotal = sale.total - sale.taxTotal;
    final itemCount = items.fold<int>(0, (sum, item) => sum + item.qty);

    pw.TextStyle style({double? size, bool bold = false}) => pw.TextStyle(
          font: arabicFont,
          fontFallback: [arabicFont],
          fontSize: size ?? _baseFontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80.copyWith(
          marginLeft: 8,
          marginRight: 8,
          marginTop: 8,
          marginBottom: 8,
        ),
        // Always LTR at the page level. Direction is decided per piece of
        // text instead (see _shapedText) — see the comment on that method.
        textDirection: pw.TextDirection.ltr,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Store name + phone number right under it.
              pw.Center(
                child: _shapedText(storeName, style(size: _titleFontSize, bold: true)),
              ),
              if (storePhone != null && storePhone.trim().isNotEmpty)
                pw.Center(child: _shapedText(storePhone.trim(), style())),
              pw.SizedBox(height: 3),
              pw.Center(child: _shapedText(header, style())),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  _shapedText('${t['invoice']!}: ', style()),
                  // The invoice number itself is always plain Latin/digits
                  // (INV-YYYYMMDD-XXXX), kept as its own text so it never
                  // gets caught up in the label's direction.
                  _shapedText(sale.invoiceNo, style()),
                ],
              ),
              pw.Text(sale.createdAt.toString().substring(0, 16), style: style()),
              pw.Row(
                children: [
                  _shapedText('${t['customer']!}: ', style()),
                  _shapedText(customerLabel, style()),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.6),
              // Header row: item | qty | price | total — always English,
              // fixed short labels so nothing ever wraps.
              pw.Row(
                children: [
                  pw.Expanded(flex: 5, child: pw.Text(_colItem, style: style(size: _headerFontSize, bold: true))),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(_colQty, style: style(size: _headerFontSize, bold: true), textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(_colPrice, style: style(size: _headerFontSize, bold: true), textAlign: pw.TextAlign.right),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(_colTotal, style: style(size: _headerFontSize, bold: true), textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.3),
              // Item rows. A small "TVA" tag marks items with tax applied.
              ...items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Wrap(
                          crossAxisAlignment: pw.WrapCrossAlignment.center,
                          children: [
                            _shapedText(item.nameSnapshot, style()),
                            if (item.taxable) ...[
                              pw.SizedBox(width: 3),
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(width: 0.4),
                                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                                ),
                                child: pw.Text('TVA', style: style(size: 6)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('${item.qty}', style: style(), textAlign: pw.TextAlign.center),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          toMain(item.priceSnapshot).toStringAsFixed(currencyDecimals),
                          style: style(),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          toMain(item.lineTotal).toStringAsFixed(currencyDecimals),
                          style: style(),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 0.6),
              // Totals: pre-tax amount in both currencies, then the final
              // tax-inclusive total (only when TVA applies), then item count.
              _totalLine(t['totalUsd']!, fmtUsd(preTaxTotal), style),
              _totalLine(t['totalLbp']!, fmtLbp(preTaxTotal), style),
              if (sale.taxTotal > 0)
                _totalLine(t['totalAfterTax']!, fmtMain(sale.total), style, bold: true),
              _totalLine(t['itemCount']!, '$itemCount', style),
              pw.SizedBox(height: 8),
              pw.Center(child: _shapedText(footer, style())),
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

  pw.Widget _totalLine(
    String label,
    String value,
    pw.TextStyle Function({double? size, bool bold}) style, {
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _shapedText('$label:', style(bold: bold)),
          pw.Text(value, style: style(bold: bold)),
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
