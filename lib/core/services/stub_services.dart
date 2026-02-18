import '../../domain/repositories/repositories.dart';

class FakeSyncService implements SyncService {
  @override
  Future<void> syncNow() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
}

class StubPrinterService implements PrinterService {
  @override
  Future<void> printReceiptPdfBytes(List<int> bytes) async {
    // Stub for future ESC/POS Bluetooth implementation.
  }
}
