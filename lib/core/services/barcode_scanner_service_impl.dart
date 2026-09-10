import 'package:flutter/material.dart';

import '../../domain/repositories/repositories.dart';
import '../../features/shared/widgets/barcode_scanner_page.dart';

class RouteBarcodeScannerService implements BarcodeScannerService {
  RouteBarcodeScannerService(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;

  @override
  Future<String?> scanBarcode() async {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return null;
    }
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    return result;
  }
}
