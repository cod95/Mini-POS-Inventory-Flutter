import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as s3;

/// Thrown when the database exists but cannot be opened (its key is gone).
class DatabaseUnreadableException implements Exception {
  const DatabaseUnreadableException();
  @override
  String toString() => 'DatabaseUnreadableException';
}

/// Encrypts the shop database on the phone with SQLCipher (AES-256). The key
/// is random, created on this phone and kept in the Android Keystore through
/// secure storage, so the database file alone is useless to anyone who copies
/// it. If encryption cannot be used on a phone the app keeps working with a
/// normal database and says so in Settings.
class DbSecurity {
  DbSecurity._();

  static const String dbName = 'mini_pos_inventory.sqlite';
  static const String pendingRestoreName = 'restore.pending.sqlite';
  static const String _keyName = 'quickstock_db_key_v1';

  /// 'encrypted' or 'plain' (set when the database is opened).
  static String status = 'unknown';

  /// True when the SQLCipher library is the one in use.
  static bool cipherAvailable = false;

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<File> databaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, dbName));
  }

  static Future<File> pendingRestoreFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, pendingRestoreName));
  }

  static bool _hasCipher() {
    s3.Database? db;
    try {
      db = s3.sqlite3.openInMemory();
      return db.select('PRAGMA cipher_version').isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      db?.dispose();
    }
  }

  static String _newKey() {
    final random = Random.secure();
    final b = StringBuffer();
    for (var i = 0; i < 32; i++) {
      b.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  static Future<String?> _readKey() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final value = await _storage.read(key: _keyName);
        if (value != null && value.length == 64) return value;
        return null;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    return null;
  }

  static bool _opens(File file, String? hex) {
    s3.Database? db;
    try {
      db = s3.sqlite3.open(file.path);
      if (hex != null) db.execute('PRAGMA key = "x\'$hex\'";');
      db.select('SELECT count(*) FROM sqlite_master');
      return true;
    } catch (_) {
      return false;
    } finally {
      db?.dispose();
    }
  }

  static void _wipe(File file) {
    try {
      if (!file.existsSync()) return;
      final length = file.lengthSync();
      final raf = file.openSync(mode: FileMode.write);
      final chunk = List<int>.filled(64 * 1024, 0);
      var written = 0;
      while (written < length) {
        final n = min(chunk.length, length - written);
        raf.writeFromSync(chunk, 0, n);
        written += n;
      }
      raf.flushSync();
      raf.closeSync();
      file.deleteSync();
    } catch (_) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  /// Turns a plain database into an encrypted one. The plain file is only
  /// removed after the encrypted copy was opened successfully.
  static bool _encryptInPlace(File file, String hex) {
    final tmp = File('${file.path}.enc');
    final old = File('${file.path}.plain');
    try {
      if (tmp.existsSync()) tmp.deleteSync();
      if (old.existsSync()) old.deleteSync();
      final db = s3.sqlite3.open(file.path);
      try {
        final version = db.select('PRAGMA user_version').first.values.first as int;
        db.execute("ATTACH DATABASE '${tmp.path}' AS encrypted KEY \"x'$hex'\";");
        db.select("SELECT sqlcipher_export('encrypted');");
        db.execute('PRAGMA encrypted.user_version = $version;');
        db.execute('DETACH DATABASE encrypted;');
      } finally {
        db.dispose();
      }
      if (!_opens(tmp, hex)) {
        tmp.deleteSync();
        return false;
      }
      file.renameSync(old.path);
      tmp.renameSync(file.path);
      if (!_opens(file, hex)) {
        file.deleteSync();
        old.renameSync(file.path);
        return false;
      }
      _wipe(old);
      return true;
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
        if (!file.existsSync() && old.existsSync()) old.renameSync(file.path);
      } catch (_) {}
      return false;
    }
  }

  /// A backup waiting to be restored replaces the database before it opens.
  static Future<void> _applyPendingRestore(File file) async {
    final pending = await pendingRestoreFile();
    if (!pending.existsSync()) return;
    try {
      if (_opens(pending, null)) {
        if (file.existsSync()) {
          final prev = File('${file.path}.before-restore');
          if (prev.existsSync()) prev.deleteSync();
          file.renameSync(prev.path);
        }
        pending.renameSync(file.path);
      } else {
        _wipe(pending);
      }
    } catch (_) {
      _wipe(pending);
    }
  }

  static LazyDatabase openConnection() {
    return LazyDatabase(() async {
      final file = await databaseFile();
      await _applyPendingRestore(file);

      try {
        await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
        open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
      } catch (_) {}
      cipherAvailable = _hasCipher();

      String? hex;
      var useKey = false;
      if (cipherAvailable) {
        hex = await _readKey();
        final exists = file.existsSync() && file.lengthSync() > 0;
        if (hex == null) {
          if (exists && !_opens(file, null)) {
            // Encrypted by a key that is no longer on this phone.
            throw const DatabaseUnreadableException();
          }
          hex = _newKey();
          await _storage.write(key: _keyName, value: hex);
          if (await _readKey() != hex) hex = null;
        }
        if (hex != null) {
          if (!exists || _opens(file, hex)) {
            useKey = true;
          } else if (_opens(file, null)) {
            useKey = _encryptInPlace(file, hex);
          } else {
            throw const DatabaseUnreadableException();
          }
        }
      }
      status = useKey ? 'encrypted' : 'plain';

      final key = hex;
      return NativeDatabase(
        file,
        setup: (raw) {
          if (useKey && key != null) {
            raw.execute('PRAGMA key = "x\'$key\'";');
          }
        },
      );
    });
  }

  /// Last resort when the key is lost and there is no backup: puts the
  /// unreadable database aside so the app can start empty.
  static Future<void> setUnreadableAside() async {
    final file = await databaseFile();
    if (file.existsSync()) {
      final aside = File('${file.path}.unreadable-${DateTime.now().millisecondsSinceEpoch}');
      file.renameSync(aside.path);
    }
    try {
      await _storage.delete(key: _keyName);
    } catch (_) {}
  }
}
