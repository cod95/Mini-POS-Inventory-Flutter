import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/state/app_cubit.dart';
import '../../../../data/sync/file_sync_service.dart';
import '../../../../data/sync/lan_sync_service.dart';

/// Admin: send this phone's data to the other phone, or receive the other
/// phone's file. Works through any file channel (WhatsApp, Bluetooth, USB).
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  bool _busy = false;
  String? _message;
  bool _isError = false;
  String? _code;
  bool _codeLoaded = false;
  bool _isMain = false;
  bool _autoSync = true;
  String _hubAddress = '';
  List<String> _addresses = const [];

  bool get _ar => context.l10n.isArabic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_codeLoaded) {
      _codeLoaded = true;
      _loadCode();
    }
  }

  Future<void> _loadCode() async {
    final deps = AppScope.of(context);
    final code = await deps.fileSyncService.getSyncCode();
    final row = await deps.fileSyncService.settings();
    final addresses = await deps.lanSyncService.localAddresses();
    if (!mounted) return;
    setState(() {
      _code = code;
      _isMain = row.isMainDevice;
      _autoSync = row.autoSync;
      _hubAddress = row.hubAddress ?? '';
      _addresses = addresses;
    });
  }

  String _statusText(LanSyncStatus st) {
    final ar = _ar;
    switch (st.state) {
      case 'off':
        return ar
            ? 'متوقفة. أدخل رمز المحل وفعّل المزامنة التلقائية.'
            : 'Off. Set the shop code and turn automatic sync on.';
      case 'searching':
        return ar ? 'جارٍ البحث عن هاتف المدير على الشبكة نفسها…' : 'Looking for the admin phone on this network…';
      case 'syncing':
        return ar ? 'جارٍ المزامنة…' : 'Syncing…';
      case 'connected':
        if (_isMain) {
          return ar ? 'جاهز. تتصل الهواتف الأخرى تلقائياً.' : 'Ready. The other phones connect by themselves.';
        }
        return ar ? 'متصل بـ ${st.peerName ?? 'المدير'}' : 'Connected to ${st.peerName ?? 'admin'}';
      default:
        switch (st.error) {
          case 'UNREACHABLE':
            return ar
                ? 'تعذّر الاتصال بهاتف المدير. تأكد أن التطبيق مفتوح عنده وأن الهاتفين على شبكة الواي فاي نفسها.'
                : 'Cannot reach the admin phone. Make sure the app is open there and both are on the same Wi-Fi.';
          case 'WRONG_CODE':
            return ar ? 'رمز المحل مختلف بين الهاتفين.' : 'The shop code differs between the two phones.';
          case 'CLOCK':
            return ar ? 'وقت الهاتفين مختلف كثيراً، يرجى ضبط الساعة.' : 'The phones\' clocks differ too much. Fix the time.';
          case 'two-main':
            return ar
                ? 'يوجد أكثر من هاتف «رئيسي» على الشبكة. يجب إنشاء الرمز على هاتف المدير فقط.'
                : 'More than one main phone is on the network. Only the admin phone should create the code.';
          default:
            return st.error ?? '';
        }
    }
  }

  Future<void> _syncNow() async {
    final deps = AppScope.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    final error = await deps.lanSyncService.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = error != null;
      _message = error == null
          ? (_ar ? 'تمت المزامنة.' : 'Synced.')
          : _statusText(deps.lanSyncService.status.value.copyWith(state: 'error', error: error));
    });
  }

  Future<void> _editHubAddress() async {
    final deps = AppScope.of(context);
    final controller = TextEditingController(text: _hubAddress);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_ar ? 'عنوان هاتف المدير' : 'Admin phone address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '192.168.1.20',
            helperText: _ar
                ? 'استخدمه فقط إذا لم يُعثر عليه تلقائياً. يظهر على هاتف المدير في هذه الشاشة نفسها.'
                : 'Only if it is not found by itself. Shown on the admin phone in this screen.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(_ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () async {
              final value = controller.text.trim();
              await deps.fileSyncService
                  .updateSyncOptions(hubAddress: value, clearHubAddress: value.isEmpty);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text(_ar ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    await _loadCode();
  }

  Widget _autoCard(BuildContext context) {
    final deps = AppScope.of(context);
    final ar = _ar;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ValueListenableBuilder<LanSyncStatus>(
          valueListenable: deps.lanSyncService.status,
          builder: (context, st, _) {
            final isError = st.state == 'error';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wifi),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        ar ? 'المزامنة التلقائية (واي فاي)' : 'Automatic sync (Wi-Fi)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Switch.adaptive(
                      value: _autoSync,
                      onChanged: (value) async {
                        await deps.fileSyncService.updateSyncOptions(autoSync: value);
                        await _loadCode();
                      },
                    ),
                  ],
                ),
                Text(
                  _code == null
                      ? (ar ? 'أدخل رمز المحل أولاً.' : 'Set the shop code first.')
                      : (_isMain
                          ? (ar ? 'هذا هو هاتف المدير (الرئيسي).' : 'This is the admin (main) phone.')
                          : (ar ? 'هذا هاتف موظف.' : 'This is an employee phone.')),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _statusText(st),
                  style: TextStyle(
                    color: isError ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (st.lastSyncAt != null)
                  Text(
                    ar
                        ? 'آخر مزامنة: ${TimeOfDay.fromDateTime(st.lastSyncAt!).format(context)}'
                        : 'Last sync: ${TimeOfDay.fromDateTime(st.lastSyncAt!).format(context)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_isMain && _addresses.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar ? 'عنوان هذا الهاتف: ${_addresses.join('  ،  ')}' : 'This phone\'s address: ${_addresses.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  ar
                      ? 'تعمل والتطبيق مفتوح على الهاتفين وهما على الشبكة نفسها. تنتقل المبيعات إلى المدير، وتصل الأسعار والمنتجات والمستخدمون إلى الموظف.'
                      : 'Works while the app is open on both phones and they share a network. Sales go to the admin; prices, products and users come back.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!_isMain && _code != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _syncNow,
                        icon: const Icon(Icons.sync),
                        label: Text(ar ? 'زامن الآن' : 'Sync now'),
                      ),
                      OutlinedButton(
                        onPressed: _editHubAddress,
                        child: Text(
                          _hubAddress.isEmpty
                              ? (ar ? 'إدخال العنوان يدوياً' : 'Enter address manually')
                              : (ar ? 'العنوان: $_hubAddress' : 'Address: $_hubAddress'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _createCode() async {
    final service = AppScope.of(context).fileSyncService;
    if (_code != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_ar ? 'رمز جديد؟' : 'New code?'),
          content: Text(_ar
              ? 'يجب إدخال الرمز الجديد في الأجهزة الأخرى، وإلا لن تتمكن من قراءة ملفاتك.'
              : 'The other phones must enter the new code, otherwise they cannot read your files.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(_ar ? 'إلغاء' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(_ar ? 'تغيير' : 'Change')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await service.createSyncCode();
    await _loadCode();
  }

  Future<void> _enterCode() async {
    final service = AppScope.of(context).fileSyncService;
    final controller = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(_ar ? 'رمز المحل' : 'Shop code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'XXXX-XXXX-XXXX',
                  helperText: _ar ? 'الرمز الظاهر على هاتف المدير في شاشة المزامنة' : 'Shown on the admin phone in this screen',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(_ar ? 'إلغاء' : 'Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await service.setSyncCode(controller.text);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } on FormatException {
                  setLocal(() => error = _ar ? 'الرمز غير صحيح' : 'Invalid code');
                }
              },
              child: Text(_ar ? 'حفظ' : 'Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    await _loadCode();
  }

  String _describe(Object e) {
    if (e is FormatException) {
      switch (e.message) {
        case 'NO_SYNC_CODE':
          return _ar ? 'أدخل رمز المحل أولاً.' : 'Set the shop code first.';
        case 'WRONG_CODE':
          return _ar
              ? 'رمز المحل مختلف أو الملف تالف. تأكد من أن الجهازين يستخدمان الرمز نفسه.'
              : 'Different shop code or damaged file. Make sure both phones use the same code.';
        case 'NOT_A_SYNC_FILE':
          return _ar ? 'هذا الملف ليس ملف مزامنة صالحاً.' : 'This is not a valid sync file.';
      }
    }
    return e.toString();
  }

  Future<void> _export() async {
    final deps = AppScope.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final file = await deps.fileSyncService.exportToFile();
      await deps.fileSyncService.shareFile(file);
      setState(() {
        _isError = false;
        _message = _ar ? 'تم تجهيز ملف المزامنة.' : 'Sync file ready.';
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _message = _describe(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final deps = AppScope.of(context);
    final cubit = context.read<AppCubit>();
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await deps.fileSyncService.importFromFile(File(path));
      await cubit.initialize();
      if (!mounted) return;
      await _showResult(result);
      setState(() {
        _isError = false;
        _message = _ar ? 'تمت المزامنة.' : 'Sync complete.';
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _message = _describe(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResult(SyncImportResult r) {
    final ar = _ar;
    final lines = <String>[
      ar ? 'فواتير جديدة: ${r.newSales}' : 'New invoices: ${r.newSales}',
      ar ? 'فواتير تغيّرت حالتها: ${r.updatedSales}' : 'Invoices with new status: ${r.updatedSales}',
      ar ? 'حركات مخزون مطبّقة: ${r.appliedMovements}' : 'Stock movements applied: ${r.appliedMovements}',
      ar ? 'منتجات جديدة: ${r.newProducts}' : 'New products: ${r.newProducts}',
      ar ? 'منتجات معدّلة: ${r.updatedProducts}' : 'Updated products: ${r.updatedProducts}',
      if (r.usersChanged > 0) (ar ? 'مستخدمين: ${r.usersChanged}' : 'Users: ${r.usersChanged}'),
      if (r.settingsApplied) (ar ? 'تم تحديث إعدادات المحل' : 'Store settings updated'),
      if (r.assignedDeviceCode != null)
        (ar
            ? 'أصبح رمز هذا الجهاز: ${r.assignedDeviceCode} (يظهر في أرقام فواتيره)'
            : 'This device code is now ${r.assignedDeviceCode} (shown in its invoice numbers)'),
    ];
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'نتيجة المزامنة' : 'Sync result'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines) Text(line),
              if (r.warnings.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(ar ? 'ملاحظات:' : 'Notes:', style: Theme.of(ctx).textTheme.titleSmall),
                for (final w in r.warnings.take(10)) Text(w, style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ar ? 'حسناً' : 'OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;

    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'المزامنة بين الأجهزة' : 'Device sync')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _autoCard(context),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.vpn_key_outlined),
                      const SizedBox(width: AppSpacing.sm),
                      Text(ar ? 'رمز المحل' : 'Shop code', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (_code != null)
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _code!,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: 2),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () => Clipboard.setData(ClipboardData(text: _code!)),
                        ),
                      ],
                    )
                  else
                    Text(
                      ar
                          ? 'لا يوجد رمز بعد. على هاتف المدير اضغط «إنشاء رمز»، وعلى بقية الهواتف «إدخال الرمز».'
                          : 'No code yet. On the admin phone tap "Create code", on the other phones "Enter code".',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar
                        ? 'تُشفَّر جميع ملفات المزامنة بهذا الرمز، ويجب أن يكون الرمز نفسه في جميع هواتف المحل.'
                        : 'Every sync file is encrypted with this code. All phones of the shop must use the same one.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      if (context.read<AppCubit>().isAdmin)
                        OutlinedButton(
                          onPressed: _createCode,
                          child: Text(_code == null ? (ar ? 'إنشاء رمز' : 'Create code') : (ar ? 'رمز جديد' : 'New code')),
                        ),
                      OutlinedButton(onPressed: _enterCode, child: Text(ar ? 'إدخال الرمز' : 'Enter code')),
                    ],
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
                  Text(ar ? 'طريقة العمل' : 'How it works', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar
                        ? '1) على هاتف الموظف: شاشة المزامنة ← «إرسال مزامنة». يظهر ملف، أرسله عبر واتساب إلى هاتفك.\n'
                            '2) على هاتفك (المدير): اضغط «استلام مزامنة» واختر الملف. تُضاف المبيعات والمرتجعات ويُحدَّث المخزون.\n'
                            '3) بالعكس: اضغط «إرسال مزامنة» عندك وأرسل الملف إلى هاتف الموظف ليستلمه هناك، فتصله الأسعار والمنتجات الجديدة والمستخدمون.\n'
                            'استلام الملف نفسه مرتين لا يكرر أي شيء.'
                        : '1) On the employee phone: Account > "Send sales" (or from here as admin). Send the file to your phone.\n'
                            '2) On your phone (admin): tap "Receive sync" and pick the file. Sales and returns are merged and stock is updated.\n'
                            '3) The other way: tap "Send sync" on your phone and import it on the employee phone as admin. That sends prices, new products and users.\n'
                            'Importing the same file twice never duplicates anything.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.send),
            label: Text(ar ? 'إرسال مزامنة' : 'Send sync'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.download),
            label: Text(ar ? 'استلام مزامنة' : 'Receive sync'),
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _message!,
              style: TextStyle(
                color: _isError ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
