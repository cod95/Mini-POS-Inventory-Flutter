import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/services/file_export_service.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../domain/repositories/repositories.dart';

class ReportsState extends Equatable {
  const ReportsState({
    this.loading = false,
    this.error,
    this.dashboard = DashboardMetrics.empty,
    this.invoices = const [],
    this.salesByProduct = const [],
    this.lowStockProducts = const [],
    this.from,
    this.to,
    this.lastExport,
  });

  final bool loading;
  final String? error;
  final DashboardMetrics dashboard;
  final List<SaleSummary> invoices;
  final List<SalesByProductMetric> salesByProduct;
  final List<ProductView> lowStockProducts;
  final DateTime? from;
  final DateTime? to;
  final File? lastExport;

  ReportsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    DashboardMetrics? dashboard,
    List<SaleSummary>? invoices,
    List<SalesByProductMetric>? salesByProduct,
    List<ProductView>? lowStockProducts,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    File? lastExport,
  }) {
    return ReportsState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      dashboard: dashboard ?? this.dashboard,
      invoices: invoices ?? this.invoices,
      salesByProduct: salesByProduct ?? this.salesByProduct,
      lowStockProducts: lowStockProducts ?? this.lowStockProducts,
      from: clearDates ? null : from ?? this.from,
      to: clearDates ? null : to ?? this.to,
      lastExport: lastExport ?? this.lastExport,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        error,
        dashboard,
        invoices,
        salesByProduct,
        lowStockProducts,
        from,
        to,
        lastExport,
      ];
}

class ReportsCubit extends Cubit<ReportsState> {
  ReportsCubit({
    required ReportsRepository reportsRepository,
    required SalesRepository salesRepository,
    required FileExportService exportService,
  })  : _reportsRepository = reportsRepository,
        _salesRepository = salesRepository,
        _exportService = exportService,
        super(const ReportsState());

  final ReportsRepository _reportsRepository;
  final SalesRepository _salesRepository;
  final FileExportService _exportService;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final dashboard = await _reportsRepository.getDashboardMetrics();
      final salesByProduct =
          await _reportsRepository.salesByProduct(from: state.from, to: state.to);
      final lowStock = await _reportsRepository.lowStockProducts();
      final invoices = await _salesRepository.getInvoices(
        filter: InvoiceFilter(from: state.from, to: state.to),
      );

      emit(
        state.copyWith(
          loading: false,
          dashboard: dashboard,
          invoices: invoices,
          salesByProduct: salesByProduct,
          lowStockProducts: lowStock,
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> setRange(DateTime? from, DateTime? to) async {
    emit(state.copyWith(from: from, to: to));
    await load();
  }

  Future<void> exportSalesCsv() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final rows = await _reportsRepository.salesReportRows(from: state.from, to: state.to);
      final file = await _exportService.exportSalesCsv(rows);
      await _exportService.shareFile(file);
      emit(state.copyWith(loading: false, lastExport: file));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> exportInventoryCsv() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final rows = await _reportsRepository.inventoryReportRows();
      final file = await _exportService.exportInventoryCsv(rows);
      await _exportService.shareFile(file);
      emit(state.copyWith(loading: false, lastExport: file));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }
}
