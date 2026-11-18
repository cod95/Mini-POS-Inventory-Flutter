import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The signed content of a licence code.
class LicensePayload {
  const LicensePayload({
    required this.deviceId,
    required this.customer,
    required this.expiry,
    required this.issued,
    this.devices = 1,
  });

  final String deviceId;
  final String customer;

  /// Last valid day, or null for an unlimited licence.
  final DateTime? expiry;
  final DateTime? issued;

  /// Number of phones this licence covers (the main phone included).
  final int devices;
}

/// Checks licence codes: `QS1.<payload>.<signature>` where the signature is
/// ECDSA P-256 / SHA-256 (r || s) over the payload bytes.
class LicenseVerifier {
  LicenseVerifier._();

  static Uint8List _b64u(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    while (v.length % 4 != 0) {
      v += '=';
    }
    return Uint8List.fromList(base64.decode(v));
  }

  static BigInt _big(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static int _devices(Object? raw) {
    final n = raw is int ? raw : int.tryParse('$raw') ?? 1;
    return n < 1 ? 1 : (n > 500 ? 500 : n);
  }

  /// Returns the payload when [token] carries a valid signature for the key
  /// ([publicX], [publicY] in hex); otherwise null.
  static LicensePayload? verify(String token, String publicX, String publicY) {
    try {
      final parts = token.trim().split('.');
      if (parts.length != 3 || parts[0] != 'QS1') return null;
      final payloadBytes = _b64u(parts[1]);
      final sig = _b64u(parts[2]);
      if (sig.length != 64) return null;

      final params = ECCurve_secp256r1();
      final point = params.curve.createPoint(
        BigInt.parse(publicX, radix: 16),
        BigInt.parse(publicY, radix: 16),
      );
      final signer = ECDSASigner(SHA256Digest())
        ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, params)));
      final ok = signer.verifySignature(
        payloadBytes,
        ECSignature(_big(sig.sublist(0, 32)), _big(sig.sublist(32))),
      );
      if (!ok) return null;

      final map = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      final expiry = map['e'] as String?;
      final issued = map['i'] as String?;
      return LicensePayload(
        deviceId: '${map['d']}',
        customer: '${map['c'] ?? ''}',
        expiry: expiry == null ? null : DateTime.tryParse(expiry),
        issued: issued == null ? null : DateTime.tryParse(issued),
        devices: _devices(map['n']),
      );
    } catch (_) {
      return null;
    }
  }
}
