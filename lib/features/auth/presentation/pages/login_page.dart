import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/app_models.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/fields.dart';

/// Login: pick a user, then enter his password (admin) or PIN (cashier).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _passwordController = TextEditingController();
  List<AppUser> _users = const [];
  int? _selectedUserId;
  bool _loadedUsers = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedUsers) {
      _loadedUsers = true;
      _loadUsers();
    }
  }

  Future<void> _loadUsers() async {
    final users = await AppScope.of(context).authRepository.getUsers(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _users = users;
      _selectedUserId ??= users.isEmpty ? null : users.first.id;
    });
  }

  AppUser? get _selectedUser {
    for (final user in _users) {
      if (user.id == _selectedUserId) return user;
    }
    return null;
  }

  String _errorText(String error, bool ar, String invalid) {
    if (error.startsWith('locked:')) {
      final seconds = int.tryParse(error.substring(7)) ?? 60;
      final minutes = (seconds / 60).ceil();
      return ar
          ? 'الحساب مقفول مؤقتاً بسبب محاولات غلط. جرّب بعد $minutes دقيقة.'
          : 'Account temporarily locked after wrong attempts. Try again in $minutes min.';
    }
    return invalid;
  }

  void _submit() {
    final id = _selectedUserId;
    if (id == null) return;
    context.read<AppCubit>().login(id, _passwordController.text);
  }

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
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
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
                          DropdownButtonFormField<int>(
                            value: _selectedUserId,
                            decoration: InputDecoration(
                              labelText: l10n.isArabic ? 'المستخدم' : 'User',
                            ),
                            items: _users
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u.id,
                                    child: Text(
                                      '${u.name}  (${u.role == UserRole.admin ? (l10n.isArabic ? 'أدمن' : 'Admin') : (l10n.isArabic ? 'كاشير' : 'Cashier')})',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() {
                              _selectedUserId = value;
                              _passwordController.clear();
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            controller: _passwordController,
                            label: _selectedUser?.role == UserRole.cashier
                                ? (l10n.isArabic ? 'الرمز (PIN)' : 'PIN')
                                : (l10n.isArabic ? 'كلمة السر' : 'Password'),
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: l10n.tr('login'),
                            onPressed: state.loading || _selectedUserId == null ? null : _submit,
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              _errorText(state.error!, l10n.isArabic, l10n.tr('invalidCredentials')),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xl),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Designed & Developed by Mohammad Al-Qaseer | Version 1.0 - 2026',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                            letterSpacing: 0.3,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
