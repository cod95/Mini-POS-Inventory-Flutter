# QuickStock POS — Mini POS + Inventory (Flutter MVP)

> **Offline-first** point-of-sale and inventory management app for small stores, built with Flutter 3.x using **BLoC/Cubit**, **feature-first clean architecture**, and **Drift (SQLite)**.

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Tech Stack](#tech-stack)
4. [Architecture](#architecture)
5. [Project Structure](#project-structure)
6. [Data Model](#data-model)
7. [Getting Started](#getting-started)
8. [Default Credentials](#default-credentials)
9. [Configuration](#configuration)
10. [Building for Release](#building-for-release)
11. [Testing](#testing)
12. [Export & Receipts](#export--receipts)
13. [Localization](#localization)
14. [Extending the App](#extending-the-app)
15. [Contributing](#contributing)
16. [License](#license)

---

## Overview

**QuickStock POS** is a fully local, offline-first Flutter app designed for small retail stores. It covers the complete store workflow — from scanning a product barcode all the way to generating a printed PDF receipt — without ever requiring an internet connection.

Key design goals:

- **Zero cloud dependency** — all data lives in a local SQLite database via Drift.
- **Clean Architecture** — domain contracts are separated from data and UI layers.
- **Role-aware** — Admin and Cashier roles control access to sensitive operations.
- **Extensible** — service interfaces (printer, sync, barcode scanner) are fully abstracted so real implementations can be swapped in without touching business logic.

---

## Features

| Area | Capabilities |
|---|---|
| **POS** | Product search / barcode scan → cart → discount → checkout |
| **Products** | Full CRUD with categories, SKU, barcode, unit, cost/price, low-stock threshold |
| **Inventory** | Stock movement tracking (add / remove / adjust / purchase / sale / return) |
| **Invoices** | Sales list with filters, invoice detail view, partial/full returns with automatic restock |
| **Reports** | Dashboard metrics (today + month), best sellers, sales-by-product, low-stock alerts |
| **Export** | Sales CSV and Inventory CSV exported to device storage then shared |
| **Receipts** | PDF receipt generation + system share sheet; printer abstraction stub (ESC/POS Bluetooth ready) |
| **Auth** | Local PIN login (Cashier) and password login (Admin); role-based UI guards |
| **Settings** | Store name, currency, tax toggle/rate, receipt header/footer, language, negative stock flag, PIN & password change |
| **Localization** | English / Arabic scaffold (LTR/RTL ready via `flutter_localizations`) |
| **Customers** | Customer ledger with outstanding balance tracking |
| **Suppliers** | Supplier records linked to purchase movements |

---

## Tech Stack

| Concern | Package / Tool |
|---|---|
| UI framework | Flutter 3.x (Material 3, null-safety) |
| State management | `flutter_bloc` ^9 (Cubit pattern) |
| Routing | `go_router` ^17 (shell routes + auth redirect) |
| Local database | `drift` ^2.21 + `sqlite3_flutter_libs` |
| Code generation | `build_runner` + `drift_dev` |
| PDF generation | `pdf` + `printing` |
| File sharing | `share_plus` |
| CSV export | `csv` |
| Charts | `fl_chart` |
| Barcode scanner | `mobile_scanner` (via service abstraction) |
| Localization | `flutter_localizations` + `intl` |
| Image picker | `image_picker` |
| Unique IDs | `uuid` |
| Equality | `equatable` |

---

## Architecture

The app follows a **feature-first clean architecture** with three horizontal layers:

```
┌──────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                 │
│   Features: pos / products / reports / invoices /    │
│             settings / auth / shell                  │
│   Each feature owns its Cubit(s) + Pages + Widgets   │
└───────────────────────┬──────────────────────────────┘
                        │ depends on ▼
┌──────────────────────────────────────────────────────┐
│                     DOMAIN LAYER                     │
│   Entities  (app_entities.dart)                      │
│   Repository contracts  (repositories.dart)          │
│   Core models / enums  (app_models.dart)             │
└───────────────────────┬──────────────────────────────┘
                        │ depends on ▼
┌──────────────────────────────────────────────────────┐
│                      DATA LAYER                      │
│   Drift DB schema  (app_database.dart + .g.dart)     │
│   Seed data  (seed_data.dart)                        │
│   Repository implementations  (local_repositories)  │
└──────────────────────────────────────────────────────┘
```

**Dependency injection** is handled manually via `AppDependencies` — a plain Dart class that wires up all repositories, services, and cubits at app startup. Widgets receive dependencies through `AppScope` (an `InheritedWidget`).

**Global state** (`AppCubit`) holds authentication session and app settings. All feature-level cubits are created locally and scoped to their route.

---

## Project Structure

```text
lib/
├── main.dart                        # Entry point — initialises dependencies, runs app
│
├── app/
│   ├── app.dart                     # Root MaterialApp.router + theme/locale wiring
│   ├── app_dependencies.dart        # Manual DI — creates all repos, services & cubits
│   ├── app_scope.dart               # InheritedWidget to pass dependencies down the tree
│   ├── router/
│   │   └── app_router.dart          # GoRouter config: auth redirect + shell + routes
│   └── theme/
│       └── app_theme.dart           # Material 3 theme, spacing constants, border radii
│
├── core/
│   ├── errors/
│   │   └── app_exception.dart       # Typed application exception
│   ├── l10n/
│   │   └── app_localizations.dart   # Localisation delegate + EN/AR strings
│   ├── models/
│   │   └── app_models.dart          # Shared models, enums and input DTOs
│   ├── services/
│   │   ├── barcode_scanner_service_impl.dart  # GoRouter-based scanner page integration
│   │   ├── file_export_service.dart           # CSV write + share via share_plus
│   │   ├── receipt_pdf_service.dart           # PDF build + print/share
│   │   └── stub_services.dart                 # FakeSyncService, StubPrinterService
│   ├── state/
│   │   ├── app_cubit.dart           # Global cubit: auth + settings
│   │   └── view_state.dart          # Generic loading/data/error state wrapper
│   ├── utils/
│   │   ├── formatters.dart          # Currency, date, number formatters
│   │   └── money_calculator.dart    # Pure arithmetic helpers (line total, tax, profit)
│   └── widgets/
│       ├── buttons.dart             # Reusable button components
│       ├── cards.dart               # Reusable card components
│       ├── fields.dart              # Reusable form field components
│       └── states.dart              # Loading / error / empty state widgets
│
├── data/
│   ├── local/
│   │   ├── db/
│   │   │   ├── app_database.dart    # Drift database: tables, schema version, migrations
│   │   │   └── app_database.g.dart  # Generated Drift code (do not edit)
│   │   └── seed/
│   │       └── seed_data.dart       # First-run seed: 5 categories, 20 products, customers, suppliers
│   └── repositories/
│       └── local_repositories.dart  # Concrete Drift implementations of all repository contracts
│
├── domain/
│   ├── entities/
│   │   └── app_entities.dart        # Rich view entities (ProductView, SaleView, etc.)
│   └── repositories/
│       └── repositories.dart        # Abstract repository interfaces + result value objects
│
└── features/
    ├── auth/
    │   └── presentation/
    │       ├── cubit/               # (login state management)
    │       └── pages/
    │           └── login_page.dart  # PIN / password login screen
    ├── pos/
    │   └── presentation/
    │       ├── cubit/
    │       │   └── pos_cubit.dart   # Cart state, search, barcode scan, checkout
    │       ├── pages/
    │       │   └── pos_page.dart    # Main POS screen
    │       └── widgets/
    │           ├── product_tile.dart    # Product card with image and low-stock badge
    │           └── cart_item_tile.dart  # Cart item row with qty/discount controls
    ├── products/
    │   └── presentation/
    │       ├── cubit/
    │       │   └── products_cubit.dart  # Product list, filter, CRUD, stock movements
    │       ├── pages/
    │       │   └── products_page.dart   # Product catalogue + category filter chips
    │       └── widgets/                 # Product form, stock movement dialog, etc.
    ├── invoices/
    │   └── presentation/
    │       ├── cubit/
    │       │   └── invoice_detail_cubit.dart  # Invoice detail + return flow
    │       └── pages/
    │           └── invoice_detail_page.dart   # Invoice detail + return items UI
    ├── reports/
    │   └── presentation/
    │       ├── cubit/
    │       │   └── reports_cubit.dart   # Dashboard metrics, charts, CSV export trigger
    │       └── pages/
    │           └── reports_page.dart    # Dashboard cards + best sellers chart
    ├── settings/
    │   └── presentation/
    │       ├── cubit/               # Settings form state
    │       └── pages/
    │           └── settings_page.dart   # Store settings, language, PIN/password change
    ├── shared/
    │   └── widgets/
    │       └── barcode_scanner_page.dart  # Full-screen camera scanner page
    └── shell/
        └── presentation/
            └── pages/
                └── app_shell_page.dart  # Bottom navigation shell (POS / Products / Reports / Settings)

test/
├── widget_test.dart
├── core/
│   └── utils/
│       └── money_calculator_test.dart   # Unit tests for MoneyCalculator
└── data/
    └/repositories/
        └── stock_logic_test.dart        # Unit tests for stock deduction logic
```

---

## Data Model

All data is persisted in a single SQLite file (`mini_pos_inventory.sqlite`) via Drift.

### Tables

| Table | Purpose |
|---|---|
| `products` | Product catalogue (name, SKU, barcode, category FK, cost, price, stock, threshold, unit, image) |
| `categories` | Product categories |
| `stock_movements` | Append-only log: add / remove / adjust / purchase / sale / return |
| `customers` | Customer records with outstanding balance |
| `suppliers` | Supplier records |
| `purchases` | Purchase records (linked to supplier + product + stock movement) |
| `sales` | Invoice header (invoice no., totals, payment method, status) |
| `sale_items` | Invoice line items with price/cost snapshots (preserves history after product edits) |
| `app_settings` | Singleton row (id=1) for all store configuration |

### Schema Version

Current schema version: **2**  
Migration from v1 → v2 adds the `image_path` column to `products`.

### Entity Relationships

```
categories ──< products >── stock_movements
                  │
                  ├──< sale_items >── sales >── customers
                  │
                  └──< purchases >── suppliers
```

### Invoice Numbering

- **Sales:** `INV-YYYYMMDD-XXXX` (e.g. `INV-20260218-0001`)
- **Returns:** `RET-YYYYMMDD-XXXX` (e.g. `RET-20260218-0001`)

---

## Getting Started

### Prerequisites

- Flutter SDK `^3.10.4` ([Install Flutter](https://docs.flutter.dev/get-started/install))
- Dart SDK `^3.10.4` (included with Flutter)
- A device/emulator (Android, iOS, or desktop)

### 1. Clone the repository

```bash
git clone https://github.com/AmrNabil12/MiniPOS-Inventory-Offline-Flutter-MVP.git
cd MiniPOS-Inventory-Offline-Flutter-MVP
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. (Optional) Re-generate Drift code

> The generated file `lib/data/local/db/app_database.g.dart` is already committed.  
> Only run this if you modify the Drift table definitions.

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Run the app

```bash
flutter run
```

On first launch, the database is automatically seeded with:

- 5 categories (Beverages, Snacks, Dairy, Household, Personal Care)
- 20 products with realistic prices, barcodes, and Unsplash images
- 3 sample customers (including a default "Walk-in Customer")
- 2 sample suppliers

---

## Default Credentials

| Role | Field | Default Value |
|---|---|---|
| **Cashier** | PIN | `1234` |
| **Admin** | Password | `admin123` |

> ⚠️ Change these immediately in **Settings** before deploying to a real store.

### Role Permissions

| Action | Cashier | Admin |
|---|---|---|
| POS / checkout | ✅ | ✅ |
| View products | ✅ | ✅ |
| Add / edit products | ❌ | ✅ |
| Delete products | ❌ | ✅ |
| Edit product prices | ❌ | ✅ |
| View reports | ✅ | ✅ |
| Export CSV | ✅ | ✅ |
| Manage settings | ❌ | ✅ |
| Process returns | ✅ | ✅ |
| Manage customers/suppliers | ❌ | ✅ |

---

## Configuration

All settings are persisted in the `app_settings` table and editable from **Settings → Store Settings**:

| Setting | Default | Description |
|---|---|---|
| Store name | `Mini Mart` | Appears on receipts |
| Currency | `EGP` | Displayed throughout the UI |
| Tax enabled | `false` | Enables VAT calculation at checkout |
| Tax rate | `14%` | Egyptian standard VAT rate |
| Receipt header | `Mini Mart - Welcome` | Top line of PDF receipt |
| Receipt footer | `Thank you for shopping with us` | Bottom line of PDF receipt |
| Language | `en` | `en` or `ar` |
| Allow negative stock | `false` | If `true`, checkout is allowed even when stock = 0 |
| Cashier PIN | `1234` | 4-digit PIN for cashier login |
| Admin password | `admin123` | Password for admin login |

---

## Building for Release

### Android APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### Android App Bundle (Play Store)

```bash
flutter build appbundle --release
```

### iOS (macOS required)

```bash
flutter build ios --release
```

Then archive and distribute via Xcode.

### Windows (Desktop)

```bash
flutter build windows --release
```

### Linux (Desktop)

```bash
flutter build linux --release
```

### macOS (Desktop)

```bash
flutter build macos --release
```

> For Android signing, configure `android/key.properties` and update `android/app/build.gradle.kts` accordingly before building a release APK.

---

## Testing

Run all tests:

```bash
flutter test
```

### Test Coverage

| File | What is tested |
|---|---|
| `test/core/utils/money_calculator_test.dart` | `lineTotal`, `subtotal`, `tax`, `orderTotal`, `profitForLine` edge cases |
| `test/data/repositories/stock_logic_test.dart` | Stock movement update behavior, sale stock deduction with/without negative stock allowed |

---

## Export & Receipts

### CSV Export

From the **Reports** screen:

- **Export Sales CSV** — all sales rows (invoice no., date, total, payment, status)
- **Export Inventory CSV** — all products (name, SKU, category, stock, cost, price, low-stock flag)

Files are written to the app documents directory and then shared via the system share sheet (e-mail, WhatsApp, cloud storage, etc.).

### PDF Receipts

After a successful checkout on the **POS** screen:

- **Print Receipt** — triggers the system print dialog (Google Cloud Print / AirPrint)
- **Share PDF** — shares the PDF bytes via the system share sheet

Printer integration is abstracted via `PrinterService`. The current implementation (`StubPrinterService`) is a no-op stub ready for a real ESC/POS Bluetooth integration (e.g., via `esc_pos_bluetooth` or `flutter_bluetooth_serial`).

---

## Localization

Go to **Settings → Language** and select:

- 🇬🇧 **English** (`en`)
- 🇪🇬 **Arabic** (`ar`)

The language choice is persisted in the database and applied on next app startup. The app uses `flutter_localizations` with a custom `AppLocalizations` delegate, and the theme/router respect RTL layout automatically.

To add a new locale:

1. Add the locale string to `AppLocalizations.supportedLocales`.
2. Add translated strings to the appropriate ARB files (if using `intl` ARB workflow) or extend the localizations class.

---

## Extending the App

### Adding a real ESC/POS Bluetooth printer

1. Add `esc_pos_bluetooth` (or equivalent) to `pubspec.yaml`.
2. Create a class implementing `PrinterService` (see `lib/domain/repositories/repositories.dart`).
3. Replace `StubPrinterService()` with your implementation in `AppDependencies.create()`.

### Adding cloud sync

1. Implement the `SyncService` interface.
2. Replace `FakeSyncService()` with your implementation in `AppDependencies.create()`.
3. The fake service already simulates a 700 ms delay for UI testing.

### Adding a new feature screen

1. Create `lib/features/<feature>/presentation/cubit/<feature>_cubit.dart`.
2. Create `lib/features/<feature>/presentation/pages/<feature>_page.dart`.
3. Register the new route in `lib/app/router/app_router.dart`.
4. Add a navigation tab entry in `lib/features/shell/presentation/pages/app_shell_page.dart` if needed.

---

## Contributing

1. **Fork** the repository.
2. Create a feature branch: `git checkout -b feat/your-feature-name`.
3. Commit your changes following [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, etc.
4. Open a **Pull Request** against `main`.

Please keep code consistent with the existing style (`flutter_lints` is enforced).

---

## License

This project is released under the **MIT License**. See [LICENSE](LICENSE) for details.

---

*Built as a Flutter MVP — contributions, feedback, and issues are welcome!*
