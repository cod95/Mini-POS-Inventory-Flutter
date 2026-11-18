import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/backup/backup_service.dart';
import '../data/local/db/secure_connection.dart';
import 'theme/app_theme.dart';

/// Shown instead of the app when the database cannot be opened, for example
/// when the phone lost its encryption key. An admin password restores the key;
/// otherwise a backup can be restored.
class RecoveryApp extends StatefulWidget {
  const RecoveryApp({super.key, required this.error});

  final Object error;

  @override
  State<RecoveryApp> createState() => _RecoveryAppState();
}

class _RecoveryAppState extends State<RecoveryApp> {
  final _adminPassword = TextEditingController();
  final _backupPassword = TextEditingController();
  String? _message;
  bool _isError = false;
  bool _staged = false;
  bool _busy = false;

  @override
  void dispose() {
    _adminPassword.dispose();
    _backupPassword.dispose();
    super.dispose();
  }

  void _done(String message) {
    setState(() {
      _busy = false;
      _staged = true;
      _isError = false;
      _message = message;
    });
  }

  void _fail(String message) {
    setState(() {
      _busy = false;
      _isError = true;
      _message = message;
    });
  }

  Future<void> _recoverKey() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await DbSecurity.recoverKey(_adminPassword.text);
    if (!mounted) return;
    if (ok) {
      _done('تمت استعادة مفتاح التشفير. أغلق التطبيق ثم افتحه من جديد.');
    } else {
      _fail('كلمة المرور غير صحيحة، أو لا توجد نسخة محفوظة من المفتاح لهذا الحساب.');
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await BackupService.stageRestore(File(path), _backupPassword.text);
      _done('تم تجهيز الاسترجاع. أغلق التطبيق ثم افتحه من جديد.');
    } catch (e) {
      _fail(e is BackupException && e.code == 'WRONG_PASSWORD'
          ? 'كلمة مرور النسخة غير صحيحة أو الملف تالف.'
          : 'هذا ليس ملف نسخة احتياطية صالحاً.');
    }
  }

  Future<void> _startEmpty(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('البدء من الصفر؟'),
        content: const Text(
          'تعذّرت قراءة البيانات الحالية. سيُفتح التطبيق فارغاً، وتُحفظ البيانات القديمة جانباً دون حذف.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ابدأ')),
        ],
      ),
    );
    if (ok != true) return;
    await DbSecurity.setUnreadableAside();
    _done('أغلق التطبيق ثم افتحه من جديد.');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('QuickStock POS')),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.error is DatabaseUnreadableException
                    ? 'تعذّر فتح قاعدة البيانات لأن مفتاح التشفير لم يعد موجوداً على هذا الهاتف. بياناتك محفوظة ويمكن استعادتها.'
                    : 'حدث خطأ أثناء فتح البيانات.\n\n${widget.error}',
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('١) استعادة المفتاح بكلمة مرور المدير', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _adminPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة مرور أحد المدراء'),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _busy ? null : _recoverKey,
                icon: const Icon(Icons.key),
                label: const Text('استعادة المفتاح'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('٢) استرجاع نسخة احتياطية', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _backupPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة مرور النسخة'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restoreBackup,
                icon: const Icon(Icons.restore),
                label: const Text('اختيار ملف النسخة'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: _busy ? null : () => _startEmpty(context),
                child: const Text('البدء من الصفر (الخيار الأخير)'),
              ),
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _isError ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (_staged) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('إغلاق التطبيق')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
