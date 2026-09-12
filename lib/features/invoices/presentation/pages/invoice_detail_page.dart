import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/states.dart';
import '../cubit/invoice_detail_cubit.dart';

class InvoiceDetailPage extends StatelessWidget {
  const InvoiceDetailPage({super.key, required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return BlocProvider(
      create: (_) => InvoiceDetailCubit(deps.salesRepository)..load(saleId),
      child: const _InvoiceDetailView(),
    );
  }
}

class _InvoiceDetailView extends StatelessWidget {
  const _InvoiceDetailView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<AppCubit>().state.settings;

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
        final customerLabel = (sale.customerName == null || sale.customerName!.trim().isEmpty)
            ? l10n.tr('noName')
            : sale.customerName!.trim();
        final preTaxTotal = sale.total - sale.taxTotal;
        final itemCount = detail.items.fold<int>(0, (sum, item) => sum + item.qty);

        return Scaffold(
          appBar: AppBar(title: Text(settings.storeName)),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Invoice number + date + customer name.
              Text('${l10n.tr('invoiceNumber')}: ${sale.invoiceNo}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(AppFormatters.shortDate(sale.createdAt),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              Text('${l10n.tr('customerName')}: $customerLabel'),
              const SizedBox(height: AppSpacing.md),
              // Items table: item | qty | price | total
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
                          final canReturnThis = sale.status == SaleStatus.completed;
                          final returnQty = state.returnQtyByItemId[item.id] ?? 0;
                          final maxQty = item.qty.abs();

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
                                      child: Text(item.priceSnapshot.toStringAsFixed(2),
                                          textAlign: TextAlign.end),
                                    ),
                                    Expanded(
                                      child: Text(item.lineTotal.toStringAsFixed(2),
                                          textAlign: TextAlign.end),
                                    ),
                                  ],
                                ),
                                if (canReturnThis) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Row(
                                    children: [
                                      Text('${l10n.tr('returnQty')} ($maxQty):'),
                                      const SizedBox(width: AppSpacing.sm),
                                      IconButton.filledTonal(
                                        onPressed: returnQty <= 0
                                            ? null
                                            : () => context
                                                .read<InvoiceDetailCubit>()
                                                .setReturnQty(item.id, returnQty - 1),
                                        icon: const Icon(Icons.remove),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Text('$returnQty', style: Theme.of(context).textTheme.titleMedium),
                                      const SizedBox(width: AppSpacing.xs),
                                      IconButton.filled(
                                        onPressed: returnQty >= maxQty
                                            ? null
                                            : () => context
                                                .read<InvoiceDetailCubit>()
                                                .setReturnQty(item.id, returnQty + 1),
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
                      // Totals: USD, LBP, after-TVA (if applicable), item count.
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
                          exchangeRate: settings.exchangeRate,
                        ),
                      ),
                      if (settings.taxEnabled)
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
              FilledButton.icon(
                onPressed: state.canReturn && !state.returning
                    ? () => context.read<InvoiceDetailCubit>().submitReturn()
                    : null,
                icon: const Icon(Icons.undo),
                label: Text(state.returning ? l10n.tr('processingReturn') : l10n.tr('returnSelectedItems')),
              ),
              if (state.lastReturnInvoice != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${l10n.tr('returnCreated')}: ${state.lastReturnInvoice}',
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
