import 'package:drift/drift.dart';

import '../../local/db/app_database.dart';

/// Deliberately does NOT seed any demo categories, products, customers, or
/// suppliers. Every fresh install starts completely empty — ready for the
/// real shop's own categories and products to be entered from scratch.
class SeedData {
  const SeedData(this.db);

  final AppDatabase db;

  Future<void> ensureSeeded() async {
    await _ensureSettings();
    await _ensureUsers();
  }

  /// First run (or first run after upgrading to multi-user): creates the
  /// default Admin and Cashier accounts from the legacy password/PIN stored
  /// in settings. The fixed uuids let two devices recognise the same default
  /// accounts when they sync.
  Future<void> _ensureUsers() async {
    final existing = await db.select(db.userAccounts).get();
    if (existing.isNotEmpty) {
      await _scrubLegacySecrets();
      return;
    }
    final settings =
        await (db.select(db.appSettings)..where((t) => t.id.equals(1))).getSingleOrNull();
    await db.into(db.userAccounts).insert(
          UserAccountsCompanion.insert(
            uuid: 'default-admin',
            name: 'Admin',
            role: 'admin',
            secret: _orDefault(settings?.adminPassword, 'admin123'),
            mustChangeSecret: const Value(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await db.into(db.userAccounts).insert(
          UserAccountsCompanion.insert(
            uuid: 'default-cashier',
            name: 'Cashier',
            role: 'cashier',
            secret: _orDefault(settings?.cashierPin, '1234'),
            mustChangeSecret: const Value(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await _scrubLegacySecrets();
  }

  String _orDefault(String? value, String fallback) =>
      (value == null || value.isEmpty) ? fallback : value;

  /// The old single admin password / cashier PIN lived in plain text inside
  /// the settings row. Accounts replaced them, so wipe those leftovers.
  Future<void> _scrubLegacySecrets() async {
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      const AppSettingsCompanion(
        cashierPin: Value(''),
        adminPassword: Value(''),
      ),
    );
  }

  /// Inserts the default settings row ONLY the very first time the app runs
  /// (when no row with id=1 exists yet). Using insertOrIgnore here — instead
  /// of insertOnConflictUpdate — is important: this method runs on every app
  /// startup, and insertOnConflictUpdate would silently reset every setting
  /// (currency, exchange rate, tax rate, receipt text, PIN, password) back
  /// to these hardcoded defaults on every restart, wiping out anything
  /// changed from the Settings screen.
  Future<void> _ensureSettings() async {
    await db.into(db.appSettings).insert(
          AppSettingsCompanion.insert(
            id: const Value(1),
            storeName: const Value('Mini Mart'),
            currency: const Value('USD'),
            secondaryCurrencyCode: const Value('LBP'),
            exchangeRate: const Value(89000),
            taxEnabled: const Value(false),
            taxRate: const Value(0.11),
            receiptHeader: const Value('Mini Mart - Welcome'),
            receiptFooter: const Value('Thank you for shopping with us'),
            language: const Value('en'),
            allowNegativeStock: const Value(false),
            cashierPin: const Value('1234'),
            adminPassword: const Value('admin123'),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
