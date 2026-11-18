import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';

/// Changing the password / PIN of the logged-in user. When [forced] the user
/// still has a default secret and cannot use the app before replacing it.
class ChangeSecretPage extends StatefulWidget {
  const ChangeSecretPage({super.key, required this.forced});

  final bool forced;

  @override
  State<ChangeSecretPage> createState() => _ChangeSecretPageState();
}

class _ChangeSecretPageState extends State<ChangeSecretPage> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ar = context.l10n.isArabic;
    if (_new.text != _confirm.text) {
      setState(() => _error = ar ? 'الكلمتين مش متطابقتين' : 'The two entries do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final cubit = context.read<AppCubit>();
    final error = await cubit.changeOwnSecret(
      _new.text,
      currentSecret: widget.forced ? null : _current.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    setState(() => _busy = false);
    if (widget.forced) {
      context.go('/pos');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ar ? 'تم تغيير كلمة السر' : 'Password changed')),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final role = context.read<AppCubit>().state.session?.role;
    final isAdmin = role == UserRole.admin;
    final what = isAdmin ? (ar ? 'كلمة السر' : 'password') : (ar ? 'الرمز (PIN)' : 'PIN');

    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.forced,
          title: Text(ar ? 'تغيير $what' : 'Change $what'),
          actions: [
            if (widget.forced)
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => context.read<AppCubit>().logout(),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                if (widget.forced) ...[
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        ar
                            ? 'هالحساب لسا عم يستعمل $what الافتراضي. لأمان المحل لازم تختار واحد جديد قبل ما تكمّل.'
                            : 'This account still uses the default $what. For your shop\'s safety choose a new one before continuing.',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else ...[
                  TextField(
                    controller: _current,
                    obscureText: true,
                    decoration: InputDecoration(labelText: ar ? '$what الحالي' : 'Current $what'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextField(
                  controller: _new,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: ar ? '$what الجديد' : 'New $what',
                    helperText: isAdmin
                        ? (ar ? '6 خانات على الأقل' : 'At least 6 characters')
                        : (ar ? '4 خانات على الأقل' : 'At least 4 characters'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: InputDecoration(labelText: ar ? 'أعد كتابته' : 'Repeat it'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(ar ? 'حفظ' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
