import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backup/backup_service.dart';
import '../data/local/db/secure_connection.dart';

/// Shown instead of the app when the database cannot be opened (for example
/// its key was wiped from the phone). The owner can restore a backup or, as a
/// last resort, start empty.
class RecoveryApp extends StatefulWidget {
  const RecoveryApp({super.key, required this.error});

  final Object error;

  @override
  State<RecoveryApp> createState() => _RecoveryAppState();
}

class _RecoveryAppState extends State<RecoveryApp> {
  final _password = TextEditingController();
  String? _message;
  bool _staged = false;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await BackupService.stageRestore(File(path), _password.text);
      setState(() {
        _staged = true;
        _message = 'تمام. سكّر التطبيق وافتحو من جديد.\nDone. Close the app and open it again.';
      });
    } catch (e) {
      setState(() => _message = e is BackupException && e.code == 'WRONG_PASSWORD'
          ? 'كلمة السر غلط أو الملف تالف.\nWrong password or damaged file.'
          : 'هاد مش ملف نسخة صحيح.\nThis is not a valid backup file.');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _startEmpty() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('البدء من الصفر؟ / Start empty?'),
        content: const Text(
          'البيانات الحالية ما عاد بتنقرا. هالخيار بيفتح التطبيق فاضي.\n'
          'The current data can no longer be read. This opens the app empty.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء / Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ابدأ / Start')),
        ],
      ),
    );
    if (ok != true) return;
    await DbSecurity.setUnreadableAside();
    setState(() {
      _staged = true;
      _message = 'سكّر التطبيق وافتحو من جديد.\nClose the app and open it again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('QuickStock POS')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              widget.error is DatabaseUnreadableException
                  ? 'ما قدرنا نفتح قاعدة البيانات (مفتاح التشفير مش موجود على هالتلفون).\n'
                      'The database cannot be opened (its encryption key is not on this phone).'
                  : 'صار خطأ بفتح البيانات.\nSomething went wrong opening the data.\n\n${widget.error}',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة سر النسخة / Backup password'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore),
              label: const Text('استرجاع نسخة احتياطية / Restore a backup'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _startEmpty,
              child: const Text('البدء من الصفر / Start empty'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!),
            ],
            if (_staged) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('سكّر / Close')),
            ],
          ],
        ),
      ),
    );
  }
}
