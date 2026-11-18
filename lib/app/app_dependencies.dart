import 'package:flutter/material.dart';

import '../core/license/license_service.dart';
import '../core/services/barcode_scanner_service_impl.dart';
import '../core/services/bluetooth_printer_service.dart';
import '../core/services/file_export_service.dart';
import '../core/services/receipt_pdf_service.dart';
import '../core/services/stub_services.dart';
import '../core/state/app_cubit.dart';
import '../data/local/db/app_database.dart';
import '../data/backup/backup_service.dart';
import '../data/sync/file_sync_service.dart';
import '../data/sync/lan_sync_service.dart';
import '../data/local/seed/seed_data.dart';
import '../data/repositories/local_repositories.dart';
import '../domain/repositories/repositories.dart';

class AppDependencies {
  AppDependencies._({
    required this.rootNavigatorKey,
    required this.database,
    required this.authRepository,
    required this.settingsRepository,
    required this.productRepository,
    required this.salesRepository,
    required this.reportsRepository,
    required this.partyRepository,
    required this.syncService,
    required this.printerService,
    required this.barcodeScannerService,
    required this.fileExportService,
    required this.receiptPdfService,
    required this.bluetoothPrinterService,
    required this.fileSyncService,
    required this.lanSyncService,
    required this.backupService,
    required this.licenseService,
    required this.appCubit,
  });

  final GlobalKey<NavigatorState> rootNavigatorKey;
  final AppDatabase database;

  final AuthRepository authRepository;
  final SettingsRepository settingsRepository;
  final ProductRepository productRepository;
  final SalesRepository salesRepository;
  final ReportsRepository reportsRepository;
  final PartyRepository partyRepository;

  final SyncService syncService;
  final PrinterService printerService;
  final BarcodeScannerService barcodeScannerService;
  final FileExportService fileExportService;
  final ReceiptPdfService receiptPdfService;
  final BluetoothPrinterService bluetoothPrinterService;

  final FileSyncService fileSyncService;
  final LanSyncService lanSyncService;
  final BackupService backupService;
  final LicenseService licenseService;

  final AppCubit appCubit;

  static Future<AppDependencies> create() async {
    final rootNavigatorKey = GlobalKey<NavigatorState>();
    final db = AppDatabase();
    await SeedData(db).ensureSeeded();

    final settingsRepository = LocalSettingsRepository(db);
    final licenseService = LicenseService();
    await licenseService.init();

    final productRepository = LocalProductRepository(db, licenseService);
    final authRepository = LocalAuthRepository(db, licenseService);
    final salesRepository = LocalSalesRepository(db, licenseService);
    final partyRepository = LocalPartyRepository(db);
    final reportsRepository = LocalReportsRepository(db, productRepository);

    final barcodeScannerService = RouteBarcodeScannerService(rootNavigatorKey);
    final fileExportService = FileExportService();
    final printerService = StubPrinterService();
    final receiptPdfService = ReceiptPdfService(printerService: printerService);
    final bluetoothPrinterService = BluetoothPrinterService();
    final syncService = FakeSyncService();
    final fileSyncService = FileSyncService(db);
    final lanSyncService = LanSyncService(db, fileSyncService);
    final backupService = BackupService(db);
    final appCubit = AppCubit(
      authRepository: authRepository,
      settingsRepository: settingsRepository,
    )..initialize();

    // Prices, users and store settings may arrive from the main phone.
    lanSyncService.dataVersion.addListener(() => appCubit.refreshSettings());
    lanSyncService.start();

    return AppDependencies._(
      rootNavigatorKey: rootNavigatorKey,
      database: db,
      authRepository: authRepository,
      settingsRepository: settingsRepository,
      productRepository: productRepository,
      salesRepository: salesRepository,
      reportsRepository: reportsRepository,
      partyRepository: partyRepository,
      syncService: syncService,
      printerService: printerService,
      barcodeScannerService: barcodeScannerService,
      fileExportService: fileExportService,
      receiptPdfService: receiptPdfService,
      bluetoothPrinterService: bluetoothPrinterService,
      fileSyncService: fileSyncService,
      lanSyncService: lanSyncService,
      backupService: backupService,
      licenseService: licenseService,
      appCubit: appCubit,
    );
  }

  Future<void> dispose() async {
    licenseService.dispose();
    await lanSyncService.stop();
    await appCubit.close();
    await database.close();
  }
}
