import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/cards.dart';
import '../../../../core/widgets/states.dart';
import '../../../../domain/repositories/repositories.dart';
import '../invoice_status.dart';

enum _InvoiceTypeFilter { all, sales, returns, cancelled }

/// Every invoice, newest first. Open one to see its details, send/print it
/// again, return items from it or cancel it.
class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  static const int _maxRows = 300;

  final TextEditingController _searchController = TextEditingController();
  SalesRepository? _repository;
  List<SaleSummary> _invoices = const [];
  _InvoiceTypeFilter _filter = _InvoiceTypeFilter.all;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      _repository = AppScope.of(context).salesRepository;
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await repository.getInvoices(
        filter: InvoiceFilter(search: _searchController.text),
      );
      if (!mounted) return;
      setState(() {
        _invoices = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<SaleSummary> get _visible {
    final rows = _invoices.where((invoice) {
      switch (_filter) {
        case _InvoiceTypeFilter.all:
          return true;
        case _InvoiceTypeFilter.sales:
          return !invoice.isReturnDocument && invoice.status != SaleStatus.cancelled;
        case _InvoiceTypeFilter.returns:
          return invoice.isReturnDocument ||
              invoice.status == SaleStatus.returned ||
              invoice.status == SaleStatus.partiallyReturned;
        case _InvoiceTypeFilter.cancelled:
          return invoice.status == SaleStatus.cancelled;
      }
    }).toList();
    return rows.take(_maxRows).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ar = l10n.isArabic;
    final settings = context.watch<AppCubit>().state.settings;
    final rows = _visible;

    String filterLabel(_InvoiceTypeFilter f) {
      switch (f) {
        case _InvoiceTypeFilter.all:
          return ar ? 'الكل' : 'All';
        case _InvoiceTypeFilter.sales:
          return ar ? 'مبيعات' : 'Sales';
        case _InvoiceTypeFilter.returns:
          return ar ? 'مرتجعات' : 'Returns';
        case _InvoiceTypeFilter.cancelled:
          return ar ? 'ملغاة' : 'Cancelled';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'الفواتير' : 'Invoices'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: ar ? 'ابحث برقم الفاتورة أو اسم الزبون' : 'Search invoice no. or customer',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _load();
                  },
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Row(
              children: [
                for (final f in _InvoiceTypeFilter.values) ...[
                  ChoiceChip(
                    label: Text(filterLabel(f)),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: LoadingSkeleton(count: 6),
                  )
                : _error != null
                    ? EmptyState(message: _error!)
                    : rows.isEmpty
                        ? EmptyState(message: ar ? 'ما في فواتير' : 'No invoices')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final invoice = rows[index];
                                final name = (invoice.customerName ?? '').trim();
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(invoice.invoiceNo),
                                  subtitle: Text(
                                    name.isEmpty
                                        ? AppFormatters.shortDate(invoice.createdAt)
                                        : '${AppFormatters.shortDate(invoice.createdAt)} • $name',
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        AppFormatters.money(
                                          invoice.total,
                                          currency: settings.currency,
                                          exchangeRate: settings.exchangeRate,
                                        ),
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      StatusChip(
                                        label: invoiceStatusLabel(
                                          invoice.status,
                                          arabic: ar,
                                          isReturnDocument: invoice.isReturnDocument,
                                        ),
                                        color: invoiceStatusColor(
                                          invoice.status,
                                          isReturnDocument: invoice.isReturnDocument,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    await context.push('/invoices/invoice/${invoice.id}');
                                    if (mounted) _load();
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
