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
