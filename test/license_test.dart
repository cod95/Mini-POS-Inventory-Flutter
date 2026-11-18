import 'package:flutter_test/flutter_test.dart';
import 'package:mini_pos_inventory/core/license/license_verifier.dart';
import 'package:mini_pos_inventory/core/security/secret_hasher.dart';

// Vector produced by tools/license-tool.html (same code the developer uses).
const _x = '8454c229812eab45dcbd110aabc434d053e71d2f6f824c700d4af7f39c5642f7';
const _y = '4a5a787cb5acfb912230f2bed5acd76100d290c06fb2a453d99f46e339624268';
const _good = 'QS1.eyJ2IjoxLCJkIjoiUVMtVEVTVC0wMDAwLTAwMDEiLCJjIjoiVGVzdCBTaG9wIiwiZSI6IjIwOTktMTItMzEiLCJpIjoiMjAyNi0xMS0xOCJ9.f61X_upVBV4zEFDoYVo0J8WD5G3mw1erk-eeAK7xd9YH2PsdhcAjXQTmSold-4niH_4H2dGJ9iVkHmMGsxhVfw';
const _perpetual = 'QS1.eyJ2IjoxLCJkIjoiUVMtVEVTVC0wMDAwLTAwMDEiLCJjIjoiUGVycCIsImUiOm51bGwsImkiOiIyMDI2LTExLTE4In0.xA3C6V7wDPvr3cv0_wLe-a_OLdnjXH4ieQiFYQ0OzrkEIdd1STxclO8T8fGSTuf7UzyayNj1C-u5Lr32ivq4Cw';
const _expired = 'QS1.eyJ2IjoxLCJkIjoiUVMtVEVTVC0wMDAwLTAwMDEiLCJjIjoiT2xkIiwiZSI6IjIwMjAtMDEtMDEiLCJpIjoiMjAxOS0wMS0wMSJ9.l23QoGvmOQNVH6HiiZHBKm7mwn-lERDLsw9svf92TUgFwFMQ8Al2GeS4cSvodnLNjYL0zCSYz8E9Rk5pt8xNmA';
const _verifier = r'pbkdf2$200000$XqN7ytGt4nUEfZ7iF1kz2A==$P1U9LfYwh2xDuNWWtyO5DXVg+kdpYAKQU+qz5CuK/F8=';

// Second key pair, produced by the same tool, with device counts.
const _x2 = '38346f1f4dc696ca6688aaa432b6c66c8c3c8a5af568b3693581c984e9f57217';
const _y2 = '7b87a9859e45bf74e9f18c36c85663314056a503d744f6beed4552a7fcb28a93';
const _multi = 'QS1.eyJ2IjoxLCJkIjoiUVMtVEVTVC0wMDAwLTAwMDEiLCJjIjoiQ2FmZSBUZXN0IiwibiI6MywiZSI6bnVsbCwiaSI6IjIwMjYtMTEtMTkifQ.dss0MetF6TB-VNsdTIJuhS6k6GwEwvbdhr0unqnflP-8tb3YGobG9Vw8JG5o54QioKcwP3WU6NVlrQPpt-3tMQ';
const _noCount = 'QS1.eyJ2IjoxLCJkIjoiUVMtVEVTVC0wMDAwLTAwMDEiLCJjIjoiT2xkIiwiZSI6bnVsbCwiaSI6IjIwMjYtMTEtMTkifQ.0QiiHrfzbKkirAj6Psb1ioaQz6btisVUIzwpR2tKxK42zZxyByCKaFegdDrUunfdO2hU1f2Fj1CkxKNhvoJNmg';
const _huge = 'QS1.eyJ2IjoxLCJkIjoiUVMtVEVTVC0wMDAwLTAwMDEiLCJjIjoiQmlnIiwibiI6OTk5OTksImUiOm51bGwsImkiOiIyMDI2LTExLTE5In0.ETEzMreBcVZsVsgOqSjcOSuswqLwgXsKW2tCxuK7d0iuCcnrN3cgS4v2WjEk7b8555ea5ARjSxRWoP7LG0RBpA';

void main() {
  test('device count is read, defaults to 1 and is capped', () {
    expect(LicenseVerifier.verify(_multi, _x2, _y2)!.devices, 3);
    expect(LicenseVerifier.verify(_multi, _x2, _y2)!.customer, 'Cafe Test');
    expect(LicenseVerifier.verify(_noCount, _x2, _y2)!.devices, 1);
    expect(LicenseVerifier.verify(_huge, _x2, _y2)!.devices, 500);
    expect(LicenseVerifier.verify(_multi, _x, _y), isNull);
  });

  test('valid licence verifies and exposes its content', () {
    final p = LicenseVerifier.verify(_good, _x, _y);
    expect(p, isNotNull);
    expect(p!.deviceId, 'QS-TEST-0000-0001');
    expect(p.customer, 'Test Shop');
    expect(p.expiry, DateTime.parse('2099-12-31'));
  });

  test('unlimited and expired licences are read correctly', () {
    expect(LicenseVerifier.verify(_perpetual, _x, _y)!.expiry, isNull);
    expect(LicenseVerifier.verify(_expired, _x, _y)!.expiry, DateTime.parse('2020-01-01'));
  });

  test('a changed payload is rejected', () {
    final parts = _good.split('.');
    final forged = '${parts[0]}.${_perpetual.split('.')[1]}.${parts[2]}';
    expect(LicenseVerifier.verify(forged, _x, _y), isNull);
  });

  test('garbage and a wrong key are rejected', () {
    expect(LicenseVerifier.verify('nonsense', _x, _y), isNull);
    expect(LicenseVerifier.verify('QS1.a.b', _x, _y), isNull);
    expect(LicenseVerifier.verify(_good, _y, _x), isNull);
  });

  test('master password verifier from the tool', () async {
    expect(await SecretHasher.verify('test-master-password-123', _verifier), isTrue);
    expect(await SecretHasher.verify('wrong-password', _verifier), isFalse);
  });
}
