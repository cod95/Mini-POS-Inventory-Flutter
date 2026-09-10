import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/services/receipt_pdf_service.dart';
import '../../../../core/utils/money_calculator.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../domain/repositories/repositories.dart';

class PosState extends Equatable {
  const PosState({
    this.loading = false,
    this.error,
    this.products = const [],
    this.filteredProducts = const [],
    this.popularProducts = const [],
    this.cart = const [],
    this.categories = const [],
    this.customers = const [],
    this.filter = const ProductFilter(),
    this.selectedCustomerId,
    this.paymentMethod = PaymentMethod.cash,
    this.orderDiscount = 0,
    this.taxEnabled = false,
    this.taxRate = 0.14,
    this.paid = 0,
    this.lastResult,
    this.receiptProcessing = false,
    this.infoMessage,
  });

  final bool loading;
  final String? error;
  final List<ProductView> products;
  final List<ProductView> filteredProducts;
  final List<ProductView> popularProducts;
  final List<CartItem> cart;
  final List<CategoryModel> categories;
  final List<CustomerModel> customers;
  final ProductFilter filter;
  final int? selectedCustomerId;
  final PaymentMethod paymentMethod;
  final double orderDiscount;
  final bool taxEnabled;
  final double taxRate;
  final double paid;
  final SaleCheckoutResult? lastResult;
  final bool receiptProcessing;
  final String? infoMessage;

  double get subtotal {
    final totals = cart
        .map((item) => MoneyCalculator.lineTotal(
              unitPrice: item.price,
              qty: item.qty,
              itemDiscount: item.discount,
            ))
        .toList();
    return MoneyCalculator.subtotal(totals);
  }

  double get tax => MoneyCalculator.tax(
        taxableAmount: max(0, subtotal - orderDiscount),
        taxEnabled: taxEnabled,
        taxRate: taxRate,
      );

  double get total =>
      MoneyCalculator.orderTotal(subtotal: subtotal, orderDiscount: orderDiscount, tax: tax);

  double get change => MoneyCalculator.round2(max(0, paid - total));

  PosState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<ProductView>? products,
    List<ProductView>? filteredProducts,
    List<ProductView>? popularProducts,
    List<CartItem>? cart,
    List<CategoryModel>? categories,
    List<CustomerModel>? customers,
    ProductFilter? filter,
    int? selectedCustomerId,
    bool clearCustomer = false,
    PaymentMethod? paymentMethod,
    double? orderDiscount,
    bool? taxEnabled,
    double? taxRate,
    double? paid,
    SaleCheckoutResult? lastResult,
    bool clearLastResult = false,
    bool? receiptProcessing,
    String? infoMessage,
    bool clearInfoMessage = false,
  }) {
    return PosState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      products: products ?? this.products,
      filteredProducts: filteredProducts ?? this.filteredProducts,
      popularProducts: popularProducts ?? this.popularProducts,
      cart: cart ?? this.cart,
      categories: categories ?? this.categories,
      customers: customers ?? this.customers,
      filter: filter ?? this.filter,
      selectedCustomerId: clearCustomer ? null : selectedCustomerId ?? this.selectedCustomerId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      orderDiscount: orderDiscount ?? this.orderDiscount,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      taxRate: taxRate ?? this.taxRate,
      paid: paid ?? this.paid,
      lastResult: clearLastResult ? null : lastResult ?? this.lastResult,
      receiptProcessing: receiptProcessing ?? this.receiptProcessing,
      infoMessage: clearInfoMessage ? null : infoMessage ?? this.infoMessage,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        error,
        products,
        filteredProducts,
        popularProducts,
        cart,
        categories,
        customers,
        filter,
        selectedCustomerId,
        paymentMethod,
        orderDiscount,
        taxEnabled,
        taxRate,
        paid,
        lastResult,
        receiptProcessing,
        infoMessage,
      ];
}

class PosCubit extends Cubit<PosState> {
  PosCubit({
    required ProductRepository productRepository,
    required SalesRepository salesRepository,
    required SettingsRepository settingsRepository,
    required PartyRepository partyRepository,
    required BarcodeScannerService scannerService,
    required ReceiptPdfService receiptPdfService,
  })  : _productRepository = productRepository,
        _salesRepository = salesRepository,
        _settingsRepository = settingsRepository,
        _partyRepository = partyRepository,
        _scannerService = scannerService,
        _receiptPdfService = receiptPdfService,
        super(const PosState());

  final ProductRepository _productRepository;
  final SalesRepository _salesRepository;
  final SettingsRepository _settingsRepository;
  final PartyRepository _partyRepository;
  final BarcodeScannerService _scannerService;
  final ReceiptPdfService _receiptPdfService;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final settings = await _settingsRepository.getSettings();
      final categories = await _productRepository.getCategories();
      final products = await _productRepository.getProducts();
      final popular = await _productRepository.getPopularProducts();
      final customers = await _partyRepository.getCustomers();

