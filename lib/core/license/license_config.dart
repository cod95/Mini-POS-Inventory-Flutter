/// Developer keys that protect the app against unlicensed copies.
///
/// Fill these three values from the output of `tools/license-tool.html`
/// (they are public: the private signing key never leaves the developer).
/// While they are empty the licence check is switched off.
class LicenseConfig {
  LicenseConfig._();

  /// Public key (P-256, hex) that licence codes are verified with.
  static const String publicKeyX = '';
  static const String publicKeyY = '';

  /// Verifier of the developer's master password (PBKDF2). The password
  /// itself is known only to the developer.
  static const String masterVerifier = '';

  static bool get configured => publicKeyX.isNotEmpty && publicKeyY.isNotEmpty;
}
