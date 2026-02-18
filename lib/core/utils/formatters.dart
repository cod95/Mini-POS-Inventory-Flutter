import 'package:intl/intl.dart';

class AppFormatters {
  const AppFormatters._();

  static String money(double value, {String currency = 'EGP'}) {
    final format = NumberFormat.currency(symbol: '$currency ', decimalDigits: 2);
    return format.format(value);
  }

  static String shortDate(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm').format(value);
  }
}
