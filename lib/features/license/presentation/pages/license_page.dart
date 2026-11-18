import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/license/license_config.dart';
import '../../../../core/license/license_gate.dart';
import '../../../../core/license/license_service.dart';
import 'license_widgets.dart';

/// Admin: licence status of this device and renewal.
class LicensePage extends StatelessWidget {
  const LicensePage({super.key});

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final service = AppScope.of(context).licenseService;

    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'الترخيص' : 'Licence')),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) {
          final info = service.info;
          final String status;
          if (!LicenseConfig.configured) {
            status = ar ? 'نظام الترخيص غير مفعّل في هذه النسخة.' : 'Licensing is not enabled in this build.';
          } else if (info.isSeat) {
            status = ar
                ? 'جهاز موظف يعمل بترخيص المحل عبر هاتف المدير. يتجدد تلقائياً عند كل مزامنة معه، وإن انقطع الاتصال يعمل حتى ${_date(info.leaseUntil!)}.'
                : 'Employee phone working under the shop licence through the admin phone. It renews at every sync, and works without contact until ${_date(info.leaseUntil!)}.';
          } else if (!service.full && info.state != LicenseState.clockTampered) {
            status = ar
                ? 'نسخة تجريبية محدودة (حتى ${LicenseGate.trialMaxProducts} منتجاً و${LicenseGate.trialMaxInvoices} فواتير، دون مستخدمين جدد أو مزامنة أو Excel). أدخل رمز التفعيل لإزالة القيود.'
                : 'Limited trial. Enter an activation code to remove the limits.';
          } else if (info.masterUntil != null) {
            status = ar
                ? 'مفتوح بواسطة المطوّر حتى ${_date(info.masterUntil!)}'
                : 'Opened by the developer until ${_date(info.masterUntil!)}';
          } else if (info.expiry == null) {
            status = ar ? 'ترخيص دائم' : 'Unlimited licence';
          } else {
            status = ar ? 'ساري حتى ${_date(info.expiry!)}' : 'Valid until ${_date(info.expiry!)}';
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(
                    (info.customer ?? '').isEmpty
                        ? (ar ? 'حالة الترخيص' : 'Licence status')
                        : info.customer!,
                  ),
                  subtitle: Text(status),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DeviceIdCard(deviceId: service.deviceId, ar: ar),
              if (service.full && !info.isSeat && info.devices > 1) ...[
                const SizedBox(height: AppSpacing.md),
                SeatsCard(service: service, ar: ar),
              ],
              if (!service.full && service.seatError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  service.seatError == 'FULL'
                      ? (ar
                          ? 'رفض هاتف المدير تفعيل هذا الهاتف لأن عدد الأجهزة المسموح بها اكتمل.'
                          : 'The admin phone refused this phone: the allowed number of devices is reached.')
                      : (ar
                          ? 'هاتف المدير غير مرخّص حالياً.'
                          : 'The admin phone has no valid licence at the moment.'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (LicenseConfig.configured) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  service.full ? (ar ? 'تجديد الترخيص' : 'Renew the licence') : (ar ? 'تفعيل الترخيص' : 'Activate the licence'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                ActivationForm(service: service, ar: ar),
              ],
            ],
          );
        },
      ),
    );
  }
}
