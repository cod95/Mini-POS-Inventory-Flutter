import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/fields.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _pinController = TextEditingController(text: '1234');
  final _adminController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    _adminController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<AppCubit, AppState>(
      listenWhen: (previous, current) => previous.isAuthenticated != current.isAuthenticated,
      listener: (context, state) {
        if (state.isAuthenticated) {
          context.go('/pos');
        }
      },
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: BlocBuilder<AppCubit, AppState>(
                    builder: (context, state) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.tr('appTitle'), style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: AppSpacing.sm),
                          Text(l10n.tr('login'), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppSpacing.xl),
                          AppTextField(
                            controller: _pinController,
                            label: l10n.tr('pin'),
                            keyboardType: TextInputType.number,
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: l10n.tr('continueAsCashier'),
                            onPressed: state.loading
                                ? null
                                : () => context.read<AppCubit>().loginCashier(_pinController.text.trim()),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppTextField(
                            controller: _adminController,
                            label: l10n.tr('adminPassword'),
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                            onPressed: state.loading
                                ? null
                                : () => context.read<AppCubit>().loginAdmin(_adminController.text.trim()),
                            icon: const Icon(Icons.admin_panel_settings_outlined),
                            label: Text(l10n.tr('continueAsAdmin')),
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              l10n.tr('invalidCredentials'),
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
