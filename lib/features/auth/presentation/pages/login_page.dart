import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/fields.dart';

/// دخول لمستخدم واحد فقط: كلمة سر واحدة بتفتح كل التطبيق بصلاحية كاملة
/// (ما في تفريق أدمن/كاشير بعد اليوم). كلمة السر تتغيّر من:
/// الإعدادات -> Credentials -> "Admin password".
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
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
                            controller: _passwordController,
                            label: l10n.tr('adminPassword'),
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: l10n.tr('login'),
                            onPressed: state.loading
                                ? null
                                : () => context.read<AppCubit>().loginAdmin(_passwordController.text.trim()),
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
