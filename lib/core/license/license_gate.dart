import '../errors/app_exception.dart';

/// What an unlicensed (trial) copy may do. A licensed copy has no limits.
abstract class LicenseGate {
  /// True when the app is fully licensed (or licensing is switched off).
  bool get full;

  static const int trialMaxProducts = 20;
  static const int trialMaxInvoices = 10;

  static const String productsMessage =
      'النسخة التجريبية تسمح بإضافة $trialMaxProducts منتجاً فقط. للمتابعة يلزم تفعيل الترخيص من المطوّر.';
  static const String invoicesMessage =
      'النسخة التجريبية تسمح بإصدار $trialMaxInvoices فواتير فقط. للمتابعة يلزم تفعيل الترخيص من المطوّر.';
  static const String usersMessage =
      'إضافة المستخدمين غير متاحة في النسخة التجريبية. يلزم تفعيل الترخيص من المطوّر.';

  /// Throws [AppException] with [message] unless the app is fully licensed.
  void requireFull(String message) {
    if (!full) throw AppException(message);
  }
}

/// Used where no licence service exists (tests): never limits anything.
class OpenGate extends LicenseGate {
  @override
  bool get full => true;
}
