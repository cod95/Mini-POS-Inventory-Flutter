import 'package:flutter/material.dart';

import '../../../core/models/app_models.dart';

/// Label + colour of an invoice status, shared by the invoices list, the
/// invoice details and the reports history.
String invoiceStatusLabel(
  SaleStatus status, {
  required bool arabic,
  bool isReturnDocument = false,
}) {
  if (isReturnDocument) return arabic ? 'فاتورة مرتجع' : 'Return';
  switch (status) {
    case SaleStatus.completed:
      return arabic ? 'مكتملة' : 'Completed';
    case SaleStatus.partiallyReturned:
      return arabic ? 'مرتجع جزئي' : 'Partly returned';
    case SaleStatus.returned:
      return arabic ? 'مرتجعة' : 'Returned';
    case SaleStatus.cancelled:
      return arabic ? 'ملغاة' : 'Cancelled';
  }
}

Color invoiceStatusColor(SaleStatus status, {bool isReturnDocument = false}) {
  if (isReturnDocument) return Colors.deepOrange;
  switch (status) {
    case SaleStatus.completed:
      return Colors.green;
    case SaleStatus.partiallyReturned:
      return Colors.amber.shade800;
    case SaleStatus.returned:
      return Colors.orange;
    case SaleStatus.cancelled:
      return Colors.red;
  }
}
