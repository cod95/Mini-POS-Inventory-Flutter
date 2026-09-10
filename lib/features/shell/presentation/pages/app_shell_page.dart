import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_localizations.dart';

class AppShellPage extends StatelessWidget {
  const AppShellPage({
    super.key,
    required this.currentPath,
    required this.child,
  });

  final String currentPath;
  final Widget child;

  static const _tabs = ['/pos', '/products', '/reports', '/settings'];

  int get _currentIndex {
    for (var i = 0; i < _tabs.length; i++) {
      if (currentPath.startsWith(_tabs[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.point_of_sale), label: l10n.tr('pos')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), label: l10n.tr('products')),
          NavigationDestination(icon: const Icon(Icons.assessment_outlined), label: l10n.tr('reports')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: l10n.tr('settings')),
        ],
        onDestinationSelected: (index) {
          if (index == _currentIndex) return;
          context.go(_tabs[index]);
        },
      ),
    );
  }
}
