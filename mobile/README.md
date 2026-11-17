# StockPesa Mobile

Android first Flutter client for the StockPesa API. Flutter owns navigation and presentation; the API remains the source of truth for stock, sales, balances, permissions, and reporting.

## Run

From this directory:

```sh
flutter pub get
flutter run --dart-define=API=http://10.0.2.2:3000
```

Use a Flutter release that includes Dart 3.10 or newer and a Java 17+ JDK for Android builds.

`10.0.2.2` reaches the host machine from an Android emulator. Use `http://localhost:3000` for an iOS simulator, or the development computer's LAN address for a physical phone. Start the API and PostgreSQL from the repository root with `docker compose up --build`.

The app defaults to the Android emulator API URL. Override it with `--dart-define=API=...`; do not commit live API credentials or production URLs. For production, provide an HTTPS URL through the same build define.
Android permits cleartext HTTP only in the debug manifest for local API testing; release builds do not enable it.
`.env.example` documents the development value; Flutter does not load that file automatically.

## Push notifications

Firebase Messaging is optional until Firebase values are configured. Initialize a Firebase Android/iOS app, enable Cloud Messaging, and build with `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_API_KEY`, and the matching `FIREBASE_ANDROID_APP_ID` or `FIREBASE_IOS_APP_ID` dart-defines. iOS also needs `FIREBASE_IOS_BUNDLE_ID`, the Push Notifications capability, and an APNs key configured in Firebase. Never put service-account credentials in the mobile build; the API receives `FIREBASE_SERVICE_ACCOUNT_JSON` from a deployment secret manager.

The app asks notification permission from Settings → Notification preferences, registers authorized tokens with the authenticated API, handles foreground messages, routes notification taps, and revokes the token on sign out. The API outbox sends low/out-of-stock transition messages to opted-in business users and deactivates invalid tokens. Other event types can be controlled in preferences but require their event producers before delivery is active.

## Structure

```text
lib/
  app/                 Router, onboarding, responsive app shell
  core/                Dio client, secure session storage, theme, shared states
  features/
    auth/              Session restoration and auth state
    dashboard/         Dashboard API repository
    products/           Product API repository
    stock/              Inventory API repository
    sales/              Checkout/history API repository
    customers/          Customer and credit API repository
    insights/           Dashboard/report/alert API repository
    settings/            Business profile and staff API repository
  screens/              Existing feature screens, incrementally being migrated
```

Repositories keep endpoint calls out of new presentation code. The legacy screens remain in `screens/` while their routes are being migrated; they use the same central Dio client and secure token store.

## Routes

| Route | Screen |
| --- | --- |
| `/splash`, `/onboarding` | Session restore and first run introduction |
| `/login`, `/register`, `/forgot-password` | Authentication; reset screen explains that the API has no reset endpoint |
| `/dashboard` | Live dashboard data |
| `/products`, `/products/add`, `/products/import` | Catalogue, create, CSV import |
| `/products/:productId`, `/products/:productId/edit` | Product detail, current stock movements, edit |
| `/sell`, `/sell/cart`, `/sell/payment`, `/sell/success/:saleId` | Cart and checkout; success reference |
| `/stock`, `/stock/intake`, `/stock/adjust`, `/stock/count`, `/stock/movements` | On hand, stock changes, counts, movement history |
| `/customers`, `/customers/:customerId` | Search/edit customers, debt filter, unpaid sales, recent purchases, payments, create a sale for the customer |
| `/sales`, `/sales/:saleId/receipt` | Sales history, return flow, receipt preview, PDF share/download, text summary |
| `/categories` | Product categories |
| `/alerts`, `/reports`, `/market-insights`, `/settings`, `/notification-settings`, `/staff`, `/privacy`, `/terms`, `/more` | Business alerts/insights, preferences, legal templates, profile, roles and management links |

