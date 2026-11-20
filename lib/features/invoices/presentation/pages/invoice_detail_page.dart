import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/cards.dart';
import '../../../../core/widgets/states.dart';
import '../cubit/invoice_detail_cubit.dart';
import '../invoice_status.dart';

class InvoiceDetailPage extends StatelessWidget {
  const InvoiceDetailPage({super.key, required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return BlocProvider(
      create: (_) => InvoiceDetailCubit(
        deps.salesRepository,
        deps.settingsRepository,
        deps.receiptPdfService,
        deps.bluetoothPrinterService,
      )..load(saleId),
      child: const _InvoiceDetailView(),
    );
  }
}

class _InvoiceDetailView extends StatelessWidget {
  const _InvoiceDetailView();

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ar = context.l10n.isArabic;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ar ? 'رجوع' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ar = l10n.isArabic;
    final appState = context.watch<AppCubit>().state;
    final settings = appState.settings;
    final isAdmin = appState.session?.role == UserRole.admin;

    return BlocBuilder<InvoiceDetailCubit, InvoiceDetailState>(
      builder: (context, state) {
        if (state.loading && state.detail == null) {
          return const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: LoadingSkeleton(count: 6),
            ),
          );
        }

        final detail = state.detail;
        if (detail == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.tr('invoiceDetails'))),
            body: EmptyState(message: state.error ?? l10n.tr('invoiceNotFound')),
          );
        }

        final sale = detail.sale;
        final isReturnDoc = sale.isReturnDocument;
        final customerLabel = (sale.customerName == null || sale.customerName!.trim().isEmpty)
            ? l10n.tr('noName')
            : sale.customerName!.trim();
        final preTaxTotal = sale.total - sale.taxTotal;
        final itemCount = detail.items.fold<int>(0, (sum, item) => sum + item.qty);
        final cubit = context.read<InvoiceDetailCubit>();
        final busy = state.working || state.returning;

        return Scaffold(
          appBar: AppBar(title: Text(sale.invoiceNo)),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      settings.storeName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  StatusChip(
                    label: invoiceStatusLabel(sale.status, arabic: ar, isReturnDocument: isReturnDoc),
                    color: invoiceStatusColor(sale.status, isReturnDocument: isReturnDoc),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(AppFormatters.shortDate(sale.createdAt),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              Text('${l10n.tr('customerName')}: $customerLabel'),
              if ((sale.cashierName ?? '').isNotEmpty)
                Text('${ar ? 'أمين الصندوق' : 'Cashier'}: ${sale.cashierName}'),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(l10n.tr('item'), style: Theme.of(context).textTheme.labelLarge),
                          ),
                          Expanded(
                            child: Text(l10n.tr('qty'),
                                style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.center),
                          ),
                          Expanded(
                            child: Text(l10n.tr('price'),
                                style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.end),
                          ),
                          Expanded(
                            child: Text(l10n.tr('total'),
                                style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.end),
                          ),
                        ],
                      ),
                      const Divider(),
                      ...detail.items.map(
                        (item) {
                          final returned = detail.returnedQtyByItemId[item.id] ?? 0;
                          final maxQty = detail.returnableQty(item).clamp(0, item.qty);
                          final returnQty = state.returnQtyByItemId[item.id] ?? 0;
                          final showReturnControls = isAdmin && state.isReturnable && maxQty > 0;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          Flexible(child: Text(item.nameSnapshot)),
                                          if (item.taxable) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: Theme.of(context).colorScheme.outline),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'TVA',
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Text('${item.qty}', textAlign: TextAlign.center),
                                    ),
                                    Expanded(
                                      child: Text(item.isFree ? 'Free' : item.priceSnapshot.toStringAsFixed(2),
                                          textAlign: TextAlign.end),
                                    ),
                                    Expanded(
                                      child: Text(item.isFree ? 'Free' : item.lineTotal.toStringAsFixed(2),
                                          textAlign: TextAlign.end),
                                    ),
                                  ],
                                ),
                                if (!isReturnDoc && returned > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      ar ? 'تم إرجاع $returned من ${item.qty}' : 'Returned $returned of ${item.qty}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.orange.shade800),
                                    ),
                                  ),
                                if (showReturnControls) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Row(
                                    children: [
                                      Text('${l10n.tr('returnQty')} ($maxQty):'),
                                      const SizedBox(width: AppSpacing.sm),
                                      IconButton.filledTonal(
                                        onPressed: returnQty <= 0
                                            ? null
                                            : () => cubit.setReturnQty(item.id, returnQty - 1),
                                        icon: const Icon(Icons.remove),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Text('$returnQty', style: Theme.of(context).textTheme.titleMedium),
                                      const SizedBox(width: AppSpacing.xs),
                                      IconButton.filled(
                                        onPressed: returnQty >= maxQty
                                            ? null
                                            : () => cubit.setReturnQty(item.id, returnQty + 1),
                                        icon: const Icon(Icons.add),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const Divider(),
                      _totalLine(
                        context,
                        l10n.tr('totalUsd'),
                        AppFormatters.money(preTaxTotal, currency: 'USD'),
                      ),
                      _totalLine(
                        context,
                        l10n.tr('totalLbp'),
                        AppFormatters.money(
                          preTaxTotal,
                          currency: 'LBP',
                          exchangeRate: sale.exchangeRateAtSale,
                        ),
                      ),
                      if (sale.taxTotal != 0)
                        _totalLine(
                          context,
                          l10n.tr('totalAfterTax'),
                          AppFormatters.money(sale.total, currency: 'USD'),
                          bold: true,
                        ),
                      _totalLine(context, l10n.tr('itemCount'), '$itemCount'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Send / print: available to every role.
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => cubit.sendReceipt(share: true),
                      icon: const Icon(Icons.share),
                      label: Text(ar ? 'إرسال' : 'Send'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => cubit.sendReceipt(share: false),
                      icon: const Icon(Icons.print),
                      label: Text(ar ? 'طباعة' : 'Print'),
                    ),
                  ),
                ],
              ),
              if (state.working) ...[
                const SizedBox(height: AppSpacing.sm),
                const LinearProgressIndicator(),
              ],

              // Return + cancel: admin only.
              if (isAdmin && state.isReturnable) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: state.canReturn && !busy
                      ? () async {
                          final ok = await _confirm(
                            context,
                            title: ar ? 'تأكيد المرتجع' : 'Confirm return',
                            message: ar
                                ? 'ستُعاد الأصناف المحددة إلى المخزون وتُخصم من المبيعات والأرباح.'
                                : 'The selected items go back to stock and are deducted from sales and profit.',
                            confirmLabel: ar ? 'تأكيد' : 'Confirm',
                          );
                          if (ok) await cubit.submitReturn();
                        }
                      : null,
                  icon: const Icon(Icons.undo),
                  label: Text(state.returning ? l10n.tr('processingReturn') : l10n.tr('returnSelectedItems')),
                ),
              ],
              if (isAdmin && state.isCancellable) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: busy
                      ? null
                      : () async {
                          final ok = await _confirm(
                            context,
                            title: ar ? 'إلغاء الفاتورة' : 'Cancel invoice',
                            message: ar
                                ? 'ستُلغى الفاتورة كاملةً وتُعاد جميع الأصناف إلى المخزون ولن تُحتسب في التقارير.'
                                : 'The whole invoice is voided, all items go back to stock and it no longer counts in reports.',
                            confirmLabel: ar ? 'إلغاء الفاتورة' : 'Cancel invoice',
                          );
                          if (ok) await cubit.cancelInvoice();
                        },
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(ar ? 'إلغاء الفاتورة' : 'Cancel invoice'),
                ),
              ],
              if (!isAdmin && !isReturnDoc && state.isReturnable) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  ar ? 'المرتجع والإلغاء من صلاحية المدير فقط.' : 'Returns and cancellation need an admin.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (state.lastReturnInvoice != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${l10n.tr('returnCreated')}: ${state.lastReturnInvoice}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ],
              if (state.info == 'cancelled') ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  ar ? 'تم إلغاء الفاتورة وإعادة المخزون.' : 'Invoice cancelled and stock restored.',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _totalLine(BuildContext context, String label, String value, {bool bold = false}) {
    final textStyle = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text('$label:', style: textStyle)),
          Text(value, style: textStyle),
        ],
      ),
    );
  }
}
