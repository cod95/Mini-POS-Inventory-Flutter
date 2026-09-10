import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/cards.dart';
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
            appBar: AppBar(title: const Text('Invoice details')),
            body: EmptyState(message: state.error ?? 'Invoice not found'),
          );
        }

        final sale = detail.sale;

        return Scaffold(
          appBar: AppBar(title: Text(sale.invoiceNo)),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              SummaryCard(
                title: 'Invoice summary',
                value: AppFormatters.money(sale.total),
                subtitle:
                    '${AppFormatters.shortDate(sale.createdAt)} • ${sale.paymentMethod.value.toUpperCase()}',
                icon: Icons.receipt_long,
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Items', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      ...detail.items.map(
                        (item) {
                          final canReturnThis = sale.status == SaleStatus.completed;
                          final returnQty = state.returnQtyByItemId[item.id] ?? 0;
                          final maxQty = item.qty.abs();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outlineVariant,
                                ),
                                borderRadius: AppRadii.md,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.nameSnapshot,
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                      ),
                                      StatusChip(
                                        label:
                                            'x${item.qty} • ${AppFormatters.money(item.lineTotal)}',
                                        color: Colors.blue,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Price ${AppFormatters.money(item.priceSnapshot)}  |  Cost ${AppFormatters.money(item.costSnapshot)}  |  Discount ${AppFormatters.money(item.discount)}',
                                  ),
                                  if (canReturnThis) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    Row(
                                      children: [
                                        Text('Return qty (max $maxQty):'),
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
                                        Text(
                                          '$returnQty',
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
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
                            ),
                          );
                        },
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
                      Text('Totals', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      _line('Subtotal', sale.subtotal),
                      _line('Discount', sale.discountTotal),
                      _line('Tax', sale.taxTotal),
                      _line('Total', sale.total, bold: true),
                      _line('Paid', sale.paid),
                      _line('Change', sale.changeAmount),
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
                label: Text(state.returning ? 'Processing return...' : 'Return selected items'),
              ),
              if (state.lastReturnInvoice != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Return created: ${state.lastReturnInvoice}',
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

  Widget _line(String label, double value, {bool bold = false}) {
    final textStyle = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textStyle)),
          Text(AppFormatters.money(value), style: textStyle),
        ],
      ),
    );
  }
}