      emit(
        state.copyWith(
          loading: false,
          categories: categories,
          products: products,
          filteredProducts: products,
          popularProducts: popular,
          customers: customers,
          taxEnabled: settings.taxEnabled,
          taxRate: settings.taxRate,
          paid: state.total,
          selectedCustomerId: customers.isNotEmpty ? customers.first.id : null,
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> scanAndAdd() async {
    final code = await _scannerService.scanBarcode();
    if (code == null || code.isEmpty) return;
    final product = await _productRepository.findByBarcode(code);
    if (product == null) {
      emit(state.copyWith(error: 'Product not found', clearLastResult: true));
      return;
    }
    addProductToCart(product);
  }

  void updateFilter({String? search, int? categoryId, bool? lowStockOnly}) {
    final filter = state.filter.copyWith(
      search: search,
      categoryId: categoryId,
      lowStockOnly: lowStockOnly,
      clearCategory: categoryId == -1,
    );
    final searchLower = filter.search.trim().toLowerCase();
    final filtered = state.products.where((p) {
      final matchSearch = searchLower.isEmpty ||
          p.name.toLowerCase().contains(searchLower) ||
          p.sku.toLowerCase().contains(searchLower) ||
          (p.barcode?.contains(searchLower) ?? false);
      final matchCategory = filter.categoryId == null || p.categoryId == filter.categoryId;
      final matchLow = !filter.lowStockOnly || p.isLowStock;
      return matchSearch && matchCategory && matchLow;
    }).toList();

    emit(state.copyWith(filter: filter, filteredProducts: filtered));
  }

  void addProductToCart(ProductView product) {
    final existingIndex = state.cart.indexWhere((item) => item.productId == product.id);
    final updated = [...state.cart];

    if (existingIndex == -1) {
      updated.add(
        CartItem(
          productId: product.id,
          name: product.name,
          sku: product.sku,
          barcode: product.barcode,
          cost: product.cost,
          price: product.price,
          qty: 1,
        ),
      );
    } else {
      final item = updated[existingIndex];
      updated[existingIndex] = item.copyWith(qty: item.qty + 1);
    }

    emit(state.copyWith(cart: updated, paid: state.total, clearError: true, clearLastResult: true));
  }

  void updateItemQty(int productId, int qty) {
    final updated = [...state.cart];
    final index = updated.indexWhere((item) => item.productId == productId);
    if (index == -1) return;

    if (qty <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(qty: qty);
    }
    emit(state.copyWith(cart: updated, paid: state.total));
  }

  void removeFromCart(int productId) {
    final updated = state.cart.where((item) => item.productId != productId).toList();
    emit(state.copyWith(cart: updated, paid: state.total));
  }

  void setItemDiscount(int productId, double discount) {
    final updated = [...state.cart];
    final index = updated.indexWhere((item) => item.productId == productId);
    if (index == -1) return;
    final item = updated[index];
    updated[index] = item.copyWith(discount: max(0, discount));
    emit(state.copyWith(cart: updated));
  }

  void setItemPrice(int productId, double price) {
    final updated = [...state.cart];
    final index = updated.indexWhere((item) => item.productId == productId);
    if (index == -1) return;
    final item = updated[index];
    updated[index] = item.copyWith(price: max(0, price));
    emit(state.copyWith(cart: updated));
  }

  void setOrderDiscount(double value) => emit(state.copyWith(orderDiscount: max(0, value)));

  void setPaymentMethod(PaymentMethod method) => emit(state.copyWith(paymentMethod: method));

  void setPaid(double value) => emit(state.copyWith(paid: max(0, value)));

  void selectCustomer(int? id) => emit(state.copyWith(selectedCustomerId: id, clearCustomer: id == null));

  Future<void> checkout() async {
    if (state.cart.isEmpty) {
      emit(state.copyWith(error: 'Cart is empty'));
      return;
    }
    emit(state.copyWith(loading: true, clearError: true));

    try {
      final result = await _salesRepository.checkout(
        SaleCheckoutInput(
          items: state.cart,
          orderDiscount: state.orderDiscount,
          taxEnabled: state.taxEnabled,
          taxRate: state.taxRate,
          paid: state.paid,
          paymentMethod: state.paymentMethod,
          customerId: state.selectedCustomerId,
        ),
      );

      emit(
        state.copyWith(
          loading: false,
          lastResult: result,
          cart: const [],
          orderDiscount: 0,
          paid: 0,
          infoMessage: 'Sale completed: ${result.invoiceNo}',
        ),
      );

      await load();
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void newSale() {
    emit(
      state.copyWith(
        cart: const [],
        orderDiscount: 0,
        paid: 0,
        clearLastResult: true,
        clearError: true,
        clearInfoMessage: true,
      ),
    );
  }

  Future<void> shareLastReceipt() async {
    await _handleReceiptAction(share: true);
  }

  Future<void> printLastReceipt() async {
    await _handleReceiptAction(share: false);
  }

  Future<void> _handleReceiptAction({required bool share}) async {
    final checkout = state.lastResult;
    if (checkout == null) {
      emit(state.copyWith(error: 'No recent sale to generate receipt for'));
      return;
    }

    emit(state.copyWith(receiptProcessing: true, clearError: true, clearInfoMessage: true));
    try {
      final detail = await _salesRepository.getInvoiceDetail(checkout.saleId);
      if (detail == null) {
        throw AppException('Invoice details not found');
      }
      final settings = await _settingsRepository.getSettings();
      final file = await _receiptPdfService.generateReceipt(
        sale: detail.sale,
        items: detail.items,
        storeName: settings.storeName,
        header: settings.receiptHeader,
        footer: settings.receiptFooter,
        currency: settings.currency,
      );
      if (share) {
        await _receiptPdfService.sharePdf(file);
      } else {
        await _receiptPdfService.printPdf(file);
      }

      emit(
        state.copyWith(
          receiptProcessing: false,
          infoMessage: share ? 'Receipt shared' : 'Receipt sent to printer',
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(receiptProcessing: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(receiptProcessing: false, error: e.toString()));
    }
  }
}
