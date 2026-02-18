import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/fields.dart';
import '../../../../core/widgets/states.dart';
import '../../../../domain/entities/app_entities.dart';
import '../cubit/products_cubit.dart';
import '../../../pos/presentation/widgets/product_tile.dart' show ProductImageWidget;

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return BlocProvider(
      create: (_) => ProductsCubit(deps.productRepository)..load(),
      child: const _ProductsView(),
    );
  }
}

class _ProductsView extends StatelessWidget {
  const _ProductsView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final appState = context.watch<AppCubit>().state;
    final isAdmin = appState.session?.role == UserRole.admin;

    return BlocBuilder<ProductsCubit, ProductsState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.tr('products'))),
          floatingActionButton: isAdmin
              ? FloatingActionButton.extended(
                  onPressed: () => _showProductEditor(context),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.tr('addProduct')),
                )
              : null,
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                AppTextField(
                  hint: l10n.tr('searchProducts'),
                  onChanged: (value) => context.read<ProductsCubit>().applyFilter(search: value),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: state.filter.categoryId == null,
                        onSelected: (_) => context.read<ProductsCubit>().applyFilter(categoryId: -1),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ...state.categories.map(
                        (c) => Padding(
                          padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                          child: FilterChip(
                            label: Text(c.name),
                            selected: state.filter.categoryId == c.id,
                            onSelected: (_) => context.read<ProductsCubit>().applyFilter(categoryId: c.id),
                          ),
                        ),
                      ),
                      FilterChip(
                        label: Text(l10n.tr('lowStock')),
                        selected: state.filter.lowStockOnly,
                        onSelected: (_) => context
                            .read<ProductsCubit>()
                            .applyFilter(lowStockOnly: !state.filter.lowStockOnly),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (state.loading && state.products.isEmpty)
                  const Expanded(child: LoadingSkeleton())
                else if (state.filteredProducts.isEmpty)
                  Expanded(child: EmptyState(message: l10n.tr('empty')))
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: state.filteredProducts.length,
                      separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, index) {
                        final product = state.filteredProducts[index];
                        final tile = _ProductListTile(
                          product: product,
                          currency: appState.settings.currency,
                          isAdmin: isAdmin,
                          onEdit: () => _showProductEditor(context, existing: product),
                          onStockAction: () => _showStockActionSheet(context, product),
                        );
                        if (!isAdmin) {
                          return tile;
                        }

                        return Dismissible(
                          key: ValueKey('product_${product.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.errorContainer,
                              borderRadius: AppRadii.md,
                            ),
                            child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                          ),
                          confirmDismiss: (_) async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(l10n.tr('delete')),
                                content: Text('Delete ${product.name}?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: Text(l10n.tr('cancel')),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: Text(l10n.tr('delete')),
                                  ),
                                ],
                              ),
                            );
                            return confirmed == true;
                          },
                          onDismissed: (_) => context.read<ProductsCubit>().deleteProduct(product.id),
                          child: tile,
                        );
                      },
                    ),
                  ),
                if (state.error != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        state.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showProductEditor(BuildContext context, {ProductView? existing}) async {
    final cubit = context.read<ProductsCubit>();
    final state = cubit.state;

    final name = TextEditingController(text: existing?.name ?? '');
    final sku = TextEditingController(text: existing?.sku ?? '');
    final barcode = TextEditingController(text: existing?.barcode ?? '');
    final cost = TextEditingController(text: (existing?.cost ?? 0).toStringAsFixed(2));
    final price = TextEditingController(text: (existing?.price ?? 0).toStringAsFixed(2));
    final stock = TextEditingController(text: '${existing?.stockQty ?? 0}');
    final low = TextEditingController(text: '${existing?.lowStockThreshold ?? 5}');
    final unit = TextEditingController(text: existing?.unit ?? 'piece');
    final notes = TextEditingController(text: existing?.notes ?? '');
    final imageUrlController = TextEditingController(
      text: (existing?.imagePath?.startsWith('http') ?? false) ? existing!.imagePath! : '',
    );
    int? categoryId = existing?.categoryId;
    String? pickedImagePath = existing?.imagePath;

    final picker = ImagePicker();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              Future<void> pickImage(ImageSource source) async {
                final picked = await picker.pickImage(
                  source: source,
                  maxWidth: 600,
                  maxHeight: 600,
                  imageQuality: 85,
                );
                if (picked != null) {
                  setState(() => pickedImagePath = picked.path);
                }
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      existing == null ? 'Add product' : 'Edit product',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Image section ─────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Preview + pick button
                        Column(
                          children: [
                            GestureDetector(
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                builder: (ctx) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.photo_library_outlined),
                                        title: const Text('Choose from gallery'),
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          pickImage(ImageSource.gallery);
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.camera_alt_outlined),
                                        title: const Text('Take a photo'),
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          pickImage(ImageSource.camera);
                                        },
                                      ),
                                      if (pickedImagePath != null)
                                        ListTile(
                                          leading: const Icon(Icons.delete_outline),
                                          title: const Text('Remove image'),
                                          onTap: () {
                                            Navigator.of(ctx).pop();
                                            setState(() {
                                              pickedImagePath = null;
                                              imageUrlController.clear();
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              child: pickedImagePath != null
                                  ? ClipRRect(
                                      borderRadius: AppRadii.lg,
                                      child: ProductImageWidget(
                                        imagePath: pickedImagePath,
                                        size: 100,
                                      ),
                                    )
                                  : _ImagePickerPlaceholder(
                                      colorScheme: Theme.of(context).colorScheme,
                                    ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Tap to pick',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // URL text field
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppTextField(
                                controller: imageUrlController,
                                label: 'Image URL (https://...)',
                                onChanged: (url) {
                                  final trimmed = url.trim();
                                  if (trimmed.startsWith('http')) {
                                    setState(() => pickedImagePath = trimmed);
                                  }
                                },
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Paste an internet image URL, or tap the thumbnail to pick from camera/gallery.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    AppTextField(controller: name, label: 'Name'),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(controller: sku, label: 'SKU'),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(controller: barcode, label: 'Barcode'),
                    const SizedBox(height: AppSpacing.sm),
                    AppDropdown<int?>(
                      label: 'Category',
                      value: categoryId,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('No category')),
                        ...state.categories
                            .map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (value) => setState(() => categoryId = value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: AppTextField(controller: cost, label: 'Cost', keyboardType: TextInputType.number)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: AppTextField(controller: price, label: 'Price', keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: AppTextField(controller: stock, label: 'Stock', keyboardType: TextInputType.number)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: AppTextField(
                            controller: low,
                            label: 'Low stock threshold',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: AppTextField(controller: unit, label: 'Unit (piece/kg)')),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: AppTextField(controller: notes, label: 'Notes')),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: context.l10n.tr('save'),
                      onPressed: () async {
                        final input = ProductUpsertInput(
                          id: existing?.id,
                          name: name.text.trim(),
                          sku: sku.text.trim(),
                          barcode: barcode.text.trim().isEmpty ? null : barcode.text.trim(),
                          categoryId: categoryId,
                          cost: double.tryParse(cost.text.trim()) ?? 0,
                          price: double.tryParse(price.text.trim()) ?? 0,
                          stockQty: int.tryParse(stock.text.trim()) ?? 0,
                          lowStockThreshold: int.tryParse(low.text.trim()) ?? 5,
                          unit: unit.text.trim().isEmpty ? 'piece' : unit.text.trim(),
                          notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                          imagePath: pickedImagePath,
                        );
                        await cubit.saveProduct(input);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showStockActionSheet(BuildContext context, ProductView product) async {
    final qty = TextEditingController(text: '1');
    final reason = TextEditingController();
    var type = StockMovementType.add;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stock action • ${product.name}'),
                  const SizedBox(height: AppSpacing.md),
                  AppDropdown<StockMovementType>(
                    label: 'Action',
                    value: type,
                    items: StockMovementType.values
                        .where((e) => e != StockMovementType.sale && e != StockMovementType.returnSale)
                        .map((e) => DropdownMenuItem(value: e, child: Text(e.value)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => type = value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(controller: qty, label: 'Quantity', keyboardType: TextInputType.number),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(controller: reason, label: 'Reason'),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: context.l10n.tr('save'),
                    onPressed: () async {
                      final rawQty = int.tryParse(qty.text.trim()) ?? 0;
                      final parsedQty = switch (type) {
                        StockMovementType.remove => -rawQty.abs(),
                        StockMovementType.adjust => rawQty,
                        _ => rawQty.abs(),
                      };

                      await context.read<ProductsCubit>().applyStockMovement(
                            StockMovementInput(
                              productId: product.id,
                              type: type,
                              qtyChange: parsedQty,
                              reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
                            ),
                          );
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ImagePickerPlaceholder extends StatelessWidget {
  const _ImagePickerPlaceholder({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: AppRadii.lg,
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, color: colorScheme.primary, size: 32),
          const SizedBox(height: 4),
          Text(
            'Add Image',
            style: TextStyle(color: colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ProductListTile extends StatelessWidget {
  const _ProductListTile({
    required this.product,
    required this.currency,
    required this.isAdmin,
    required this.onEdit,
    required this.onStockAction,
  });

  final ProductView product;
  final String currency;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onStockAction;

  @override
  Widget build(BuildContext context) {
    final low = product.isLowStock;
    return Card(
      child: ListTile(
        title: Text(product.name),
        subtitle: Text('${product.sku} • ${product.categoryName ?? '-'}'),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(AppFormatters.money(product.price, currency: currency)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
              decoration: BoxDecoration(
                color: low
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: AppRadii.sm,
              ),
              child: Text('Stock ${product.stockQty}'),
            ),
          ],
        ),
        onTap: isAdmin ? onEdit : null,
        onLongPress: onStockAction,
      ),
    );
  }
}
