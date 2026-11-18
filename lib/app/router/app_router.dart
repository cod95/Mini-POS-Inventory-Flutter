import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/app_models.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/data_tools/presentation/pages/data_tools_page.dart';
import '../../features/invoices/presentation/pages/invoice_detail_page.dart';
import '../../features/invoices/presentation/pages/invoices_page.dart';
import '../../features/pos/presentation/pages/pos_page.dart';
import '../../features/products/presentation/pages/products_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/sync/presentation/pages/sync_page.dart';
import '../../features/users/presentation/pages/account_page.dart';
import '../../features/users/presentation/pages/users_page.dart';
import '../../features/shell/presentation/pages/app_shell_page.dart';
import '../app_dependencies.dart';

class AppRouter {
  AppRouter(this.dependencies)
      : router = GoRouter(
          navigatorKey: dependencies.rootNavigatorKey,
          initialLocation: '/login',
          refreshListenable: GoRouterRefreshStream(dependencies.appCubit.stream),
          redirect: (context, state) {
            final isAuthenticated = dependencies.appCubit.state.isAuthenticated;
            final isLoginRoute = state.uri.path == '/login';

            if (!isAuthenticated && !isLoginRoute) {
              return '/login';
            }
            if (isAuthenticated && isLoginRoute) {
              return '/pos';
            }

            // A cashier may only use the POS, the invoices and his account.
            final session = dependencies.appCubit.state.session;
            if (session != null && session.role != UserRole.admin) {
              final path = state.uri.path;
              const adminOnly = ['/products', '/reports', '/settings/'];
              if (adminOnly.any(path.startsWith)) {
                return '/pos';
              }
            }
            return null;
          },
          routes: [
            GoRoute(
              path: '/login',
              builder: (context, state) => const LoginPage(),
            ),
            ShellRoute(
              builder: (context, state, child) {
                return AppShellPage(currentPath: state.uri.path, child: child);
              },
              routes: [
                GoRoute(
                  path: '/pos',
                  builder: (context, state) => const PosPage(),
                ),
                GoRoute(
                  path: '/invoices',
                  builder: (context, state) => const InvoicesPage(),
                  routes: [
                    GoRoute(
                      path: 'invoice/:id',
                      builder: (context, state) {
                        final id = int.tryParse(state.pathParameters['id'] ?? '');
                        return InvoiceDetailPage(saleId: id ?? 0);
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: '/products',
                  builder: (context, state) => const ProductsPage(),
                ),
                GoRoute(
                  path: '/reports',
                  builder: (context, state) => const ReportsPage(),
                  routes: [
                    GoRoute(
                      path: 'invoice/:id',
                      builder: (context, state) {
                        final id = int.tryParse(state.pathParameters['id'] ?? '');
                        return InvoiceDetailPage(saleId: id ?? 0);
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: '/settings',
                  builder: (context, state) =>
                      dependencies.appCubit.state.session?.role == UserRole.admin
                          ? const SettingsPage()
                          : const AccountPage(),
                  routes: [
                    GoRoute(
                      path: 'sync',
                      builder: (context, state) => const SyncPage(),
                    ),
                    GoRoute(
                      path: 'users',
                      builder: (context, state) => const UsersPage(),
                    ),
                    GoRoute(
                      path: 'data',
                      builder: (context, state) => const DataToolsPage(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

  final AppDependencies dependencies;
  final GoRouter router;
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
