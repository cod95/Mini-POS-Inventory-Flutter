import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/models/app_models.dart';
import '../../../../domain/entities/app_entities.dart';
import '../../../../domain/repositories/repositories.dart';

class ProductsState extends Equatable {
  const ProductsState({
    this.loading = false,
    this.error,
    this.products = const [],
    this.filteredProducts = const [],
    this.categories = const [],
    this.filter = const ProductFilter(),
  });

  final bool loading;
  final String? error;
  final List<ProductView> products;
  final List<ProductView> filteredProducts;
  final List<CategoryModel> categories;
  final ProductFilter filter;

  ProductsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<ProductView>? products,
    List<ProductView>? filteredProducts,
    List<CategoryModel>? categories,
    ProductFilter? filter,
  }) {
    return ProductsState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      products: products ?? this.products,
      filteredProducts: filteredProducts ?? this.filteredProducts,
      categories: categories ?? this.categories,
      filter: filter ?? this.filter,
    );
  }

  @override
  List<Object?> get props => [loading, error, products, filteredProducts, categories, filter];
}

class ProductsCubit extends Cubit<ProductsState> {
  ProductsCubit(this._productRepository) : super(const ProductsState());

  final ProductRepository _productRepository;

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final categories = await _productRepository.getCategories();
      final products = await _productRepository.getProducts(filter: state.filter);
      emit(
        state.copyWith(
          loading: false,
          categories: categories,
          products: products,
          filteredProducts: products,
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> applyFilter({String? search, int? categoryId, bool? lowStockOnly}) async {
    final filter = state.filter.copyWith(
      search: search,
      categoryId: categoryId,
      lowStockOnly: lowStockOnly,
      clearCategory: categoryId == -1,
    );
    emit(state.copyWith(filter: filter));
    await load();
  }

  Future<void> saveProduct(ProductUpsertInput input) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _productRepository.upsertProduct(input);
      await load();
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> deleteProduct(int id) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _productRepository.deleteProduct(id);
      await load();
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  Future<void> saveCategory(String name) async {
    if (name.trim().isEmpty) return;
    await _productRepository.addCategory(name.trim());
    await load();
  }

  Future<void> applyStockMovement(StockMovementInput input) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _productRepository.addStockMovement(input);
      await load();
    } on AppException catch (e) {
      emit(state.copyWith(loading: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }
}
