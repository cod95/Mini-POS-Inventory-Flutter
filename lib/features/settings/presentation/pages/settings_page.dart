import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/services/bluetooth_printer_service.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/fields.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<String> _supportedCurrencies = ['USD', 'LBP'];

  late final TextEditingController _storeNameController;
  late final TextEditingController _storePhoneController;
  late final TextEditingController _exchangeRateController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _receiptHeaderController;
  late final TextEditingController _receiptFooterController;
  late final TextEditingController _cashierPinController;
  late final TextEditingController _adminPasswordController;

  String _currency = 'USD';
  String _secondaryCurrency = 'LBP';

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _storeNameController = TextEditingController();
    _storePhoneController = TextEditingController();
    _exchangeRateController = TextEditingController();
    _taxRateController = TextEditingController();
    _receiptHeaderController = TextEditingController();
    _receiptFooterController = TextEditingController();
    _cashierPinController = TextEditingController();
    _adminPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _storePhoneController.dispose();
    _exchangeRateController.dispose();
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
    _storePhoneController.text = settings.storePhone ?? '';
    _currency = _supportedCurrencies.contains(settings.currency) ? settings.currency : 'USD';
    _secondaryCurrency =
        _supportedCurrencies.contains(settings.secondaryCurrencyCode) ? settings.secondaryCurrencyCode : 'LBP';
    _exchangeRateController.text = settings.exchangeRate.toStringAsFixed(0);
    // taxRate يتخزن داخليًا كنسبة عشرية (0.11)، بس بيتعرض للمستخدم كنسبة مئوية (11)
    _taxRateController.text = (settings.taxRate * 100).toStringAsFixed(2);
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
                      AppTextField(
                        controller: _storePhoneController,
                        label: l10n.tr('storePhone'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: AppDropdown<String>(
                              value: _currency,
                              label: l10n.tr('currency'),
                              items: _supportedCurrencies
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                  .toList(),
                              onChanged: state.loading
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() => _currency = value);
                                    },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: AppDropdown<String>(
                              value: _secondaryCurrency,
                              label: 'العملة الثانية',
                              items: _supportedCurrencies
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                  .toList(),
                              onChanged: state.loading
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() => _secondaryCurrency = value);
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        controller: _exchangeRateController,
                        label: '1 $_currency = ? $_secondaryCurrency',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppTextField(
                        controller: _taxRateController,
                        label: 'نسبة الضريبة (%)',
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
                      Text(context.l10n.tr('receipt'), style: Theme.of(context).textTheme.titleMedium),
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
                      Text(context.l10n.tr('credentials'), style: Theme.of(context).textTheme.titleMedium),
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.tr('bluetoothPrinter'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        settings.printerName == null
                            ? l10n.tr('noPrinterSelected')
                            : '${l10n.tr('connectedPrinter')}: ${settings.printerName}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(l10n.tr('paperWidth'), style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          ChoiceChip(
                            label: const Text('58 mm'),
                            selected: settings.printerPaperWidthMm == '58',
                            onSelected: (_) => context
                                .read<AppCubit>()
                                .updateSettings(settings.copyWith(printerPaperWidthMm: '58')),
                          ),
                          ChoiceChip(
                            label: const Text('80 mm'),
                            selected: settings.printerPaperWidthMm == '80',
                            onSelected: (_) => context
                                .read<AppCubit>()
                                .updateSettings(settings.copyWith(printerPaperWidthMm: '80')),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () => _pickBluetoothPrinter(context, settings),
                        icon: const Icon(Icons.bluetooth_searching),
                        label: Text(l10n.tr('selectPrinter')),
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
                        final parsedTaxPercent = double.tryParse(_taxRateController.text.trim().replaceAll(',', '.'));
                        final updated = settings.copyWith(
                          storeName: _storeNameController.text.trim().isEmpty
                              ? settings.storeName
                              : _storeNameController.text.trim(),
                          storePhone: _storePhoneController.text.trim(),
                          clearStorePhone: _storePhoneController.text.trim().isEmpty,
                          currency: _currency,
                          secondaryCurrencyCode: _secondaryCurrency,
                          exchangeRate: double.tryParse(_exchangeRateController.text.trim().replaceAll(',', '.')) ??
                              settings.exchangeRate,
                          // بيرجع يتخزن كنسبة عشرية (11 -> 0.11)
                          taxRate: parsedTaxPercent != null ? parsedTaxPercent / 100 : settings.taxRate,
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

  Future<void> _pickBluetoothPrinter(BuildContext context, AppSettingsModel settings) async {
    final l10n = context.l10n;
    final deps = AppScope.of(context);
    final appCubit = context.read<AppCubit>();

    final devices = await deps.bluetoothPrinterService.pairedDevices();
    if (!context.mounted) return;

    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.tr('noPairedPrinters'))));
      return;
    }

    final picked = await showDialog<BluetoothPrinterDevice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('selectPrinter')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final d = devices[index];
              return ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(d.name.isEmpty ? d.macAddress : d.name),
                subtitle: Text(d.macAddress),
                onTap: () => Navigator.of(ctx).pop(d),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.tr('cancel'))),
        ],
      ),
    );

    if (picked == null) return;
    await appCubit.updateSettings(
      settings.copyWith(printerMacAddress: picked.macAddress, printerName: picked.name),
    );
  }
}
