import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/license/license_service.dart';
import 'license_widgets.dart';

/// Shown instead of the app while there is no valid licence on this device.
class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final _master = TextEditingController();
  Duration _duration = const Duration(days: 7);
  String? _masterError;
  bool _busy = false;

  @override
  void dispose() {
    _master.dispose();
    super.dispose();
  }

  Future<void> _masterUnlock(LicenseService service, bool ar) async {
    setState(() {
      _busy = true;
      _masterError = null;
    });
    try {
      final ok = await service.masterUnlock(_master.text, _duration);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (!ok) _masterError = ar ? 'كلمة المرور غير صحيحة.' : 'Wrong password.';
      });
    } on LoginLockedException catch (e) {
      if (!mounted) return;
      final minutes = (e.seconds / 60).ceil();
      setState(() {
        _busy = false;
        _masterError = ar
            ? 'محاولات خاطئة كثيرة. أعد المحاولة بعد $minutes دقيقة.'
            : 'Too many attempts. Try again in $minutes min.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final service = AppScope.of(context).licenseService;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final state = service.info.state;
        final title = switch (state) {
          LicenseState.expired => ar ? 'انتهت صلاحية الترخيص' : 'The licence has expired',
          LicenseState.clockTampered =>
            ar ? 'تم اكتشاف تغيير في تاريخ الجهاز' : 'A change of the device date was detected',
          LicenseState.wrongDevice =>
            ar ? 'هذا الترخيص مخصّص لجهاز آخر' : 'This licence belongs to another device',
          _ => ar ? 'التطبيق غير مفعّل' : 'The app is not activated',
        };
        final hint = state == LicenseState.clockTampered
            ? (ar
                ? 'أعد ضبط تاريخ الجهاز وساعته إلى الوقت الصحيح ثم أعد فتح التطبيق، أو تواصل مع المطوّر.'
                : 'Set the date and time of the device correctly and reopen the app, or contact the developer.')
            : (ar
                ? 'أرسل رقم هذا الجهاز إلى المطوّر للحصول على رمز التفعيل ثم أدخله أدناه.'
                : 'Send this device number to the developer to get an activation code, then enter it below.');

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  shrinkWrap: true,
                  children: [
                    Icon(Icons.lock_outline, size: 56, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(hint, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.lg),
                    DeviceIdCard(deviceId: service.deviceId, ar: ar),
                    const SizedBox(height: AppSpacing.md),
                    ActivationForm(service: service, ar: ar),
                    const SizedBox(height: AppSpacing.lg),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ar ? 'للحصول على ترخيص' : 'To get a licence',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                'Mohammad Al-Qaseer\nWhatsApp: +961 70 955 864\nmohammedqassir24@gmail.com',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ExpansionTile(
                      title: Text(ar ? 'دخول المطوّر' : 'Developer access'),
                      childrenPadding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        TextField(
                          controller: _master,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: ar ? 'كلمة مرور المطوّر' : 'Developer password',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        DropdownButtonFormField<Duration>(
                          value: _duration,
                          decoration: InputDecoration(labelText: ar ? 'مدة الفتح' : 'Open for'),
                          items: [
                            DropdownMenuItem(
                                value: const Duration(days: 1), child: Text(ar ? 'يوم واحد' : '1 day')),
                            DropdownMenuItem(
                                value: const Duration(days: 7), child: Text(ar ? '7 أيام' : '7 days')),
                            DropdownMenuItem(
                                value: const Duration(days: 30), child: Text(ar ? '30 يوماً' : '30 days')),
                            DropdownMenuItem(
                                value: const Duration(days: 365), child: Text(ar ? 'سنة' : '1 year')),
                          ],
                          onChanged: (v) => setState(() => _duration = v ?? _duration),
                        ),
                        if (_masterError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Text(_masterError!,
                                style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        FilledButton(
                          onPressed: _busy ? null : () => _masterUnlock(service, ar),
                          child: Text(ar ? 'فتح التطبيق' : 'Open the app'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
