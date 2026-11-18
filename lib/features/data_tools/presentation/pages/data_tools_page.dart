import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_dependencies.dart';
import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/services/excel_service.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../license/presentation/pages/license_widgets.dart';

/// Excel import/export: fillable products template, inventory export,
/// import from a filled template and a sales export.
class DataToolsPage extends StatefulWidget {
  const DataToolsPage({super.key});

  @override
  State<DataToolsPage> createState() => _DataToolsPageState();
}

class _DataToolsPageState extends State<DataToolsPage> {
  final ExcelService _excel = ExcelService();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _ar => context.l10n.isArabic;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = e.toString();
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _info(String text) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = false;
    });
  }

  AppSettingsModel get _settings => context.read<AppCubit>().state.settings;

  // ------------------------------------------------------------ template

  Future<void> _downloadTemplate() => _run(() async {
        final file = await _excel.buildProductsTemplate(currency: _settings.currency);
        await _excel.share(file);
        _info(_ar
            ? 'تم تجهيز النموذج. احفظه أو أرسله إلى نفسك، ثم املأه وأعد استيراده.'
            : 'Template ready. Save it, fill it and import it back.');
      });

  // -------------------------------------------------------------- export

  Future<void> _exportInventory(AppDependencies deps) => _run(() async {
        final settings = _settings;
        final products = await deps.productRepository.getProducts();
        final file = await _excel.buildProductsExport(
          products: products,
          currency: settings.currency,
          toStoreCurrency: (usd) => settings.currency == 'LBP' ? usd * settings.exchangeRate : usd,
        );
        await _excel.share(file);
        _info(_ar ? 'تم تصدير ${products.length} منتج.' : 'Exported ${products.length} products.');
      });

  Future<void> _exportSales(AppDependencies deps) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: _ar ? 'اختر الفترة (أو ارجع لتصدير الكل)' : 'Pick a period (or go back to export all)',
    );
    if (!mounted) return;

    await _run(() async {
      final invoices = await deps.salesRepository.getInvoices(
        filter: InvoiceFilter(from: range?.start, to: range?.end),
      );
      final details = <SaleDetailView>[];
      for (final invoice in invoices) {
        final detail = await deps.salesRepository.getInvoiceDetail(invoice.id);
        if (detail != null) details.add(detail);
      }
      final file = await _excel.buildSalesExport(details);
      await _excel.share(file);
      _info(_ar ? 'تم تصدير ${details.length} فاتورة.' : 'Exported ${details.length} invoices.');
    });
  }

  // -------------------------------------------------------------- import

  Future<void> _import(AppDependencies deps) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    await _run(() async {
      final settings = _settings;
      final read = await _excel.readProducts(File(path));
      final errors = [...read.errors];

      final existing = await deps.productRepository.getProducts();
      final categories = await deps.productRepository.getCategories();

      final bySku = <String, ProductView>{};
      final byBarcode = <String, ProductView>{};
      final byName = <String, ProductView>{};
      void index(ProductView p) {
        if (p.sku.trim().isNotEmpty) bySku[p.sku.trim().toLowerCase()] = p;
        if ((p.barcode ?? '').trim().isNotEmpty) byBarcode[p.barcode!.trim().toLowerCase()] = p;
        byName[p.name.trim().toLowerCase()] = p;
      }

      existing.forEach(index);
      final categoryIds = {for (final c in categories) c.name.trim().toLowerCase(): c.id};

      var created = 0;
      var updated = 0;
      var counter = 0;
      final stamp = DateTime.now().millisecondsSinceEpoch;

      for (final row in read.rows) {
        try {
          final match = (row.sku.isNotEmpty ? bySku[row.sku.toLowerCase()] : null) ??
              (row.barcode.isNotEmpty ? byBarcode[row.barcode.toLowerCase()] : null) ??
              byName[row.name.toLowerCase()];

          int? categoryId = match?.categoryId;
          if (row.category.isNotEmpty) {
            final key = row.category.toLowerCase();
            categoryId = categoryIds[key] ?? await deps.productRepository.addCategory(row.category);
            categoryIds[key] = categoryId;
          }

          double toUsd(double v) =>
              AppFormatters.toUsd(v, currency: settings.currency, exchangeRate: settings.exchangeRate);

          counter++;
          final id = await deps.productRepository.upsertProduct(
            ProductUpsertInput(
              id: match?.id,
              name: row.name,
              sku: row.sku.isNotEmpty ? row.sku : (match?.sku ?? 'SKU-$stamp-$counter'),
              barcode: row.barcode.isNotEmpty ? row.barcode : match?.barcode,
              categoryId: categoryId,
              cost: row.cost != null ? toUsd(row.cost!) : (match?.cost ?? 0),
              price: row.price != null ? toUsd(row.price!) : (match?.price ?? 0),
              stockQty: match?.stockQty ?? 0,
              lowStockThreshold: row.lowStock ?? match?.lowStockThreshold ?? 5,
              unit: row.unit.isNotEmpty ? row.unit : (match?.unit ?? 'piece'),
              notes: match?.notes,
              imagePath: match?.imagePath,
              taxable: row.taxable ?? match?.taxable ?? false,
            ),
          );

          final targetStock = row.stock;
          if (targetStock != null && targetStock >= 0 && targetStock != (match?.stockQty ?? 0)) {
            await deps.productRepository.addStockMovement(
              StockMovementInput(
                productId: id,
                type: StockMovementType.adjust,
                qtyChange: targetStock,
                reason: 'Excel import',
              ),
            );
          }

          if (match == null) {
            created++;
          } else {
            updated++;
          }
          final fresh = await deps.productRepository.getProduct(id);
          if (fresh != null) index(fresh);
        } catch (e) {
          errors.add('Row ${row.rowNumber} (${row.name}): $e');
        }
      }

      if (!mounted) return;
      await _showImportResult(created: created, updated: updated, errors: errors);
      _info(_ar
          ? 'اكتمل الاستيراد: $created جديد، $updated معدّل، ${errors.length} مشكلة.'
          : 'Import done: $created new, $updated updated, ${errors.length} problems.');
    });
  }

  Future<void> _showImportResult({
    required int created,
    required int updated,
    required List<String> errors,
  }) {
    final ar = _ar;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'نتيجة الاستيراد' : 'Import result'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ar ? 'منتجات جديدة: $created' : 'New products: $created'),
                Text(ar ? 'منتجات معدّلة: $updated' : 'Updated products: $updated'),
                Text(ar ? 'مشاكل: ${errors.length}' : 'Problems: ${errors.length}'),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ...errors.take(20).map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(e, style: Theme.of(ctx).textTheme.bodySmall),
                        ),
                      ),
                  if (errors.length > 20)
                    Text(ar ? '… و${errors.length - 20} أخرى' : '… and ${errors.length - 20} more'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ar ? 'حسناً' : 'OK'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final deps = AppScope.of(context);

    if (!deps.licenseService.full) {
      return Scaffold(
        appBar: AppBar(title: Text(ar ? 'Excel (استيراد وتصدير)' : 'Excel import / export')),
        body: TrialLockedBody(ar: ar),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'Excel (استيراد وتصدير)' : 'Excel import / export')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ar ? 'المنتجات والمخزون' : 'Products & stock',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar
                        ? 'نزّل النموذج واملأ المنتجات في Excel ثم استورده. يُعدَّل المنتج الموجود (بالرمز أو الباركود أو الاسم نفسه) ويُضاف الجديد. التكلفة والسعر بعملة المحل (${_settings.currency}).'
                        : 'Download the template, fill in your products in Excel, then import it. An existing product (same SKU, barcode or name) is updated, a new one is added. Cost and price are in the store currency (${_settings.currency}).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: _busy ? null : _downloadTemplate,
                    icon: const Icon(Icons.download),
                    label: Text(ar ? 'تحميل نموذج Excel فارغ' : 'Download blank Excel template'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _exportInventory(deps),
                    icon: const Icon(Icons.upload_file),
                    label: Text(ar ? 'تصدير المخزون الحالي' : 'Export current inventory'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _import(deps),
                    icon: const Icon(Icons.file_open),
                    label: Text(ar ? 'استيراد من ملف Excel' : 'Import from Excel file'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ar ? 'المبيعات' : 'Sales',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar
                        ? 'ملف Excel يحتوي الفواتير في صفحة وتفاصيل الأصناف في صفحة ثانية مع المرتجعات.'
                        : 'An Excel file with the invoices (one sheet) and every item line (another sheet), returns included.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _exportSales(deps),
                    icon: const Icon(Icons.table_chart),
                    label: Text(ar ? 'تصدير الفواتير' : 'Export invoices'),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _message!,
              style: TextStyle(
                color: _messageIsError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
