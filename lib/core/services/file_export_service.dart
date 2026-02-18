import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/repositories/repositories.dart';

class FileExportService {
  Future<File> exportSalesCsv(List<SalesReportRow> rows) async {
    final csvRows = <List<dynamic>>[
      ['invoice_no', 'date', 'total', 'payment_method', 'status'],
      ...rows.map(
        (row) => [
          row.invoiceNo,
          row.date.toIso8601String(),
          row.total.toStringAsFixed(2),
          row.paymentMethod,
          row.status,
        ],
      ),
    ];

    return _writeCsv('sales_report', csvRows);
  }

  Future<File> exportInventoryCsv(List<InventoryReportRow> rows) async {
    final csvRows = <List<dynamic>>[
      ['name', 'sku', 'category', 'stock', 'cost', 'price', 'low_stock'],
      ...rows.map(
        (row) => [
          row.name,
          row.sku,
          row.category,
          row.stock,
          row.cost.toStringAsFixed(2),
          row.price.toStringAsFixed(2),
          row.lowStock,
        ],
      ),
    ];

    return _writeCsv('inventory_report', csvRows);
  }

  Future<void> shareFile(File file) {
    return Share.shareXFiles([XFile(file.path)]);
  }

  Future<File> _writeCsv(String prefix, List<List<dynamic>> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(dir.path, fileName));
    final csv = const ListToCsvConverter().convert(rows);
    return file.writeAsString(csv);
  }
}
