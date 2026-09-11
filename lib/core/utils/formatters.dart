import 'package:intl/intl.dart';

class AppFormatters {
  const AppFormatters._();

  /// [valueInUsd] هو السعر كما هو مخزّن دايمًا بقاعدة البيانات (بالدولار).
  /// [currency] هي العملة الأساسية المختارة حاليًا بالإعدادات ('USD' أو 'LBP').
  /// [exchangeRate] معناها ثابت دايمًا: 1 دولار = كم ليرة لبنانية.
  static String money(
    double valueInUsd, {
    String currency = 'USD',
    double exchangeRate = 1,
  }) {
    final displayValue = currency == 'LBP' ? valueInUsd * exchangeRate : valueInUsd;
    final decimals = currency == 'LBP' ? 0 : 2;
    final format = NumberFormat.currency(symbol: '$currency ', decimalDigits: decimals);
    return format.format(displayValue);
  }

  /// يحوّل رقم أدخله المستخدم بالعملة الحالية إلى دولار (عملة التخزين الثابتة).
  static double toUsd(
    double valueInCurrentCurrency, {
    required String currency,
    required double exchangeRate,
  }) {
    if (currency == 'LBP' && exchangeRate > 0) {
      return valueInCurrentCurrency / exchangeRate;
    }
    return valueInCurrentCurrency;
  }

  static String shortDate(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value);
  }
}
