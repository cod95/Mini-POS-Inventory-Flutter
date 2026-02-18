import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/fields.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _storeNameController;
  late final TextEditingController _currencyController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _receiptHeaderController;
  late final TextEditingController _receiptFooterController;
  late final TextEditingController _cashierPinController;
  late final TextEditingController _adminPasswordController;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _storeNameController = TextEditingController();
    _currencyController = TextEditingController();
    _taxRateController = TextEditingController();
    _receiptHeaderController = TextEditingController();
    _receiptFooterController = TextEditingController();
    _cashierPinController = TextEditingController();
    _adminPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _currencyController.dispose();
    _taxRateController.dispose();
    _receiptHeaderController.dispose();
    _receiptFooterController.dispose();
    _cashierPinController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  void _syncControllers(AppSettingsModel settings) {
    if (_initialized) return;
    _storeNameController.text = settings.storeName;
    _currencyController.text = settings.currency;
    _taxRateController.text = settings.taxRate.toStringAsFixed(2);
    _receiptHeaderController.text = settings.receiptHeader;
    _receiptFooterController.text = settings.receiptFooter;
    _cashierPinController.text = settings.cashierPin;
    _adminPasswordController.text = settings.adminPassword;
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final settings = state.settings;
        _syncControllers(settings);

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.tr('settings')),
            actions: [
              IconButton(
                onPressed: state.loading
                    ? null
                    : () async {
                        await context.read<AppCubit>().logout();
                      },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.tr('storeSettings'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(controller: _storeNameController, label: l10n.tr('storeName')),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(controller: _currencyController, label: l10n.tr('currency')),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        controller: _taxRateController,
                        label: 'Tax rate (0.14 = 14%)',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.tr('taxEnabled')),
                        value: settings.taxEnabled,
                        onChanged: state.loading
                            ? null
                            : (value) {
                                final updated = settings.copyWith(taxEnabled: value);
                                context.read<AppCubit>().updateSettings(updated);
                              },
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.tr('allowNegativeStock')),
                        value: settings.allowNegativeStock,
                        onChanged: state.loading
                            ? null
                            : (value) {
                                final updated = settings.copyWith(allowNegativeStock: value);
                                context.read<AppCubit>().updateSettings(updated);
                              },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Receipt', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: _receiptHeaderController,
                        label: l10n.tr('receiptHeader'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        controller: _receiptFooterController,
                        label: l10n.tr('receiptFooter'),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Credentials', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: _cashierPinController,
                        label: l10n.tr('pin'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        controller: _adminPasswordController,
                        label: l10n.tr('adminPassword'),
                        obscureText: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.tr('language'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      AppDropdown<String>(
                        value: settings.language,
                        label: l10n.tr('language'),
                        items: [
                          DropdownMenuItem(value: 'en', child: Text(l10n.tr('english'))),
                          DropdownMenuItem(value: 'ar', child: Text(l10n.tr('arabic'))),
                        ],
                        onChanged: state.loading
                            ? null
                            : (value) {
                                if (value == null) return;
                                final updated = settings.copyWith(language: value);
                                context.read<AppCubit>().updateSettings(updated);
                              },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: l10n.tr('save'),
                onPressed: state.loading
                    ? null
                    : () async {
                        final updated = settings.copyWith(
                          storeName: _storeNameController.text.trim().isEmpty
                              ? settings.storeName
                              : _storeNameController.text.trim(),
                          currency: _currencyController.text.trim().isEmpty
                              ? settings.currency
                              : _currencyController.text.trim().toUpperCase(),
                          taxRate: double.tryParse(_taxRateController.text.trim()) ?? settings.taxRate,
                          receiptHeader: _receiptHeaderController.text.trim().isEmpty
                              ? settings.receiptHeader
                              : _receiptHeaderController.text.trim(),
                          receiptFooter: _receiptFooterController.text.trim().isEmpty
                              ? settings.receiptFooter
                              : _receiptFooterController.text.trim(),
                          cashierPin: _cashierPinController.text.trim().isEmpty
                              ? settings.cashierPin
                              : _cashierPinController.text.trim(),
                          adminPassword: _adminPasswordController.text.trim().isEmpty
                              ? settings.adminPassword
                              : _adminPasswordController.text.trim(),
                        );
                        await context.read<AppCubit>().updateSettings(updated);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.tr('save'))),
                        );
                      },
              ),
              if (state.error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
