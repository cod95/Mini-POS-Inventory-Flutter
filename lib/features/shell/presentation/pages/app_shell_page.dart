import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';

class AppShellPage extends StatelessWidget {
  const AppShellPage({
    super.key,
    required this.currentPath,
    required this.child,
  });

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAdmin = context.watch<AppCubit>().state.session?.role == UserRole.admin;

    // Admin sees every tab; a cashier only sells and works with invoices.
    final tabs = <_Tab>[
      _Tab('/pos', Icons.point_of_sale, l10n.tr('pos')),
      _Tab('/invoices', Icons.receipt_long_outlined, l10n.isArabic ? 'الفواتير' : 'Invoices'),
      if (isAdmin) _Tab('/products', Icons.inventory_2_outlined, l10n.tr('products')),
      if (isAdmin) _Tab('/reports', Icons.assessment_outlined, l10n.tr('reports')),
      _Tab(
        '/settings',
        isAdmin ? Icons.settings_outlined : Icons.person_outline,
        isAdmin ? l10n.tr('settings') : (l10n.isArabic ? 'حسابي' : 'Account'),
      ),
    ];

    var currentIndex = 0;
    for (var i = 0; i < tabs.length; i++) {
      if (currentPath.startsWith(tabs[i].path)) {
        currentIndex = i;
        break;
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ListenableBuilder(
              listenable: AppScope.of(context).licenseService,
              builder: (context, _) {
                if (AppScope.of(context).licenseService.full) return const SizedBox.shrink();
                final scheme = Theme.of(context).colorScheme;
                return Container(
                  width: double.infinity,
                  color: scheme.secondaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                  child: Text(
                    l10n.isArabic
                        ? 'نسخة تجريبية محدودة — للتفعيل تواصل مع المطوّر'
                        : 'Limited trial version — contact the developer to activate',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12),
                  ),
                );
              },
            ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        destinations: [
          for (final tab in tabs) NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
        onDestinationSelected: (index) {
          if (index == currentIndex) return;
          context.go(tabs[index].path);
        },
      ),
    );
  }
}

class _Tab {
  const _Tab(this.path, this.icon, this.label);

  final String path;
  final IconData icon;
  final String label;
}
