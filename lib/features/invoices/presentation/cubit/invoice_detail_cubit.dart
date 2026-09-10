import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/models/app_models.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../domain/repositories/repositories.dart';

class InvoiceDetailState extends Equatable {
  const InvoiceDetailState({
    this.loading = false,
    this.returning = false,
    this.error,
    this.detail,
    this.returnQtyByItemId = const {},
    this.lastReturnInvoice,
  });

  final bool loading;
  final bool returning;
  final String? error;
  final SaleDetailView? detail;
  final Map<int, int> returnQtyByItemId;
  final String? lastReturnInvoice;

  bool get canReturn {
    final sale = detail?.sale;
    if (sale == null || sale.status != SaleStatus.completed) {
      return false;
    }
    return returnQtyByItemId.values.any((qty) => qty > 0);
  }

  InvoiceDetailState copyWith({
    bool? loading,
    bool? returning,
    String? error,
    bool clearError = false,
    SaleDetailView? detail,
    Map<int, int>? returnQtyByItemId,
    String? lastReturnInvoice,
    bool clearReturnInvoice = false,
  }) {
    return InvoiceDetailState(
      loading: loading ?? this.loading,
      returning: returning ?? this.returning,
      error: clearError ? null : error ?? this.error,
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
        error,
        detail,
        returnQtyByItemId,
        lastReturnInvoice,
      ];
}

class InvoiceDetailCubit extends Cubit<InvoiceDetailState> {
  InvoiceDetailCubit(this._salesRepository) : super(const InvoiceDetailState());

  final SalesRepository _salesRepository;

  Future<void> load(int saleId) async {
    emit(
      state.copyWith(
        loading: true,
        clearError: true,
        clearReturnInvoice: true,
      ),
    );
    try {
      final detail = await _salesRepository.getInvoiceDetail(saleId);
      if (detail == null) {
        emit(state.copyWith(loading: false, error: 'Invoice not found'));
        return;
      }

      final initialMap = <int, int>{
        for (final item in detail.items) item.id: 0,
      };

      emit(
        state.copyWith(
          loading: false,
          detail: detail,
          returnQtyByItemId: initialMap,
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

    final bounded = qty.clamp(0, item.qty.abs()).toInt();
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

    emit(state.copyWith(returning: true, clearError: true));
    try {
      final result =
          await _salesRepository.returnItems(saleId: detail.sale.id, items: payload);
      emit(
        state.copyWith(
          returning: false,
          lastReturnInvoice: result.invoiceNo,
          returnQtyByItemId: {
            for (final item in detail.items) item.id: 0,
          },
        ),
      );
      await load(detail.sale.id);
    } on AppException catch (e) {
      emit(state.copyWith(returning: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(returning: false, error: e.toString()));
    }
  }
}
