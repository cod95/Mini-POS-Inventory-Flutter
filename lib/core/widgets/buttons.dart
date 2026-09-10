import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
    this.minHeight,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final style = minHeight == null
        ? null
        : FilledButton.styleFrom(minimumSize: Size.fromHeight(minHeight!));

    final labelWidget = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );

    final child = icon == null
        ? FilledButton(
            style: style,
            onPressed: onPressed,
            child: labelWidget,
          )
        : FilledButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon),
            label: labelWidget,
          );

    if (expanded) {
      return SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}

class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Theme.of(context).colorScheme.onError,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
        ),
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.delete_outline),
        label: Text(label),
      ),
    );
  }
}
