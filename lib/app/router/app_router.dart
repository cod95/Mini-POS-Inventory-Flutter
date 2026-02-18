import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/invoices/presentation/pages/invoice_detail_page.dart';
import '../../features/pos/presentation/pages/pos_page.dart';
import '../../features/products/presentation/pages/products_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
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
                  builder: (context, state) => const SettingsPage(),
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