On screens narrower than 600 logical pixels, navigation uses a bottom bar. Wider layouts use a navigation rail. Users can follow system appearance or select light/dark mode in settings.

## Screen descriptions

- **Home:** current-day/month sales, stock warnings, unread alert count, and shortcuts into selling and inventory.
- **Products:** searchable catalogue with stock/category filters, product detail/edit, barcode scan/create, and CSV import.
- **Sell:** searchable/scannable catalogue and editable cart, saved/parked carts, discount, payment selection, customer credit checks, cash change, and idempotent checkout. The payment step clearly shows server-side payment limitations.
- **Receipt:** backend receipt snapshot rendered as a preview with PDF share/download and a text summary. Print integration is identified as unavailable.
- **Customers:** search/edit, debt-only filter, unpaid and recent purchases, payment recording, and customer-prefilled sale start.
- **Sales history:** transaction actions include receipt, sharing, and a quantity-limited return with explicit restock choice and recorded refund/balance summary.
- **Inventory and alerts:** stock intake, adjustment, movement history, counts, low/out-of-stock filters, read state, and product navigation.
- **Reports:** role-filtered live business figures, sales/payment/profit summary, customer debt, stock value and warnings, recent stock movements, and top products.
- **Market insights:** tenant-scoped 7/30-day sales patterns, best/slow movers, stock health and explicitly estimated run-out timing.
- **Staff/settings:** owner-managed team roles and deactivation; editable business profile, receipt footer, theme, push preferences and legal templates.

## API coverage and known server limits

| Area | API calls used |
| --- | --- |
| Auth | `POST /auth/register`, `POST /auth/login`, `GET /auth/me`, `POST /auth/refresh`, `POST /auth/logout` |
| Dashboard | `GET /reports/dashboard`, `GET /alerts`, `GET /stock` |
| Products | `GET /products`, `GET /products/:id`, `GET /products/lookup`, `POST /products`, `PATCH /products/:id`, `DELETE /products/:id`, CSV preview/confirm |
| Stock | `GET /stock`, `GET /stock/movements`, `POST /stock/intake`, `POST /stock/adjustments`, stock count endpoints |
| Sales | `GET /sales`, `GET /sales/:id`, `POST /sales` with `Idempotency-Key`, returns and payment endpoints |
| Customers | `GET /customers`, `GET /customers/:id`, customer payments |
| Business | `GET/PATCH /business/profile`, `/users` staff routes, alert read routes, `/reports/export` audit route |
| Operations | `GET /health` database readiness check |

For manual M-Pesa recording, `POST /sales` accepts `method: "MPESA"`, `amountPaid`, and `mpesaReceiptNumber` (6–32 alphanumeric characters). A receipt is stored as a settled payment reference; sending the same receipt again in the same business returns `409`. Without `mpesaReceiptNumber`, checkout follows the configured mock mode and creates a pending payment for signed callback confirmation.

Reports use live `/reports/*` responses and are role-aware: cashiers see dashboard metrics while owners/managers can see sales totals, gross profit, payments by method, customer debt, inventory valuations, low stock, recent movements and top products. Owners and managers can export a formula-safe CSV summary; each export is audited. The API does not provide slow-mover or per-product profit figures, so the app does not invent them.

The checkout supports cash received/change, manual M-Pesa receipt recording, M-Pesa mock confirmation, bank, card, and credit sales. Manual M-Pesa requires a 6–32 character alphanumeric receipt and received amount; partial payment requires a customer account, and the business cannot reuse a receipt number. This records a payment already received and does not initiate STK Push. The mock flow remains pending until the signed demo callback settles it. The server sale DTO still has no bank/card reference input or tax configuration. Return refunds use the backend's original-payment-method behavior; the API has no refund-method selector. Return quantities and restocking are submitted to the transactional return endpoint, which is restricted to owners and managers. Staff creation, editing, and deactivation are owner-only. The API has no staff reactivation route.

