import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'secret_hasher.dart';

/// Thrown when data cannot be decrypted (wrong shop code or damaged data).
class SyncDecryptException implements Exception {
  const SyncDecryptException();
  @override
  String toString() => 'SyncDecryptException';
}

/// AES-256-GCM encryption for everything that leaves the phone during sync
/// (files and network). The key comes from the "shop code" both phones share.
class SyncCrypto {
  SyncCrypto._();

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const List<int> magic = [0x51, 0x53, 0x59, 0x4e, 0x43, 0x32]; // "QSYNC2"
  static const int _nonceLength = 12;

  /// A new random shop code, e.g. `K7QD-39XM-RT4P`.
  static String generateCode() {
    final random = Random.secure();
    final chars = List<String>.generate(12, (_) => _alphabet[random.nextInt(_alphabet.length)]);
    return '${chars.sublist(0, 4).join()}-${chars.sublist(4, 8).join()}-${chars.sublist(8, 12).join()}';
  }

  static String normalize(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool isValidCode(String code) => normalize(code).length == 12;

  static String pretty(String code) {
    final n = normalize(code);
    if (n.length != 12) return code;
    return '${n.substring(0, 4)}-${n.substring(4, 8)}-${n.substring(8, 12)}';
  }

  static Future<Uint8List> deriveKey(String code) {
    final normalized = normalize(code);
    return Isolate.run(() => SecretHasher.pbkdf2(
          normalized,
          Uint8List.fromList(utf8.encode('quickstock-sync-v2')),
          30000,
          32,
        ));
  }

  static Future<Uint8List> encrypt(Uint8List plain, Uint8List key) =>
      Isolate.run(() => encryptSync(plain, key));

  static Future<Uint8List> decrypt(Uint8List blob, Uint8List key) =>
      Isolate.run(() => decryptSync(blob, key));

  /// nonce (12) + ciphertext + tag (16).
  static Uint8List encryptSync(Uint8List plain, Uint8List key) {
    final nonce = SecretHasher.randomBytes(_nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final body = cipher.process(plain);
    final out = BytesBuilder()
      ..add(nonce)
      ..add(body);
    return out.toBytes();
  }

  static Uint8List decryptSync(Uint8List blob, Uint8List key) {
    if (blob.length < _nonceLength + 16) throw const SyncDecryptException();
    try {
      final nonce = Uint8List.sublistView(blob, 0, _nonceLength);
      final body = Uint8List.sublistView(blob, _nonceLength);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
      return cipher.process(body);
    } catch (_) {
      throw const SyncDecryptException();
    }
  }

  static bool hasMagic(Uint8List raw) {
    if (raw.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (raw[i] != magic[i]) return false;
    }
    return true;
  }
}
