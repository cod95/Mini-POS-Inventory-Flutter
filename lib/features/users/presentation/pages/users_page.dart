import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../domain/repositories/repositories.dart';

/// Admin only: add, edit, deactivate and delete login accounts.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  AuthRepository? _repository;
  List<AppUser> _users = const [];
  bool _loading = true;
  String? _error;

  bool get _ar => context.l10n.isArabic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository == null) {
      _repository = AppScope.of(context).authRepository;
      _load();
    }
  }

  Future<void> _load() async {
    final users = await _repository!.getUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  String _message(Object e) => e is AppException ? e.message : e.toString();

  Future<void> _edit([AppUser? user]) async {
    final ar = _ar;
    final nameController = TextEditingController(text: user?.name ?? '');
    final secretController = TextEditingController();
    var role = user?.role ?? UserRole.cashier;
    var active = user?.active ?? true;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(user == null ? (ar ? 'مستخدم جديد' : 'New user') : (ar ? 'تعديل مستخدم' : 'Edit user')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: ar ? 'الاسم' : 'Name'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: secretController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: role == UserRole.admin
                        ? (ar ? 'كلمة المرور' : 'Password')
                        : (ar ? 'الرمز السري (PIN)' : 'PIN'),
                    helperText: user == null
                        ? null
                        : (ar ? 'اتركه فارغاً للإبقاء على الحالي' : 'Leave empty to keep the current one'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SegmentedButton<UserRole>(
                  segments: [
                    ButtonSegment(value: UserRole.cashier, label: Text(ar ? 'أمين صندوق' : 'Cashier')),
                    ButtonSegment(value: UserRole.admin, label: Text(ar ? 'مدير' : 'Admin')),
                  ],
                  selected: {role},
                  onSelectionChanged: (value) => setLocal(() => role = value.first),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ar ? 'مفعّل' : 'Active'),
                  value: active,
                  onChanged: (value) => setLocal(() => active = value),
                ),
                if (dialogError != null)
                  Text(dialogError!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ar ? 'إلغاء' : 'Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await _repository!.saveUser(
                    id: user?.id,
                    name: nameController.text,
                    role: role,
                    secret: secretController.text,
                    active: active,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  setLocal(() => dialogError = _message(e));
                }
              },
              child: Text(ar ? 'حفظ' : 'Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    secretController.dispose();
    await _load();
  }

  Future<void> _delete(AppUser user) async {
    final ar = _ar;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'حذف المستخدم' : 'Delete user'),
        content: Text(ar ? 'حذف "${user.name}"؟ تبقى فواتيره السابقة محفوظة.' : 'Delete "${user.name}"? His old invoices stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ar ? 'حذف' : 'Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repository!.deleteUser(user.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final currentUserId = context.watch<AppCubit>().state.session?.userId;

    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'المستخدمون' : 'Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add),
        label: Text(ar ? 'إضافة مستخدم' : 'Add user'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 96),
              children: [
                Text(
                  ar
                      ? 'يرى المدير كل شيء. أما أمين الصندوق فيرى البيع والفواتير (إرسال وطباعة) فقط.'
                      : 'Admins see everything. Cashiers only sell and send/print invoices.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final user in _users)
                  Card(
                    child: ListTile(
                      leading: Icon(user.role == UserRole.admin ? Icons.admin_panel_settings : Icons.point_of_sale),
                      title: Text(user.name + (user.id == currentUserId ? (ar ? '  (أنت)' : '  (you)') : '')),
                      subtitle: Text(
                        '${user.role == UserRole.admin ? (ar ? 'مدير' : 'Admin') : (ar ? 'أمين صندوق' : 'Cashier')}'
                        '${user.active ? '' : (ar ? ' • موقوف' : ' • disabled')}',
                      ),
                      onTap: () => _edit(user),
                      trailing: user.id == currentUserId
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(user),
                            ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
    );
  }
}
