import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/security/secret_hasher.dart';
import '../../core/security/sync_crypto.dart';
import '../local/db/app_database.dart';
import '../local/db/secure_connection.dart';

class BackupException implements Exception {
  const BackupException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Password-protected backup of the whole shop database (`.qbackup`).
///
/// A backup can be restored on any phone with the same password. Restoring
/// only stages the file; the swap happens the next time the app opens, before
/// the database is opened.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const List<int> _magic = [0x51, 0x42, 0x4b, 0x31]; // "QBK1"
  static const List<int> _sqliteHeader = [
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
  ];

  Future<File> createBackup(String password) async {
    if (password.length < 6) throw const BackupException('SHORT_PASSWORD');
    final dir = await getTemporaryDirectory();
    final plain = File(p.join(dir.path, 'qs_backup_${DateTime.now().millisecondsSinceEpoch}.sqlite'));
    try {
      if (plain.existsSync()) plain.deleteSync();
      final versionRow = await _db.customSelect('PRAGMA user_version').getSingle();
      final version = versionRow.read<int>('user_version');
      if (DbSecurity.cipherAvailable) {
        await _db.customStatement("ATTACH DATABASE '${plain.path}' AS backup KEY ''");
        try {
          await _db.customSelect("SELECT sqlcipher_export('backup')").get();
          await _db.customStatement('PRAGMA backup.user_version = $version');
        } finally {
          await _db.customStatement('DETACH DATABASE backup');
        }
      } else {
        await _db.customStatement("VACUUM INTO '${plain.path}'");
      }

      final bytes = await plain.readAsBytes();
      final salt = SecretHasher.randomBytes(16);
      final blob = await Isolate.run(() {
        final key = SecretHasher.pbkdf2(password, salt, SecretHasher.iterations, 32);
        return SyncCrypto.encryptSync(bytes, key);
      });

      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
      final out = File(p.join(dir.path, 'quickstock_backup_$stamp.qbackup'));
      final builder = BytesBuilder()
        ..add(_magic)
        ..add(salt)
        ..add(blob);
      await out.writeAsBytes(builder.toBytes(), flush: true);
      return out;
    } finally {
      try {
        if (plain.existsSync()) {
          plain.writeAsBytesSync(Uint8List(plain.lengthSync()));
          plain.deleteSync();
        }
      } catch (_) {}
    }
  }

  Future<void> shareBackup(File file) => Share.shareXFiles([XFile(file.path)]);

  /// Checks the password and stages the backup. Takes effect when the app is
  /// reopened. Works even when the database cannot be opened.
  static Future<void> stageRestore(File backup, String password) async {
    final raw = await backup.readAsBytes();
    if (raw.length < _magic.length + 16 + 28) throw const BackupException('NOT_A_BACKUP');
    for (var i = 0; i < _magic.length; i++) {
      if (raw[i] != _magic[i]) throw const BackupException('NOT_A_BACKUP');
    }
    final salt = Uint8List.fromList(raw.sublist(_magic.length, _magic.length + 16));
    final body = Uint8List.fromList(raw.sublist(_magic.length + 16));
    final Uint8List plain;
    try {
      plain = await Isolate.run(() {
        final key = SecretHasher.pbkdf2(password, salt, SecretHasher.iterations, 32);
        return SyncCrypto.decryptSync(body, key);
      });
    } on SyncDecryptException {
      throw const BackupException('WRONG_PASSWORD');
    }
    if (plain.length < _sqliteHeader.length) throw const BackupException('NOT_A_BACKUP');
    for (var i = 0; i < _sqliteHeader.length; i++) {
      if (plain[i] != _sqliteHeader[i]) throw const BackupException('NOT_A_BACKUP');
    }
    final pending = await DbSecurity.pendingRestoreFile();
    await pending.writeAsBytes(plain, flush: true);
  }
}
