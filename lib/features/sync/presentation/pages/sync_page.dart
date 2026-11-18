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
    final code = await AppScope.of(context).fileSyncService.getSyncCode();
    if (mounted) setState(() => _code = code);
  }

  Future<void> _createCode() async {
    final service = AppScope.of(context).fileSyncService;
    if (_code != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_ar ? 'رمز جديد؟' : 'New code?'),
          content: Text(_ar
              ? 'الأجهزة التانية لازم تدخل الرمز الجديد، وإلا ما رح تقدر تقرا ملفاتك.'
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
                  helperText: _ar ? 'الرمز الظاهر عند الأدمن بشاشة المزامنة' : 'Shown on the admin phone in this screen',
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
          return _ar ? 'حط رمز المحل أول شي.' : 'Set the shop code first.';
        case 'WRONG_CODE':
          return _ar
              ? 'رمز المحل مختلف أو الملف تالف. تأكد إن الجهازين عندن نفس الرمز.'
              : 'Different shop code or damaged file. Make sure both phones use the same code.';
        case 'NOT_A_SYNC_FILE':
          return _ar ? 'هاد الملف مش ملف مزامنة صحيح.' : 'This is not a valid sync file.';
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
      final isAdmin = context.read<AppCubit>().isAdmin;
      final file = await deps.fileSyncService.exportToFile(includeAdminData: isAdmin);
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
            ? 'رمز هالجهاز صار: ${r.assignedDeviceCode} (بيظهر بأرقام فواتيره)'
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
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ar ? 'تمام' : 'OK')),
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
                          ? 'لسا ما في رمز. على تلفون الأدمن اضغط "إنشاء رمز"، وعلى باقي التلفونات "إدخال الرمز".'
                          : 'No code yet. On the admin phone tap "Create code", on the other phones "Enter code".',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar
                        ? 'كل ملفات المزامنة بتتشفّر بهالرمز. نفس الرمز لازم يكون عند كل تلفونات المحل.'
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
                  Text(ar ? 'كيف بتشتغل' : 'How it works', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar
                        ? '1) على تلفون الموظف: حسابو > "إرسال المبيعات" (أو من هون إذا دخلت كأدمن). بيطلع ملف، ابعتو واتساب لتلفونك.\n'
                            '2) على تلفونك (الأدمن): اضغط "استلام مزامنة" واختار الملف. المبيعات والمرتجعات بتنضم، والمخزون بيتعدل.\n'
                            '3) بالعكس: اضغط "إرسال مزامنة" عندك وابعت الملف لتلفون الموظف، بيستلمو الأدمن عندو. هيك بيوصل الموظف الأسعار والمنتجات الجديدة والمستخدمين.\n'
                            'استلام نفس الملف مرتين ما بيكرّر شي.'
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
