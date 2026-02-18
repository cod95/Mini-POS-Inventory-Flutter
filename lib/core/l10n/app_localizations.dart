import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('ar')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return localizations ?? AppLocalizations(const Locale('en'));
  }

  bool get isArabic => locale.languageCode == 'ar';

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'appTitle': 'Mini POS + Inventory',
      'login': 'Login',
      'pin': 'Cashier PIN',
      'adminPassword': 'Admin Password',
      'continueAsCashier': 'Continue as cashier',
      'continueAsAdmin': 'Continue as admin',
      'invalidCredentials': 'Invalid credentials',
      'pos': 'POS',
      'products': 'Products',
      'reports': 'Reports',
      'settings': 'Settings',
      'searchProducts': 'Search products, SKU, barcode',
      'checkout': 'Checkout',
      'total': 'Total',
      'paid': 'Paid',
      'change': 'Change',
      'tax': 'Tax',
      'discount': 'Discount',
      'orderDiscount': 'Order discount',
      'cartEmpty': 'Cart is empty',
      'addProduct': 'Add product',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'stock': 'Stock',
      'lowStock': 'Low stock',
      'invoiceHistory': 'Invoice history',
      'dashboard': 'Dashboard',
      'exportSalesCsv': 'Export sales CSV',
      'exportInventoryCsv': 'Export inventory CSV',
      'sharePdf': 'Share PDF',
      'printReceipt': 'Print receipt',
      'newSale': 'New sale',
      'syncNow': 'Sync now',
      'language': 'Language',
      'storeSettings': 'Store settings',
      'allowNegativeStock': 'Allow negative stock',
      'taxEnabled': 'Enable tax',
      'currency': 'Currency',
      'storeName': 'Store name',
      'receiptHeader': 'Receipt header',
      'receiptFooter': 'Receipt footer',
      'english': 'English',
      'arabic': 'Arabic',
      'loading': 'Loading...',
      'empty': 'No data yet',
      'error': 'Something went wrong',
      'retry': 'Retry',
    },
    'ar': {
      'appTitle': 'نقطة بيع ومخزون',
      'login': 'تسجيل الدخول',
      'pin': 'رمز الكاشير',
      'adminPassword': 'كلمة مرور المدير',
      'continueAsCashier': 'الدخول ككاشير',
      'continueAsAdmin': 'الدخول كمدير',
      'invalidCredentials': 'بيانات دخول غير صحيحة',
      'pos': 'نقطة البيع',
      'products': 'المنتجات',
      'reports': 'التقارير',
      'settings': 'الإعدادات',
      'searchProducts': 'ابحث بالاسم أو الكود أو الباركود',
      'checkout': 'إتمام البيع',
      'total': 'الإجمالي',
      'paid': 'المدفوع',
      'change': 'الباقي',
      'tax': 'الضريبة',
      'discount': 'الخصم',
      'orderDiscount': 'خصم الطلب',
      'cartEmpty': 'السلة فارغة',
      'addProduct': 'إضافة منتج',
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'stock': 'المخزون',
      'lowStock': 'مخزون منخفض',
      'invoiceHistory': 'سجل الفواتير',
      'dashboard': 'لوحة المؤشرات',
      'exportSalesCsv': 'تصدير مبيعات CSV',
      'exportInventoryCsv': 'تصدير المخزون CSV',
      'sharePdf': 'مشاركة PDF',
      'printReceipt': 'طباعة الفاتورة',
      'newSale': 'بيع جديد',
      'syncNow': 'مزامنة الآن',
      'language': 'اللغة',
      'storeSettings': 'إعدادات المتجر',
      'allowNegativeStock': 'السماح بالمخزون السالب',
      'taxEnabled': 'تفعيل الضريبة',
      'currency': 'العملة',
      'storeName': 'اسم المتجر',
      'receiptHeader': 'عنوان الفاتورة',
      'receiptFooter': 'ذيل الفاتورة',
      'english': 'الإنجليزية',
      'arabic': 'العربية',
      'loading': 'جارٍ التحميل...',
      'empty': 'لا توجد بيانات',
      'error': 'حدث خطأ',
      'retry': 'إعادة المحاولة',
    },
  };

  String tr(String key) => _strings[locale.languageCode]?[key] ?? _strings['en']![key] ?? key;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.any((element) => element.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
