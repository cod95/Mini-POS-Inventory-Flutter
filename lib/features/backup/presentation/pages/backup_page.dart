import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../data/backup/backup_service.dart';
import '../../../../data/local/db/secure_connection.dart';

/// Admin: protection status of the data, encrypted backup and restore.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String? _message;
  bool _isError = false;
  bool _restoreStaged = false;

  bool get _ar => context.l10n.isArabic;

  String _describe(Object e) {
    final ar = _ar;
    if (e is BackupException) {
      switch (e.code) {
        case 'SHORT_PASSWORD':
          return ar ? 'كلمة المرور 6 خانات على الأقل.' : 'Password needs at least 6 characters.';
        case 'WRONG_PASSWORD':
          return ar ? 'كلمة المرور غير صحيحة أو الملف تالف.' : 'Wrong password or damaged file.';
        case 'NOT_A_BACKUP':
          return ar ? 'هذا ليس ملف نسخة احتياطية صالحاً.' : 'This is not a valid backup file.';
      }
    }
    return e.toString();
  }

  Future<String?> _askPassword({required bool confirm}) async {
    final ar = _ar;
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(ar ? 'كلمة مرور النسخة' : 'Backup password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: first,
                obscureText: true,
                decoration: InputDecoration(labelText: ar ? 'كلمة المرور' : 'Password'),
              ),
              if (confirm)
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration: InputDecoration(labelText: ar ? 'أعد إدخالها' : 'Repeat it'),
                ),
              if (confirm)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    ar
                        ? 'احتفظ بها جيداً. بدونها لا يمكن استرجاع النسخة.'
                        : 'Keep it safe. Without it the backup cannot be restored.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              if (error != null) Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ar ? 'إلغاء' : 'Cancel')),
            FilledButton(
              onPressed: () {
                if (first.text.length < 6 && confirm) {
                  setLocal(() => error = ar ? '6 خانات على الأقل' : 'At least 6 characters');
                  return;
                }
                if (confirm && first.text != second.text) {
                  setLocal(() => error = ar ? 'غير متطابقتين' : 'They do not match');
                  return;
                }
                Navigator.of(ctx).pop(first.text);
              },
              child: Text(ar ? 'متابعة' : 'Continue'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> _backup() async {
    final service = AppScope.of(context).backupService;
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final file = await service.createBackup(password);
      await service.shareBackup(file);
      setState(() {
        _isError = false;
        _message = _ar ? 'تم تجهيز النسخة الاحتياطية.' : 'Backup ready.';
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

  Future<void> _restore() async {
    final ar = _ar;
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'استرجاع النسخة؟' : 'Restore backup?'),
        content: Text(ar
            ? 'ستُستبدل جميع البيانات الحالية ببيانات النسخة، ويتم الاسترجاع عند إعادة فتح التطبيق.'
            : 'All current data is replaced by the backup. The restore happens when the app is opened again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ar ? 'استرجاع' : 'Restore')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await BackupService.stageRestore(File(path), password);
      setState(() {
        _isError = false;
        _restoreStaged = true;
        _message = ar
            ? 'تم. أغلق التطبيق ثم افتحه من جديد لإتمام الاسترجاع.'
            : 'Done. Close the app and open it again to finish the restore.';
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

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final encrypted = DbSecurity.status == 'encrypted';
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'الحماية والنسخ الاحتياطي' : 'Protection & backup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                encrypted ? Icons.verified_user : Icons.warning_amber_rounded,
                color: encrypted ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
              ),
              title: Text(ar ? 'تشفير قاعدة البيانات' : 'Database encryption'),
              subtitle: Text(
                encrypted
                    ? (ar
                        ? 'مفعّل (AES-256). لا يمكن قراءة ملف البيانات دون مفتاح هذا الهاتف.'
                        : 'Active (AES-256). The data file cannot be read without this phone\'s key.')
                    : (ar
                        ? 'غير مفعّل على هذا الهاتف. احرص على أخذ نسخة احتياطية بشكل دوري.'
                        : 'Not active on this phone. Make backups regularly.'),
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
                  Text(ar ? 'نسخة احتياطية مشفّرة' : 'Encrypted backup', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ar
                        ? 'ملف واحد يحوي جميع المنتجات والفواتير والمستخدمين والإعدادات، محميّ بكلمة مرور. أرسله إلى نفسك (واتساب، بريد إلكتروني، ذاكرة خارجية). ويمكن استرجاعه على أي هاتف.'
                        : 'One file with all products, invoices, users and settings, protected by a password. Send it to yourself (WhatsApp, email, USB). It restores on any phone.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _backup,
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(ar ? 'إنشاء نسخة' : 'Create backup'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _restore,
                        icon: const Icon(Icons.restore),
                        label: Text(ar ? 'استرجاع نسخة' : 'Restore backup'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
          if (_restoreStaged) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: Text(ar ? 'إغلاق التطبيق الآن' : 'Close the app now'),
            ),
          ],
        ],
      ),
    );
  }
}
