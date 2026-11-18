import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/widgets/fields.dart';

/// The only "settings" a cashier sees: who is logged in, language, logout.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ar = l10n.isArabic;

    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final settings = state.settings;
        return Scaffold(
          appBar: AppBar(title: Text(ar ? 'حسابي' : 'My account')),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(state.session?.userName ?? ''),
                  subtitle: Text(ar ? 'كاشير' : 'Cashier'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppDropdown<String>(
                value: settings.language,
                label: l10n.tr('language'),
                items: [
                  DropdownMenuItem(value: 'en', child: Text(l10n.tr('english'))),
                  DropdownMenuItem(value: 'ar', child: Text(l10n.tr('arabic'))),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  context.read<AppCubit>().updateSettings(settings.copyWith(language: value));
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () async {
                  final deps = AppScope.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final file = await deps.fileSyncService.exportToFile(includeAdminData: false);
                    await deps.fileSyncService.shareFile(file);
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                icon: const Icon(Icons.send),
                label: Text(ar ? 'إرسال المبيعات للأدمن' : 'Send sales to admin'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => context.read<AppCubit>().logout(),
                icon: const Icon(Icons.logout),
                label: Text(ar ? 'تسجيل خروج' : 'Log out'),
              ),
            ],
          ),
        );
      },
    );
  }
}
