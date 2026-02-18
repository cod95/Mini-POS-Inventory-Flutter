import '../../core/models/app_models.dart';
import '../entities/app_entities.dart';

class SaleCheckoutResult {
  const SaleCheckoutResult({
    required this.saleId,
    required this.invoiceNo,
    required this.total,
    required this.paid,
    required this.change,
  });

  final int saleId;
  final String invoiceNo;
  final double total;
  final double paid;
  final double change;
}

class ReturnResult {
  const ReturnResult({required this.returnSaleId, required this.invoiceNo});

  final int returnSaleId;
  final String invoiceNo;
}

class SalesReportRow {
  const SalesReportRow({
    required this.invoiceNo,
    required this.date,
    required this.total,
    required this.paymentMethod,
    required this.status,
  });

  final String invoiceNo;
  final DateTime date;
  final double total;
  final String paymentMethod;
  final String status;
}

class InventoryReportRow {
  const InventoryReportRow({
    required this.name,
    required this.sku,
    required this.category,
    required this.stock,
    required this.cost,
    required this.price,
    required this.lowStock,
  });

  final String name;
  final String sku;
  final String category;
  final int stock;
  final double cost;
  final double price;
  final bool lowStock;
}

abstract class AuthRepository {
  Future<UserRole?> loginWithPin(String pin);

  Future<UserRole?> loginAsAdmin(String password);

  Future<void> logout();
}

abstract class SettingsRepository {
  Future<AppSettingsModel> getSettings();

  Future<void> updateSettings(AppSettingsModel settings);
}

abstract class ProductRepository {
  Future<List<ProductView>> getProducts({ProductFilter filter = const ProductFilter()});

  Future<List<ProductView>> getPopularProducts();

  Future<ProductView?> getProduct(int id);

  Future<ProductView?> findByBarcode(String barcode);

  Future<int> upsertProduct(ProductUpsertInput input);

  Future<void> deleteProduct(int id);

  Future<List<CategoryModel>> getCategories();

  Future<int> addCategory(String name);

  Future<void> updateCategory(CategoryModel category);

  Future<void> deleteCategory(int id);

  Future<void> addStockMovement(StockMovementInput input);

  Future<List<ProductView>> getLowStockProducts();
}

abstract class SalesRepository {
  Future<SaleCheckoutResult> checkout(SaleCheckoutInput input);

  Future<List<SaleSummary>> getInvoices({InvoiceFilter filter = const InvoiceFilter()});

  Future<SaleDetailView?> getInvoiceDetail(int saleId);

  Future<ReturnResult> returnItems({
    required int saleId,
    required List<ReturnItemInput> items,
  });
}

abstract class ReportsRepository {
  Future<DashboardMetrics> getDashboardMetrics();

  Future<List<SalesByProductMetric>> salesByProduct({DateTime? from, DateTime? to});

  Future<List<ProductView>> lowStockProducts();

  Future<List<SalesReportRow>> salesReportRows({DateTime? from, DateTime? to});

  Future<List<InventoryReportRow>> inventoryReportRows();
}

abstract class PartyRepository {
  Future<List<CustomerModel>> getCustomers();

  Future<int> upsertCustomer({
    int? id,
    required String name,
    String? phone,
    String? notes,
    double balance = 0,
  });

  Future<void> deleteCustomer(int id);

  Future<List<SupplierModel>> getSuppliers();

  Future<int> upsertSupplier({
    int? id,
    required String name,
    String? phone,
  });

  Future<void> deleteSupplier(int id);
}

abstract class SyncService {
  Future<void> syncNow();
}

abstract class PrinterService {
  Future<void> printReceiptPdfBytes(List<int> bytes);
}

abstract class BarcodeScannerService {
  Future<String?> scanBarcode();
}
