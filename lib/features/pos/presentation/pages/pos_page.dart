import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/cards.dart';
import '../../../../core/widgets/fields.dart';
import '../../../../core/widgets/states.dart';
import '../cubit/pos_cubit.dart';
import '../widgets/cart_item_tile.dart';
import '../widgets/product_tile.dart';

class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return BlocProvider(
      create: (context) => PosCubit(
        productRepository: deps.productRepository,
        salesRepository: deps.salesRepository,
        settingsRepository: deps.settingsRepository,
        partyRepository: deps.partyRepository,
        scannerService: deps.barcodeScannerService,
        receiptPdfService: deps.receiptPdfService,
      )..load(),
      child: const _PosView(),
    );
  }
}

class _PosView extends StatelessWidget {
  const _PosView();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppCubit>().state;

    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        if (state.loading && state.products.isEmpty) {
          return const Scaffold(body: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: LoadingSkeleton()));
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('نقطة البيع'),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () => context.read<PosCubit>().scanAndAdd(),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                AppTextField(
                  hint: 'البحث عن منتج...',
                  onChanged: (value) => context.read<PosCubit>().updateFilter(search: value),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () {},
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      FilterChip(
                        label: const Text('الكل'),
                        selected: state.filter.categoryId == null,
                        onSelected: (_) => context.read<PosCubit>().updateFilter(categoryId: -1),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ...state.categories.map(
                        (category) => Padding(
                          padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                          child: FilterChip(
                            label: Text(category.name),
                            selected: state.filter.categoryId == category.id,
                            onSelected: (_) => context.read<PosCubit>().updateFilter(categoryId: category.id),
                          ),
                        ),
                      ),
                      FilterChip(
                        label: const Text('مخزون منخفض'),
                        selected: state.filter.lowStockOnly,
                        onSelected: (_) => context
                            .read<PosCubit>()
                            .updateFilter(lowStockOnly: !state.filter.lowStockOnly),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 1000;
                      if (wide) {
                        return Row(
                          children: [
                            Expanded(
                              child: _ProductsPane(
                                state: state,
                                currency: appState.settings.currency,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            SizedBox(
                              width: min(430, constraints.maxWidth * .38),
                              child: _CartPane(
                                state: state,
                                currency: appState.settings.currency,
                                isAdmin: appState.session?.role == UserRole.admin,
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Expanded(
                            child: _ProductsPane(
                              state: state,
                              currency: appState.settings.currency,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            height: state.cart.isEmpty
                                ? (constraints.maxHeight * 0.2).clamp(120.0, 170.0)
                                : (constraints.maxHeight * 0.3).clamp(180.0, 250.0),
                            child: _CartPane(
                              state: state,
                              currency: appState.settings.currency,
                              isAdmin: appState.session?.role == UserRole.admin,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _CheckoutBar(
            state: state,
            currency: appState.settings.currency,
          ),
        );
      },
    );
  }
}

class _ProductsPane extends StatelessWidget {
  const _ProductsPane({required this.state, required this.currency});

  final PosState state;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (state.filteredProducts.isEmpty) {
      return const EmptyState(message: 'لا توجد منتجات');
    }

    return ListView.separated(
      itemCount: state.filteredProducts.length,
      separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final product = state.filteredProducts[index];
        return ProductTile(
          product: product,
          currency: currency,
          onTap: () => context.read<PosCubit>().addProductToCart(product),
        );
      },
    );
  }
}

class _CartPane extends StatelessWidget {
  const _CartPane({
    required this.state,
    required this.currency,
    required this.isAdmin,
  });

  final PosState state;
  final String currency;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    if (state.cart.isEmpty) {
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'السلة فارغة',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: state.cart.length,
            separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, index) {
              final item = state.cart[index];
              return CartItemTile(
                item: item,
                currency: currency,
                canEditPrice: isAdmin,
                onIncrease: () => context.read<PosCubit>().updateItemQty(item.productId, item.qty + 1),
                onDecrease: () => context.read<PosCubit>().updateItemQty(item.productId, item.qty - 1),
                onRemove: () => context.read<PosCubit>().removeFromCart(item.productId),
                onDiscountEdit: (value) => context.read<PosCubit>().setItemDiscount(item.productId, value),
                onPriceEdit: (value) => context.read<PosCubit>().setItemPrice(item.productId, value),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CheckoutBar extends StatefulWidget {
  const _CheckoutBar({required this.state, required this.currency});

  final PosState state;
  final String currency;

  @override
  State<_CheckoutBar> createState() => _CheckoutBarState();
}

class _CheckoutBarState extends State<_CheckoutBar> {
  Future<void> _openCheckoutSheet(BuildContext context, PosState state) async {
    final cubit = context.read<PosCubit>();
    final discountController = TextEditingController(text: state.orderDiscount.toStringAsFixed(2));
    final paidController = TextEditingController(
      text: (state.paid > 0 ? state.paid : state.total).toStringAsFixed(2),
    );
    var method = state.paymentMethod;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تفاصيل الدفع',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AmountField(
                      controller: discountController,
                      label: 'خصم الفاتورة',
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppDropdown<PaymentMethod>(
                      label: 'طريقة الدفع',
                      value: method,
                      items: PaymentMethod.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.value == 'cash' ? 'نقداً (كاش)' : value.value.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => method = value);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AmountField(
                      controller: paidController,
                      label: 'المبلغ المدفوع',
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: SummaryCard(
                            title: 'المجموع الكلي',
                            value: AppFormatters.money(state.total, currency: widget.currency),
                            icon: Icons.payments_outlined,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: SummaryCard(
                            title: 'الباقي (الفكة)',
                            value: AppFormatters.money(
                              ((double.tryParse(paidController.text) ?? 0) - state.total)
                                  .clamp(0, double.infinity),
                              currency: widget.currency,
                            ),
                            icon: Icons.currency_exchange,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(
                      label: 'إتمام العملية',
                      icon: Icons.check_circle_outline,
                      minHeight: 52,
                      onPressed: () async {
                        cubit.setOrderDiscount(double.tryParse(discountController.text) ?? 0);
                        cubit.setPaymentMethod(method);
                        cubit.setPaid(double.tryParse(paidController.text) ?? 0);
                        await cubit.checkout();
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    discountController.dispose();
    paidController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 720;

            final checkoutButton = PrimaryButton(
              label: 'إتمام البيع',
              icon: Icons.check_circle_outline,
              minHeight: 52,
              onPressed: state.cart.isEmpty || state.loading
                  ? null
                  : () => _openCheckoutSheet(context, state),
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCompact) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SummaryCard(
                          title: 'المجموع',
                          value: AppFormatters.money(state.total, currency: widget.currency),
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: SummaryCard(
                          title: 'الباقي',
                          value: AppFormatters.money(state.change, currency: widget.currency),
                          icon: Icons.currency_exchange,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  checkoutButton,
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: SummaryCard(
                          title: 'المجموع',
                          value: AppFormatters.money(state.total, currency: widget.currency),
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: SummaryCard(
                          title: 'الباقي',
                          value: AppFormatters.money(state.change, currency: widget.currency),
                          icon: Icons.currency_exchange,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(flex: 2, child: checkoutButton),
                    ],
                  ),
                if (state.lastResult != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: AppRadii.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.infoMessage ?? 'تمت العملية بنجاح - رقم الفاتورة: ${state.lastResult!.invoiceNo}',
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            OutlinedButton.icon(
                              onPressed: state.receiptProcessing
                                  ? null
                                  : () => context.read<PosCubit>().printLastReceipt(),
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('طباعة الفاتورة'),
                            ),
                            OutlinedButton.icon(
                              onPressed: state.receiptProcessing
                                  ? null
                                  : () => context.read<PosCubit>().shareLastReceipt(),
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('مشاركة PDF'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => context.read<PosCubit>().newSale(),
                              icon: const Icon(Icons.add_shopping_cart),
                              label: const Text('عملية جديدة'),
                            ),
                          ],
                        ),
                        if (state.receiptProcessing) ...[
                          const SizedBox(height: AppSpacing.xs),
                          const LinearProgressIndicator(),
                        ],
                      ],
                    ),
                  ),
                ],
                if (state.error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      state.error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
