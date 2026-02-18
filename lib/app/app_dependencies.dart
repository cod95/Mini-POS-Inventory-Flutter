import 'package:flutter/material.dart';

import '../core/services/barcode_scanner_service_impl.dart';
import '../core/services/file_export_service.dart';
import '../core/services/receipt_pdf_service.dart';
import '../core/services/stub_services.dart';
import '../core/state/app_cubit.dart';
import '../data/local/db/app_database.dart';
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

  final AppCubit appCubit;

  static Future<AppDependencies> create() async {
    final rootNavigatorKey = GlobalKey<NavigatorState>();
    final db = AppDatabase();
    await SeedData(db).ensureSeeded();

    final settingsRepository = LocalSettingsRepository(db);
    final productRepository = LocalProductRepository(db);
    final authRepository = LocalAuthRepository(db);
    final salesRepository = LocalSalesRepository(db);
    final partyRepository = LocalPartyRepository(db);
    final reportsRepository = LocalReportsRepository(db, productRepository);

    final barcodeScannerService = RouteBarcodeScannerService(rootNavigatorKey);
    final fileExportService = FileExportService();
    final printerService = StubPrinterService();
    final receiptPdfService = ReceiptPdfService(printerService: printerService);
    final syncService = FakeSyncService();

    final appCubit = AppCubit(
      authRepository: authRepository,
      settingsRepository: settingsRepository,
    )..initialize();

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
      appCubit: appCubit,
    );
  }

  Future<void> dispose() async {
    await appCubit.close();
    await database.close();
  }
}