Offline mode preserves the active and parked carts and a catalogue cache on-device. Checkout is disabled offline and no sale is queued, because there is no server reconciliation endpoint. Password reset, remote receipt printing, logo upload, tax configuration, language selection, and custom low-stock defaults are not exposed by the current API.

## Manual smoke test

The full Phase 6 QA checklist, including permissions, transaction/idempotency, cross-tenant, security, and release checks, is in [docs/phase6-qa-checklist.md](../docs/phase6-qa-checklist.md).

1. Start the API with seeded development data and launch the Android app.
2. Complete all three onboarding pages, close/reopen the app, and confirm onboarding stays complete.
3. Sign in as owner, manager, and cashier accounts. Confirm dashboard and permitted screens load; confirm server permission errors are shown clearly for restricted actions.
4. Register a development business using a valid Kenyan mobile number, matching passwords, and accepted terms. Try invalid phone, email, and mismatched passwords.
5. Open Products, search by name/SKU, change stock status and category, sort, page through results, open a product, edit it, scan a barcode, create a product from an unrecognized scanned barcode, and preview/confirm a CSV import.
6. Receive stock, make a positive and negative adjustment, open movements, and start/complete a stock count. Refresh each screen and confirm values come back from the API.
7. Make cash, manual M-Pesa, M-Pesa mock, bank, card, and credit sales. For manual M-Pesa, enter a confirmed receipt number and amount; use a customer if a balance remains. Verify an identical receipt cannot be recorded twice. For credit, choose an existing customer or create one. Confirm the sale reference appears and stock drops exactly once. In mock mode, the app invokes the mock confirmation endpoint after sale creation; check the resulting payment status. Retry a completed sale action only with the same payload/key; verify the API returns the original sale.
8. Open a customer, edit their name/phone/notes/credit limit, review recent and unpaid purchases, start a sale prefilled with that customer, and record a payment against an unpaid sale. Confirm balances refresh; attempt to exceed the due amount and confirm the API rejects it.
9. In sales history, open a receipt, share its PDF, download it, share a text summary, then return part of an item. Try a quantity above the remaining sold quantity and confirm rejection. Test return both with restocking (stock increases) and without restocking (stock is unchanged); confirm the result shows refund and remaining balance.
10. Review the alert filters and mark an alert read. Review dashboard and reports as owner/manager, then as cashier; confirm the cashier only sees permitted summary data. Verify payment methods, debt, profit, stock figures and top products against the API/database for the selected test period.
11. As owner, add a staff member, edit the role, deactivate the account, and confirm the deactivated user cannot sign in. As manager, confirm staff management is read-only and adding/editing is rejected by the server.
12. Save business name, type, phone, location, currency and receipt footer; inspect a newly generated receipt for these fields. Toggle device light/dark mode and resize to phone/tablet widths; check scroll, keyboard overlap, and no horizontal overflow.
13. Park a cart, create another, switch between them, close/reopen the app, and restore the cart. Turn off network access: confirm the offline banner appears, checkout is disabled, and the app states that no sale was queued. Reconnect and refresh.
14. Sign out and sign back in. Visit Password help and verify it describes the API limitation.

## Demo walkthrough

Use the seeded development owner account (`owner@stockpesa.app` / `Demo1234!`). Start at Dashboard, open Sell, scan or search for a product, add two units, park that cart, create a second cash sale, and share the receipt PDF. Open the original parked cart and complete it as credit for an existing customer. In Customers, open that customer, inspect the new balance and record a partial payment. Return one unit from the credit sale with restocking enabled, then visit Reports to see net sales, customer debt, profit, payment methods and stock movement. Finish in Alerts and Staff to show the unread badge and owner-only staff actions.

The demo seed data is for local development only. Do not use the shared demo passwords outside a local/demo environment.

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug
```

For a physical Android build, configure signing and use HTTPS for the API. Local development HTTP is intended for emulator/LAN testing only.
