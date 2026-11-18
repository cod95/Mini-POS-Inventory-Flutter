import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Slow, salted hashing for passwords and PINs (PBKDF2-HMAC-SHA256).
///
/// Stored form: `pbkdf2$<iterations>$<salt base64>$<hash base64>`.
/// Anything else is treated as an old plain-text secret and is upgraded the
/// first time its owner logs in.
class SecretHasher {
  SecretHasher._();

  static const String _prefix = 'pbkdf2';
  static const int iterations = 100000;

  static bool isHashed(String stored) => stored.startsWith('$_prefix\$');

  static Future<String> hash(String secret) => Isolate.run(() => _hashSync(secret, iterations));

  static Future<bool> verify(String secret, String stored) {
    if (!isHashed(stored)) {
      return Future.value(constantTimeEquals(utf8.encode(secret), utf8.encode(stored)));
    }
    return Isolate.run(() => _verifySync(secret, stored));
  }

  static String _hashSync(String secret, int rounds) {
    final salt = randomBytes(16);
    final out = pbkdf2(secret, salt, rounds, 32);
    return '$_prefix\$$rounds\$${base64.encode(salt)}\$${base64.encode(out)}';
  }

  static bool _verifySync(String secret, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 4) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1000) return false;
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final actual = pbkdf2(secret, Uint8List.fromList(salt), rounds, expected.length);
    return constantTimeEquals(actual, expected);
  }

  static Uint8List pbkdf2(String secret, Uint8List salt, int rounds, int length) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, rounds, length));
    return derivator.process(Uint8List.fromList(utf8.encode(secret)));
  }

  static Uint8List randomBytes(int n) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => random.nextInt(256)));
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    final n = min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Minimum quality for passwords (admin) and PINs (cashier).
class SecretPolicy {
  SecretPolicy._();

  static const Set<String> _weak = {
    '1234', '0000', '1111', '2222', '4321', '123456', '000000', '111111',
    '12345678', 'admin', 'admin123', 'password', 'qwerty', '123123',
  };

  /// Returns a message (Arabic + English) when [secret] is not acceptable.
  static String? check(String secret, {required bool isAdmin}) {
    final s = secret.trim();
    if (isAdmin && s.length < 6) {
      return 'كلمة المرور 6 خانات على الأقل / Password needs at least 6 characters';
    }
    if (!isAdmin && s.length < 4) {
      return 'الرمز السري 4 خانات على الأقل / PIN needs at least 4 characters';
    }
    if (_weak.contains(s.toLowerCase())) {
      return 'هذه كلمة مرور ضعيفة ومعروفة، اختر غيرها / This secret is too common, choose another';
    }
    return null;
  }
}
