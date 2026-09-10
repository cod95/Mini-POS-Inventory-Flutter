import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/utils/formatters.dart';

class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.currency,
    required this.canEditPrice,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onDiscountEdit,
    required this.onPriceEdit,
  });

  final CartItem item;
  final String currency;
  final bool canEditPrice;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final ValueChanged<double> onDiscountEdit;
  final ValueChanged<double> onPriceEdit;

  @override
  Widget build(BuildContext context) {
    final lineTotal = (item.price * item.qty) - item.discount;
    return Dismissible(
      key: ValueKey('cart_${item.productId}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: AppRadii.md,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text(
                    AppFormatters.money(lineTotal, currency: currency),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  _QtyButton(icon: Icons.remove, onTap: onDecrease),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Text('${item.qty}', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  _QtyButton(icon: Icons.add, onTap: onIncrease),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showAmountDialog(
                      context,
                      title: 'Item discount',
                      initial: item.discount,
                      onSubmit: onDiscountEdit,
                    ),
                    icon: const Icon(Icons.discount_outlined),
                    label: Text('Disc ${item.discount.toStringAsFixed(2)}'),
                  ),
                  if (canEditPrice)
                    TextButton.icon(
                      onPressed: () => _showAmountDialog(
                        context,
                        title: 'Edit item price',
                        initial: item.price,
                        onSubmit: onPriceEdit,
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(item.price.toStringAsFixed(2)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAmountDialog(
    BuildContext context, {
    required String title,
    required double initial,
    required ValueChanged<double> onSubmit,
  }) async {
    final controller = TextEditingController(text: initial.toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(double.tryParse(controller.text.trim()) ?? initial),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      onSubmit(result);
    }
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadii.sm,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: AppRadii.sm,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}
