import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/license/license_service.dart';

/// Device number with a copy button.
class DeviceIdCard extends StatelessWidget {
  const DeviceIdCard({super.key, required this.deviceId, required this.ar});

  final String deviceId;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.smartphone),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ar ? 'رقم هذا الجهاز' : 'This device number',
                      style: Theme.of(context).textTheme.bodySmall),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      deviceId,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(letterSpacing: 1.5, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: ar ? 'نسخ' : 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: deviceId)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Field + button to enter a licence code.
class ActivationForm extends StatefulWidget {
  const ActivationForm({super.key, required this.service, required this.ar, this.onDone});

  final LicenseService service;
  final bool ar;
  final VoidCallback? onDone;

  @override
  State<ActivationForm> createState() => _ActivationFormState();
}

class _ActivationFormState extends State<ActivationForm> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final ar = widget.ar;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.service.activate(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case ActivationResult.ok:
          _error = null;
          _controller.clear();
          widget.onDone?.call();
        case ActivationResult.invalid:
          _error = ar ? 'رمز التفعيل غير صحيح.' : 'The activation code is not valid.';
        case ActivationResult.wrongDevice:
          _error = ar
              ? 'رمز التفعيل هذا مخصّص لجهاز آخر.'
              : 'This activation code belongs to another device.';
        case ActivationResult.expired:
          _error = ar ? 'رمز التفعيل منتهي الصلاحية.' : 'This activation code has expired.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: ar ? 'رمز التفعيل' : 'Activation code',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _activate,
          icon: const Icon(Icons.verified_outlined),
          label: Text(ar ? 'تفعيل' : 'Activate'),
        ),
      ],
    );
  }
}

/// Shown in place of a feature that needs the full licence.
class TrialLockedBody extends StatelessWidget {
  const TrialLockedBody({super.key, required this.ar});

  final bool ar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 44),
            const SizedBox(height: AppSpacing.md),
            Text(
              ar
                  ? 'هذه الميزة غير متاحة في النسخة التجريبية.\nللحصول على الترخيص تواصل مع المطوّر.'
                  : 'This feature is not available in the trial version.\nContact the developer to get a licence.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Main phone: the employee phones that hold a seat, with a button to free one.
class SeatsCard extends StatefulWidget {
  const SeatsCard({super.key, required this.service, required this.ar});

  final LicenseService service;
  final bool ar;

  @override
  State<SeatsCard> createState() => _SeatsCardState();
}

class _SeatsCardState extends State<SeatsCard> {
  late Future<List<SeatInfo>> _seats = widget.service.seats();

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _release(SeatInfo seat) async {
    final ar = widget.ar;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'تحرير مكان الجهاز' : 'Free this device place'),
        content: Text(
          ar
              ? 'سيُحرَّر مكان الجهاز ${seat.id} ليتمكن هاتف آخر من الانضمام. يتوقف الجهاز القديم عن العمل بالترخيص عند أول مزامنة له.'
              : 'The place of ${seat.id} will be freed for another phone. The old phone stops using the licence at its next sync.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ar ? 'تحرير' : 'Free')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.service.releaseSeat(seat.id);
    if (!mounted) return;
    setState(() => _seats = widget.service.seats());
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    final total = widget.service.info.devices;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FutureBuilder<List<SeatInfo>>(
          future: _seats,
          builder: (context, snap) {
            final seats = snap.data ?? const <SeatInfo>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ar
                      ? 'الأجهزة: ${seats.length + 1} من $total (هذا الهاتف + هواتف الموظفين)'
                      : 'Devices: ${seats.length + 1} of $total (this phone + employee phones)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (seats.isEmpty)
                  Text(
                    ar
                        ? 'لا توجد هواتف موظفين بعد. أدخل رمز المحل على هاتف الموظف وهو على شبكة الواي فاي نفسها.'
                        : 'No employee phones yet. Enter the shop code on the employee phone while on the same Wi-Fi.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                for (final seat in seats)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.smartphone),
                    title: Text(seat.id),
                    subtitle: Text(ar ? 'آخر اتصال: ${_date(seat.lastSeen)}' : 'Last seen: ${_date(seat.lastSeen)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off),
                      tooltip: ar ? 'تحرير المكان' : 'Free the place',
                      onPressed: () => _release(seat),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
