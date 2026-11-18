/// Developer keys that protect the app against unlicensed copies.
///
/// Fill these three values from the output of `tools/license-tool.html`
/// (they are public: the private signing key never leaves the developer).
/// While they are empty the licence check is switched off.
class LicenseConfig {
  LicenseConfig._();

  /// Public key (P-256, hex) that licence codes are verified with.
  static const String publicKeyX = '9c398eea645a927047e03e64c5dadde77f7b7ad77a56725729e5c213540fb93f';
  static const String publicKeyY = 'ddc9d90b24148eab56bed2d5dcb938de8c4faf889bc0bec0a3e7fd810676ed75';

  /// Verifier of the developer's master password (PBKDF2). The password
  /// itself is known only to the developer.
  static const String masterVerifier =
      r'pbkdf2$200000$3vJVRWK5mHOXcUezKq+xFA==$b9d0KHwllQeUrf2zIsLL7RCiNPHW0OFBEpy6JiqDBc4=';

  static bool get configured => publicKeyX.isNotEmpty && publicKeyY.isNotEmpty;
}
