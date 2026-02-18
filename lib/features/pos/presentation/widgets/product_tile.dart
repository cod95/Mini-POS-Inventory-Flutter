import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/app_entities.dart';

class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.currency,
    required this.onTap,
  });

  final ProductView product;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lowStock = product.isLowStock;
    return InkWell(
      borderRadius: AppRadii.md,
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              ProductImageWidget(imagePath: product.imagePath),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '${product.sku} • ${product.categoryName ?? '-'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(AppFormatters.money(product.price, currency: currency)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                decoration: BoxDecoration(
                  color: lowStock
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: AppRadii.sm,
                ),
                child: Text(
                  '${product.stockQty}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable image widget that supports both network URLs and local file paths.
class ProductImageWidget extends StatelessWidget {
  const ProductImageWidget({
    super.key,
    this.imagePath,
    this.size = 56,
  });

  final String? imagePath;
  final double size;

  bool get _isNetworkUrl =>
      imagePath != null &&
      (imagePath!.startsWith('http://') || imagePath!.startsWith('https://'));

  bool get _isLocalFile =>
      imagePath != null &&
      !_isNetworkUrl &&
      imagePath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isNetworkUrl) {
      return ClipRRect(
        borderRadius: AppRadii.md,
        child: Image.network(
          imagePath!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _PlaceholderBox(
              size: size,
              colorScheme: colorScheme,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, _) =>
              _PlaceholderBox(size: size, colorScheme: colorScheme),
        ),
      );
    }

    if (_isLocalFile) {
      return ClipRRect(
        borderRadius: AppRadii.md,
        child: Image.file(
          File(imagePath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, _) =>
              _PlaceholderBox(size: size, colorScheme: colorScheme),
        ),
      );
    }

    return _PlaceholderBox(size: size, colorScheme: colorScheme);
  }
}

class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox({
    required this.colorScheme,
    required this.size,
    this.child,
  });

  final ColorScheme colorScheme;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: AppRadii.md,
      ),
      child: child ??
          Icon(
            Icons.inventory_2_outlined,
            color: colorScheme.onPrimaryContainer,
            size: size * 0.5,
          ),
    );
  }
}
