import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/services/receipt_pdf_service.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../domain/repositories/repositories.dart';

class InvoiceDetailState extends Equatable {
  const InvoiceDetailState({
    this.loading = false,
    this.returning = false,
    this.working = false,
    this.error,
    this.info,
    this.detail,
    this.returnQtyByItemId = const {},
    this.lastReturnInvoice,
  });

  final bool loading;
  final bool returning;

  /// True while a receipt is being generated or an invoice is being cancelled.
  final bool working;
  final String? error;
  final String? info;
  final SaleDetailView? detail;
  final Map<int, int> returnQtyByItemId;
  final String? lastReturnInvoice;

  /// Only real invoices that are still (partly) open can be returned.
  bool get isReturnable {
    final sale = detail?.sale;
    if (sale == null || sale.isReturnDocument) return false;
    return sale.status == SaleStatus.completed || sale.status == SaleStatus.partiallyReturned;
  }

  /// Only an untouched invoice can be cancelled.
  bool get isCancellable {
    final sale = detail?.sale;
    if (sale == null || sale.isReturnDocument) return false;
    return sale.status == SaleStatus.completed;
  }

  bool get canReturn {
    if (!isReturnable) return false;
    return returnQtyByItemId.values.any((qty) => qty > 0);
  }

  InvoiceDetailState copyWith({
    bool? loading,
    bool? returning,
    bool? working,
    String? error,
    bool clearError = false,
    String? info,
    bool clearInfo = false,
    SaleDetailView? detail,
    Map<int, int>? returnQtyByItemId,
    String? lastReturnInvoice,
    bool clearReturnInvoice = false,
  }) {
    return InvoiceDetailState(
      loading: loading ?? this.loading,
      returning: returning ?? this.returning,
      working: working ?? this.working,
      error: clearError ? null : error ?? this.error,
      info: clearInfo ? null : info ?? this.info,
      detail: detail ?? this.detail,
      returnQtyByItemId: returnQtyByItemId ?? this.returnQtyByItemId,
      lastReturnInvoice:
          clearReturnInvoice ? null : lastReturnInvoice ?? this.lastReturnInvoice,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        returning,
        working,
        error,
        info,
        detail,
        returnQtyByItemId,
        lastReturnInvoice,
      ];
}

class InvoiceDetailCubit extends Cubit<InvoiceDetailState> {
  InvoiceDetailCubit(
    this._salesRepository,
    this._settingsRepository,
    this._receiptPdfService,
  ) : super(const InvoiceDetailState());

  final SalesRepository _salesRepository;
  final SettingsRepository _settingsRepository;
  final ReceiptPdfService _receiptPdfService;

  Future<void> load(int saleId) async {
    emit(
      state.copyWith(
        loading: true,
        clearError: true,
        clearInfo: true,
        clearReturnInvoice: true,
      ),
    );
    try {
      final detail = await _salesRepository.getInvoiceDetail(saleId);
      if (detail == null) {
        emit(state.copyWith(loading: false, error: 'Invoice not found'));
        return;
      }

      emit(
        state.copyWith(
          loading: false,
          detail: detail,
          returnQtyByItemId: {for (final item in detail.items) item.id: 0},
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void setReturnQty(int saleItemId, int qty) {
    final detail = state.detail;
    if (detail == null) return;

    final item = detail.items.where((x) => x.id == saleItemId).firstOrNull;
    if (item == null) return;

    final bounded = qty.clamp(0, detail.returnableQty(item).clamp(0, item.qty)).toInt();
    final map = Map<int, int>.from(state.returnQtyByItemId)..[saleItemId] = bounded;
    emit(state.copyWith(returnQtyByItemId: map, clearError: true, clearReturnInvoice: true));
  }

  Future<void> submitReturn() async {
    final detail = state.detail;
    if (detail == null || !state.canReturn) {
      return;
    }

    final payload = state.returnQtyByItemId.entries
        .where((entry) => entry.value > 0)
        .map((entry) => ReturnItemInput(saleItemId: entry.key, qty: entry.value))
        .toList();

    if (payload.isEmpty) {
      return;
    }

    emit(state.copyWith(returning: true, clearError: true, clearInfo: true));
    try {
      final result =
          await _salesRepository.returnItems(saleId: detail.sale.id, items: payload);
      await load(detail.sale.id);
      emit(state.copyWith(returning: false, lastReturnInvoice: result.invoiceNo));
    } on AppException catch (e) {
      emit(state.copyWith(returning: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(returning: false, error: e.toString()));
    }
  }

  /// Cancels (voids) an untouched invoice and puts its items back in stock.
  Future<void> cancelInvoice() async {
    final detail = state.detail;
    if (detail == null || !state.isCancellable) return;

    emit(state.copyWith(working: true, clearError: true, clearInfo: true));
    try {
      await _salesRepository.cancelSale(detail.sale.id);
      await load(detail.sale.id);
      emit(state.copyWith(working: false, info: 'cancelled'));
    } on AppException catch (e) {
      emit(state.copyWith(working: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(working: false, error: e.toString()));
    }
  }

  /// Builds the PDF of this invoice (or return document) and then either
  /// opens the share sheet (WhatsApp, email…) or the print dialog.
  Future<void> sendReceipt({required bool share}) async {
    final detail = state.detail;
    if (detail == null) return;

    emit(state.copyWith(working: true, clearError: true, clearInfo: true));
    try {
      final settings = await _settingsRepository.getSettings();
      final file = await _receiptPdfService.generateReceipt(
        sale: detail.sale,
        items: detail.items,
        storeName: settings.storeName,
        storePhone: settings.storePhone,
        header: settings.receiptHeader,
        footer: settings.receiptFooter,
        currency: settings.currency,
        // Use the rate the invoice was made with, not today's rate.
        exchangeRate: detail.sale.exchangeRateAtSale,
        taxEnabled: settings.taxEnabled,
        languageCode: settings.language,
      );
      if (share) {
        await _receiptPdfService.sharePdf(file);
      } else {
        await _receiptPdfService.printPdf(file);
      }
      emit(state.copyWith(working: false));
    } on AppException catch (e) {
      emit(state.copyWith(working: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(working: false, error: e.toString()));
    }
  }
}
