import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/cards.dart';
import '../../../../core/widgets/states.dart';
import '../cubit/reports_cubit.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return BlocProvider(
      create: (_) => ReportsCubit(
        reportsRepository: deps.reportsRepository,
        salesRepository: deps.salesRepository,
        exportService: deps.fileExportService,
      )..load(),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        if (state.loading && state.invoices.isEmpty) {
          return const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: LoadingSkeleton(count: 8),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.tr('reports')),
            actions: [
              IconButton(
                onPressed: state.loading ? null : () => context.read<ReportsCubit>().load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => context.read<ReportsCubit>().load(),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _RangeCard(state: state),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: 230,
                      child: SummaryCard(
                        title: 'Today sales',
                        value: AppFormatters.money(state.dashboard.todaySales),
                        subtitle: '${state.dashboard.todayInvoices} invoices',
                        icon: Icons.today,
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: SummaryCard(
                        title: 'Month sales',
                        value: AppFormatters.money(state.dashboard.monthSales),
                        subtitle: '${state.dashboard.monthInvoices} invoices',
                        icon: Icons.calendar_month,
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: SummaryCard(
                        title: 'Today profit',
                        value: AppFormatters.money(state.dashboard.todayProfit),
                        icon: Icons.trending_up,
                        color: Colors.green,
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: SummaryCard(
                        title: 'Month profit',
                        value: AppFormatters.money(state.dashboard.monthProfit),
                        icon: Icons.insights,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Exports', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: state.loading
                                    ? null
                                    : () => context.read<ReportsCubit>().exportSalesCsv(),
                                icon: const Icon(Icons.table_view_outlined),
                                label: Text(l10n.tr('exportSalesCsv')),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: state.loading
                                    ? null
                                    : () => context.read<ReportsCubit>().exportInventoryCsv(),
                                icon: const Icon(Icons.inventory_2_outlined),
                                label: Text(l10n.tr('exportInventoryCsv')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _BestSellersCard(state: state),
                const SizedBox(height: AppSpacing.md),
                _SalesByProductCard(state: state),
                const SizedBox(height: AppSpacing.md),
                _LowStockCard(state: state),
                const SizedBox(height: AppSpacing.md),
                _InvoiceHistoryCard(state: state),
                if (state.error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    state.error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RangeCard extends StatelessWidget {
  const _RangeCard({required this.state});

  final ReportsState state;

  @override
  Widget build(BuildContext context) {
    final from = state.from;
    final to = state.to;
    final label = from == null || to == null
        ? 'All time'
        : '${AppFormatters.shortDate(from)} → ${AppFormatters.shortDate(to)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(child: Text('Range: $label')),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(now.year - 2),
                  lastDate: DateTime(now.year + 1),
                  initialDateRange: from != null && to != null
                      ? DateTimeRange(start: from, end: to)
                      : DateTimeRange(
                          start: DateTime(now.year, now.month, 1),
                          end: now,
                        ),
                );
                if (!context.mounted) return;
                if (range != null) {
                  await context.read<ReportsCubit>().setRange(range.start, range.end);
                }
              },
              icon: const Icon(Icons.date_range_outlined),
              label: const Text('Pick'),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: () => context.read<ReportsCubit>().setRange(null, null),
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BestSellersCard extends StatelessWidget {
  const _BestSellersCard({required this.state});

  final ReportsState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Best sellers', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (state.dashboard.bestSellers.isEmpty)
              const EmptyState(message: 'No sales yet')
            else
              ...state.dashboard.bestSellers.map(
                (seller) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(seller.productName),
                  trailing: StatusChip(label: '${seller.qty} pcs', color: Colors.blue),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SalesByProductCard extends StatelessWidget {
  const _SalesByProductCard({required this.state});

  final ReportsState state;

  @override
  Widget build(BuildContext context) {
    final maxTotal = state.salesByProduct.isEmpty
        ? 1.0
        : state.salesByProduct.first.total <= 0
            ? 1.0
            : state.salesByProduct.first.total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sales by product', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (state.salesByProduct.isEmpty)
              const EmptyState(message: 'No product sales in selected range')
            else
              ...state.salesByProduct.take(8).map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(row.productName)),
                          Text('${row.qty} pcs • ${AppFormatters.money(row.total)}'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: (row.total / maxTotal).clamp(0, 1)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.state});

  final ReportsState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Low stock', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (state.lowStockProducts.isEmpty)
              const EmptyState(message: 'All products are healthy')
            else
              ...state.lowStockProducts.take(10).map(
                (product) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(product.name),
                  subtitle: Text(product.sku),
                  trailing: StatusChip(
                    label: '${product.stockQty}/${product.lowStockThreshold}',
                    color: Colors.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceHistoryCard extends StatelessWidget {
  const _InvoiceHistoryCard({required this.state});

  final ReportsState state;

  Color _statusColor(SaleStatus status) {
    switch (status) {
      case SaleStatus.completed:
        return Colors.green;
      case SaleStatus.returned:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.tr('invoiceHistory'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (state.invoices.isEmpty)
              const EmptyState(message: 'No invoices in selected range')
            else
              ...state.invoices.take(25).map(
                (invoice) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(invoice.invoiceNo),
                  subtitle: Text(AppFormatters.shortDate(invoice.createdAt)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppFormatters.money(invoice.total)),
                      const SizedBox(width: AppSpacing.sm),
                      StatusChip(label: invoice.status.value, color: _statusColor(invoice.status)),
                    ],
                  ),
                  onTap: () => context.push('/reports/invoice/${invoice.id}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
