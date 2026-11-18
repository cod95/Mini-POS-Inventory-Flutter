import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/app_models.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../core/errors/app_exception.dart';
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
          ? 'الحساب مقفل مؤقتاً بسبب محاولات خاطئة. أعد المحاولة بعد $minutes دقيقة.'
          : 'Account temporarily locked after wrong attempts. Try again in $minutes min.';
    }
    return invalid;
  }

  /// Forgotten password: only the developer's master password can set a new
  /// one for the selected account.
  Future<void> _forgot() async {
    final user = _selectedUser;
    if (user == null) return;
    final ar = context.l10n.isArabic;
    final deps = AppScope.of(context);
    final master = TextEditingController();
    final fresh = TextEditingController();
    String? error;
    var done = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(ar ? 'استعادة الوصول' : 'Recover access'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ar
                      ? 'يتطلب هذا الإجراء كلمة مرور المطوّر. سيتم تعيين كلمة مرور جديدة للحساب «${user.name}».'
                      : 'This needs the developer password. A new password will be set for "${user.name}".',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: master,
                  obscureText: true,
                  decoration: InputDecoration(labelText: ar ? 'كلمة مرور المطوّر' : 'Developer password'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: fresh,
                  obscureText: true,
                  decoration: InputDecoration(labelText: ar ? 'كلمة المرور الجديدة' : 'New password'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ar ? 'إلغاء' : 'Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  final ok = await deps.licenseService.verifyMaster(master.text);
                  if (!ok) {
                    setLocal(() => error = ar ? 'كلمة مرور المطوّر غير صحيحة.' : 'Wrong developer password.');
                    return;
                  }
                  await deps.authRepository.changeSecret(userId: user.id, newSecret: fresh.text);
                  done = true;
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } on LoginLockedException catch (e) {
                  final minutes = (e.seconds / 60).ceil();
                  setLocal(() => error = ar
                      ? 'محاولات خاطئة كثيرة. أعد المحاولة بعد $minutes دقيقة.'
                      : 'Too many attempts. Try again in $minutes min.');
                } on AppException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
              child: Text(ar ? 'تعيين' : 'Set'),
            ),
          ],
        ),
      ),
    );
    master.dispose();
    fresh.dispose();
    if (done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ar ? 'تم تعيين كلمة المرور الجديدة.' : 'The new password is set.')),
      );
    }
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
                                      '${u.name}  (${u.role == UserRole.admin ? (l10n.isArabic ? 'مدير' : 'Admin') : (l10n.isArabic ? 'أمين صندوق' : 'Cashier')})',
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
                                ? (l10n.isArabic ? 'الرمز السري (PIN)' : 'PIN')
                                : (l10n.isArabic ? 'كلمة المرور' : 'Password'),
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: l10n.tr('login'),
                            onPressed: state.loading || _selectedUserId == null ? null : _submit,
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: _selectedUserId == null ? null : _forgot,
                              child: Text(l10n.isArabic ? 'نسيت كلمة المرور؟' : 'Forgot password?'),
                            ),
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
