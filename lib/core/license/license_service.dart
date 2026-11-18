import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_exception.dart';
import '../security/secret_hasher.dart';
import 'license_config.dart';
import 'license_gate.dart';
import 'license_verifier.dart';

enum LicenseState { ok, notActivated, expired, clockTampered, wrongDevice }

enum ActivationResult { ok, invalid, wrongDevice, expired }

class LicenseInfo {
  const LicenseInfo({
    this.state = LicenseState.ok,
    this.customer,
    this.expiry,
    this.masterUntil,
  });

  final LicenseState state;
  final String? customer;
  final DateTime? expiry;

  /// Set while the developer's master password is keeping the app open.
  final DateTime? masterUntil;
}

/// Ties each installation to one device and to a licence code signed by the
/// developer. Without a valid code (or the developer's master password) the
/// app runs as a limited trial, so a copied app cannot be used or resold.
class LicenseService extends ChangeNotifier implements LicenseGate {
  LicenseService();

  static const String _kToken = 'qs_license_token';
  static const String _kSeen = 'qs_last_seen';
  static const String _kGrant = 'qs_master_grant';
  static const String _kFail = 'qs_master_fail';
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String deviceId = '';
  LicenseInfo info = const LicenseInfo();
  Timer? _timer;

  bool get enforced => LicenseConfig.configured;

  /// Full licence (or licensing switched off): every feature works.
  @override
  bool get full => !enforced || info.state == LicenseState.ok;

  /// Only a tampered clock locks the app completely; without a valid licence
  /// the app runs as a limited trial.
  bool get isOpen => !enforced || info.state != LicenseState.clockTampered;

  Future<void> init() async {
    deviceId = await _loadOrCreateDeviceId();
    await check();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => check());
  }

  // ---------------------------------------------------------------- storage

  Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, name));
  }

  Future<String?> _read(String key, String fileName) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    try {
      final f = await _file(fileName);
      if (f.existsSync()) {
        final v = (await f.readAsString()).trim();
        if (v.isNotEmpty) return v;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _write(String key, String fileName, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
    try {
      await (await _file(fileName)).writeAsString(value, flush: true);
    } catch (_) {}
  }

  Future<String> _loadOrCreateDeviceId() async {
    final existing = await _read('qs_device_id', 'qs_device.id');
    if (existing != null && RegExp(r'^QS-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(existing)) {
      // Keep both copies in step.
      await _write('qs_device_id', 'qs_device.id', existing);
      return existing;
    }
    final random = Random.secure();
    String group() => List.generate(4, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
    final id = 'QS-${group()}-${group()}-${group()}';
    await _write('qs_device_id', 'qs_device.id', id);
    return id;
  }

  // ------------------------------------------------------------------ check

  Future<void> check() async {
    final next = await _evaluate();
    final changed = next.state != info.state ||
        next.expiry != info.expiry ||
        next.masterUntil != info.masterUntil ||
        next.customer != info.customer;
    info = next;
    if (changed) notifyListeners();
  }

  Future<LicenseInfo> _evaluate() async {
    if (!enforced) return const LicenseInfo();
    final now = DateTime.now();

    // Clock turned back to stretch a licence?
    final seen = int.tryParse(await _read(_kSeen, 'qs_seen.txt') ?? '');
    var tampered = false;
    if (seen != null && now.millisecondsSinceEpoch < seen - const Duration(days: 1).inMilliseconds) {
      tampered = true;
    } else if (seen == null || now.millisecondsSinceEpoch > seen) {
      await _write(_kSeen, 'qs_seen.txt', '${now.millisecondsSinceEpoch}');
    }

    // Opened by the developer's master password?
    DateTime? masterUntil;
    final grant = await _read(_kGrant, 'qs_grant.txt');
    if (grant != null) {
      final parts = grant.split('|');
      if (parts.length == 2 && parts[1] == deviceId) {
        final until = DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[0]) ?? 0);
        if (until.isAfter(now)) masterUntil = until;
      }
    }

    final token = await _read(_kToken, 'qs_license.key');
    LicensePayload? payload;
    if (token != null) {
      payload = LicenseVerifier.verify(token, LicenseConfig.publicKeyX, LicenseConfig.publicKeyY);
    }
    final customer = payload?.customer;
    final expiry = payload?.expiry;

    if (masterUntil != null && !tampered) {
      return LicenseInfo(customer: customer, expiry: expiry, masterUntil: masterUntil);
    }
    if (tampered) return LicenseInfo(state: LicenseState.clockTampered, customer: customer, expiry: expiry);
    if (payload == null) return const LicenseInfo(state: LicenseState.notActivated);
    if (payload.deviceId != deviceId) {
      return LicenseInfo(state: LicenseState.wrongDevice, customer: customer);
    }
    if (expiry != null && !now.isBefore(DateTime(expiry.year, expiry.month, expiry.day + 1))) {
      return LicenseInfo(state: LicenseState.expired, customer: customer, expiry: expiry);
    }
    return LicenseInfo(customer: customer, expiry: expiry);
  }

  // ------------------------------------------------------------- activation

  Future<ActivationResult> activate(String code) async {
    final payload = LicenseVerifier.verify(code, LicenseConfig.publicKeyX, LicenseConfig.publicKeyY);
    if (payload == null) return ActivationResult.invalid;
    if (payload.deviceId != deviceId) return ActivationResult.wrongDevice;
    final expiry = payload.expiry;
    final now = DateTime.now();
    if (expiry != null && !now.isBefore(DateTime(expiry.year, expiry.month, expiry.day + 1))) {
      return ActivationResult.expired;
    }
    await _write(_kToken, 'qs_license.key', code.trim());
    await check();
    return ActivationResult.ok;
  }

  // ----------------------------------------------------------- master password

  /// Checks the developer's master password. Throws [LoginLockedException]
  /// after repeated wrong attempts.
  Future<bool> verifyMaster(String password) async {
    if (LicenseConfig.masterVerifier.isEmpty) return false;
    final now = DateTime.now();
    final raw = (await _read(_kFail, 'qs_fail.txt'))?.split('|');
    var fails = int.tryParse(raw?.first ?? '') ?? 0;
    final lockedUntil = DateTime.fromMillisecondsSinceEpoch(
      raw != null && raw.length == 2 ? int.tryParse(raw[1]) ?? 0 : 0,
    );
    if (lockedUntil.isAfter(now)) {
      throw LoginLockedException(lockedUntil.difference(now).inSeconds + 1);
    }
    final ok = await SecretHasher.verify(password, LicenseConfig.masterVerifier);
    if (ok) {
      await _write(_kFail, 'qs_fail.txt', '0|0');
      return true;
    }
    fails++;
    var lock = 0;
    if (fails >= 3) {
      lock = now.add(Duration(minutes: min(60, 1 << min(6, fails - 3)))).millisecondsSinceEpoch;
    }
    await _write(_kFail, 'qs_fail.txt', '$fails|$lock');
    if (lock != 0) {
      throw LoginLockedException(DateTime.fromMillisecondsSinceEpoch(lock).difference(now).inSeconds + 1);
    }
    return false;
  }

  /// Opens this device for [duration] with the master password.
  Future<bool> masterUnlock(String password, Duration duration) async {
    if (!await verifyMaster(password)) return false;
    final now = DateTime.now();
    await _write(_kGrant, 'qs_grant.txt', '${now.add(duration).millisecondsSinceEpoch}|$deviceId');
    await _write(_kSeen, 'qs_seen.txt', '${now.millisecondsSinceEpoch}');
    await check();
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
