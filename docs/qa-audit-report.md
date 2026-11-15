# StockPesa V1 QA Audit Report

**Audit date:** 15 November 2026

**Scope:** static review of backend, Prisma schema/migration, app configuration, Flutter screens/API wiring, documentation, and automated checks available in this environment.

**Code changes:** none. This audit did not change application code or add tests.

## Verdict

**NOT READY for a live merchant demo or user pilot.** The API compiles and its small monetary helper test passes, but the backend/database and Flutter user journeys could not be run here. The Android release variant uses the debug signing key, which is not suitable for distribution. Several requested capabilities are also absent or only represented by the mock flow. A local owner-led walkthrough may be possible in a properly provisioned developer environment, but has not been demonstrated by this audit.

No P0 vulnerability was confirmed by static inspection. This is not a security certification: tenant isolation, authorization, transaction behavior, payment callbacks, and runtime errors were not exercised against a live database/API.

## Test plan

1. Inventory API controllers, role guards, Prisma models/migration, environment configuration, seed script, Flutter screens, route configuration, and API client.
2. Run backend build/tests and Prisma validation.
3. Run Flutter analyzer/tests and check for an Android device/build toolchain.
4. Attempt local startup and record unavailable services/tooling.
5. Trace critical auth, tenant, inventory, sale, payment, return, receipt, alert, report, and export paths in source.
6. Record findings with severity, reproduction/verification steps, expected and actual behavior, root cause, and recommendation.

## Environment and automated test results

| Check | Result | Evidence / limitation |
|---|---|---|
| Node/npm dependencies | Available | Node v22.23.2 and npm 10.9.8; backend `node_modules` and lockfile are present. No clean `npm ci` was run. |
| Backend build and test | PASS (limited) | `cd backend && npm test`: Nest build succeeds; 1 test passes (`money.test.js`). This is not API or database integration coverage. |
| Prisma schema | PASS (schema only) | `npx prisma validate` succeeds. No PostgreSQL connection or migration execution. |
| Flutter analyze | BLOCKED | Flutter attempts to write engine stamps under the read-only SDK path. |
| Flutter tests | BLOCKED | Same read-only SDK startup failure; prior Phase 6 run had 9 passing tests, but this audit could not rerun them. |
| Flutter Android build | NOT RUN | Java/JDK is not installed. |
| Emulator/device E2E | BLOCKED | No emulator/device available; adb daemon cannot bind its local socket in this environment. |
| Docker/PostgreSQL startup | BLOCKED | `docker compose` is unavailable; bundled `docker-compose` cannot create its runtime directory. No database listener is available. |
| API startup / HTTP checks | NOT RUN | Requires PostgreSQL and backend environment; therefore no live requests or response codes were observed. |
| Secrets in mobile source | No embedded credentials found in reviewed source | API base URL is configurable through `--dart-define=API`; default is the Android emulator host. Local backend `.env` is ignored by git. Secret values were not opened or copied into this report. |

## Feature test matrix

“Static support” means code paths were found; it does not mean they passed runtime tests.

| Area | Coverage/status | Audit result |
|---|---|---|
| Clean checkout, dependencies, Compose, migrations, seed | Partially reviewed; runtime blocked | README documents setup and demo accounts. Clean install, Compose, database migration, seed execution, and demo login are unverified. |
| Registration/login/session/refresh/logout | Static support; runtime unverified | Routes and secure-storage client wiring exist. Password reset is explicitly unavailable. Invalid credentials, expiry, persistence, and logout were not run. |
| Roles and permissions | Static support; runtime unverified | Guards and owner/manager/cashier/storekeeper checks are present. 403 behavior and UI hiding were not exercised. |
| Tenant isolation | Static review only | Most entity lookups inspected scope by token business ID. No two-tenant adversarial API tests were run. |
| Products/categories/search/sorting | Static support; runtime unverified | Pagination, filters, barcode/SKU lookup, and role guards exist. Duplicate/category/import cases were not run. |
| CSV catalogue import | Static support; runtime unverified | Preview and confirm paths validate input and transact confirmed rows. Repeated confirmation has no explicit import idempotency key; rows without unique SKU/barcode can be duplicated by resubmitting. |
| Stock intake/adjustment/count/movements | Static support; runtime unverified | Stock updates and ledger writes are transactional and stock updates use a product lock. Intake audit-log entry is absent; adjustment and stock-count audit paths exist. Concurrency and movement reconciliation were not exercised. |
| Alerts | Static support; runtime unverified | Alert creation/read endpoints and app wiring exist. Threshold transitions, duplicate suppression, badges, navigation, and negative-attempt behavior were not run. |
| Cash/bank/card/credit sale | Static support; runtime unverified | Transactional sale path creates sale items, stock movement, payment (except credit), receipt snapshot, and audit record. API/database failure rollback and retry behavior remain unverified. |
| M-Pesa mock | Static support; runtime unverified | Mock confirmation and signed callback path exist. No callback, replay, invalid-signature, or end-to-end payment was executed. Manual receipt entry and real STK Push are absent. |
| Customer credit/payment | Static support; runtime unverified | Credit limits and outstanding checks are present. Payment races, overpayment rejection, balance consistency, and debt reports were not run. |
| Return/refund | Static support; runtime unverified | Return quantity bounds, restock toggle, refund bounds, and role guard are in code. Partial/full return and balance math were not run. Return uses the original payment method; there is no refund-method selector or distinct return receipt flow. |
| Receipts/PDF/share | Static support; runtime unverified | PDF generation, save/share, and summary share code exist. Native plugins and PDF output were not exercised. Cashier name is only resolved when the currently signed-in user made the sale. |
| Dashboard/reports/export | Partial support; runtime unverified | Dashboard, sales, product, stock, debt, low-stock, and CSV export endpoints exist. No report PDF export; detailed grouping/filter metrics requested in the brief are not implemented. |
| Audit logs | Partial support; runtime unverified | Sensitive paths have audit writes, but stock intake has none and there is no audit-log viewing API/screen. |
| Offline/network behavior | Static support; runtime unverified | The app reports offline checkout failure and preserves the cart; it does not queue sales for synchronization. Reconnect behavior was not run. |
| Android UX/device compatibility | Not tested | No emulator/device or Java build toolchain. Layout, camera permission, keyboard, share/save, navigation, and crash behavior remain unknown. |

## Findings

### P1 — Must address before external demo / user testing

#### QA-001: Android release build is signed with the debug key

- **Feature:** Android packaging and release readiness
- **Steps to reproduce:** Inspect `mobile/android/app/build.gradle.kts` under `android.buildTypes.release`.
- **Expected:** Release artifacts use a dedicated upload/release signing configuration, with key material kept out of source control.
- **Actual:** `signingConfig` points to `signingConfigs.getByName("debug")`.
- **Severity/status:** P1 — open.
- **Root cause:** Release signing was left at the Flutter starter configuration.
- **Recommended fix:** Configure an operator-supplied keystore through ignored properties or CI secrets, then verify the signed AAB and install it from an internal track. Do not publish the debug-signed build.

#### QA-002: Backend automation does not cover critical application behavior

- **Feature:** API, transaction, tenant, and permission regressions
- **Steps to reproduce:** Run `cd backend && npm test` and inspect `backend/test`.
- **Expected:** Automated tests exercise representative auth, role, tenant, stock, sale, payment, return, and report behavior against a disposable database.
- **Actual:** Build plus one money helper test; no API/database integration suite exists.
- **Severity/status:** P1 — open.
- **Root cause:** Current test suite is a unit-level smoke test only.
- **Recommended fix:** Add isolated integration coverage for the acceptance-critical journeys and rollback/idempotency/tenant cases before relying on demo data.

#### QA-003: Manual M-Pesa recording and STK Push are unavailable

- **Feature:** M-Pesa sale/payment
- **Steps to reproduce:** In the app, select M-Pesa at checkout; inspect the explanatory message and `POST /sales`/`payments/mpesa` routes.
- **Expected:** For the requested manual-payment journey, cashier can enter amount and M-Pesa receipt reference; STK Push may be scaffolded if claimed.
- **Actual:** Current flow is mock checkout only. There is no manual receipt-number entry or STK initiation endpoint. The app explains this limitation.
- **Severity/status:** P1 for a real merchant demo; mock-only is acceptable only when clearly disclosed in a scripted software demo.
- **Root cause:** Payment integration intentionally stops at a mock callback path.
- **Recommended fix:** Before field testing, implement manual M-Pesa recording with server-side validation/audit, or explicitly constrain the pilot/demo to mock mode. Do not claim live M-Pesa support.

### P2 — Should address before broad demo / polish

#### QA-004: Stock intake has no audit-log entry

- **Feature:** Stock intake accountability
- **Steps to reproduce:** Trace `POST /stock/intake` in `backend/src/stock/stock.module.ts`; compare with the adjustment handler.
- **Expected:** Intake quantity, cost, supplier/reference, actor, and product are auditable in the same transaction as stock and movement changes.
- **Actual:** Intake writes a stock movement and updates buying price, but does not write an `AuditLog` row. Adjustments do.
- **Severity/status:** P2 — open.
- **Root cause:** Audit creation is not included in the intake transaction.
- **Recommended fix:** Write an intake audit record in the same transaction and add a regression check for rollback and idempotent replay.

#### QA-005: CSV import confirmation has no explicit idempotency protection

- **Feature:** Product import retry safety
- **Steps to reproduce:** Confirm the same CSV twice where rows have no SKU/barcode and use the same tenant.
- **Expected:** Retry returns the prior import result or safely refuses a duplicate submission.
- **Actual:** Import confirmation has no idempotency key/import fingerprint. Rows without unique identifiers may be created again on a second submit.
- **Severity/status:** P2 — open.
- **Root cause:** The endpoint validates row identifiers but does not persist import-level request identity.
- **Recommended fix:** Require a stable import idempotency token or persist a file/request fingerprint and return the first result on replay.

#### QA-006: Requested report coverage and PDF export are incomplete

- **Feature:** Dashboard, financial reporting, export
- **Steps to reproduce:** Inspect `/reports/*`, the Reports screen, and export action.
- **Expected:** As specified in the QA brief, reports expose cashier/date grouping, average sale, sales by product/cashier, slow movers/per-product profit, and PDF as well as CSV export.
- **Actual:** Current endpoints return summary sales/payment/profit, top products, stock, debt, and CSV summary. Several requested dimensions and report PDF export are not present.
- **Severity/status:** P2 — open; narrow this scope if those report dimensions are explicitly deferred from V1.
- **Root cause:** V1 report implementation is intentionally a summary, not the full requested report suite.
- **Recommended fix:** Agree on the V1 demo report contract, then implement only the required dimensions and verify totals against controlled data.

#### QA-007: Password reset journey is unavailable

- **Feature:** Account recovery
- **Steps to reproduce:** Open `/forgot-password` from login.
- **Expected:** Reset request and safe reset flow, or an explicit operational recovery procedure for the owner.
- **Actual:** Screen says reset is unavailable and tells staff to contact the business administrator; no API endpoint exists.
- **Severity/status:** P2 — open / documented limitation.
- **Root cause:** No reset token delivery or password-reset backend flow.
- **Recommended fix:** Provide a safe owner/admin reset process before a self-service pilot, or keep the limitation visible and train pilot owners.

#### QA-008: Audit log has no user-facing inspection path

- **Feature:** Audit log review
- **Steps to reproduce:** Search API routes and app screens for audit-log list/detail endpoints.
- **Expected:** Authorized business owner can inspect sensitive changes and actor/time metadata if “audit logs” are presented as a merchant feature.
- **Actual:** Audit records are written internally, but no read endpoint or app screen exposes them.
- **Severity/status:** P2 — open; depends on whether audit visibility is a V1 promise.
- **Root cause:** Audit persistence was implemented without a review workflow.
- **Recommended fix:** Add owner-only, tenant-scoped, paginated audit viewing or describe audit as an internal support control rather than a user-facing feature.

#### QA-009: Receipt cashier name depends on viewer being the cashier

- **Feature:** Receipt/PDF data
- **Steps to reproduce:** Create a sale as cashier, then view that receipt while signed in as owner/manager.
- **Expected:** Receipt shows the cashier who made the sale.
- **Actual:** `ReceiptService` derives cashier name only when `sale.userId` equals the currently signed-in user. The sale detail response does not include the seller name.
- **Severity/status:** P2 — open; not runtime verified.
- **Root cause:** Receipt lookup lacks the seller relation and uses the viewer’s `/auth/me` record as a substitute.
- **Recommended fix:** Return the sale creator’s safe display name in the tenant-scoped sale detail response and use it in receipt rendering.

### P3 — Optional / operational follow-up

#### QA-010: Shared demo credentials must remain isolated from public environments

- **Feature:** Seed and deployment operations
- **Steps to reproduce:** Run the documented local seed and note the fixed demo password.
- **Expected:** Demo users are limited to local/disposable staging systems and never reachable in production.
- **Actual:** Seed is idempotent and local Compose explicitly enables it; deployment docs warn against production use. Runtime environment isolation was not exercised.
- **Severity/status:** P3 — documented control; verify in deployment pipeline.
- **Root cause:** Predictable demo credentials are intentional for local demonstrations.
- **Recommended fix:** Enforce that production deployment never runs the seed command and monitor for seeded account addresses before release.

## Security and data-integrity observations

- Passwords use bcrypt hashes; auth checks active user/business membership on protected requests and refresh.
- Role guards and many tenant-scoped queries are present. Direct hostile cross-business ID tests were not possible, so isolation remains unverified.
- Production startup requires explicit CORS and non-placeholder secrets, disables mock M-Pesa, and disables Swagger by default. Rate limits are per-process; deployment documentation correctly calls for a shared gateway limit at scale.
- Stock mutation code uses a transaction and product-level PostgreSQL advisory lock; sale and return paths also use transactional operations and idempotency keys when supplied.
- Manual verification of rollback, payment callback signature/replay behavior, concurrency, return math, report totals, receipt PDF content, alert de-duplication, and audit atomicity remains outstanding.
- Local Compose contains known development credentials and demo seed configuration. It is not a production deployment file; production Compose is a template and has not been parsed or started here.

## Missing test coverage

1. API integration tests against disposable PostgreSQL for auth, registration, roles, and tenant isolation.
2. Transaction rollback assertions for sale, payment, return, stock count, and CSV import.
3. Concurrent last-unit sale, customer payment, stock intake, and callback replay tests.
4. MPesa valid/invalid signature, failed callback, amount mismatch, replay, and wrong-tenant/payment tests.
5. CSV duplicate import and malformed upload cases.
6. Report totals compared with controlled seeded transactions; CSV contents and export audit.
7. Flutter integration tests for login, product creation, stock intake, cash sale, stock deduction, receipt, alerts, and reports.
8. Android device checks for camera permission, receipt save/share plugins, keyboard/layout, offline transitions, and signed release install.

## Prioritized fix plan

### P0 — Must fix before demo

- None confirmed by the checks that could run. Runtime/security acceptance remains incomplete; absence of a confirmed P0 is not a pass.

### P1 — Must fix before user testing

1. Replace debug release signing with controlled release signing (QA-001).
2. Add API/database regression tests for transactionality, roles, tenant isolation, and idempotency (QA-002).
3. Decide and implement the manual M-Pesa recording requirement, or explicitly constrain testing/demo claims to mock-only (QA-003).
4. Execute the database-backed and Android user journeys on a working developer machine/device before calling the build demo-ready.

### P2 — Should fix for polish and reliable operations

1. Audit stock intake (QA-004).
2. Make CSV confirmation retry-safe (QA-005).
3. Agree a smaller report contract or complete the requested report dimensions and PDF export (QA-006).
4. Define account recovery and expose audit review if these are product commitments (QA-007, QA-008).
5. Ensure receipts show the actual seller (QA-009).

### P3 — Optional

1. Add deployment guardrails that explicitly prevent demo seeding and verify seed accounts are absent in production (QA-010).

## Manual demo script (mock M-Pesa only)

**Prerequisites:** local disposable PostgreSQL; API started with `MPESA_MODE=mock`; Flutter Android app pointed at the local API; seeded demo owner credentials or a newly registered business. Use the emulator host `http://10.0.2.2:3000` where appropriate. This script has not been executed as part of this audit.

1. Register a shop or log in as `owner@stockpesa.app` (`Demo1234!`) in local demo only.
2. Add a category and a product with a KES buying/selling price and minimum-stock threshold.
3. Open Stock → Receive, add opening units, and confirm the on-hand quantity and movement history.
4. Sell one unit for cash. Open the success/receipt view and confirm the total and amount paid.
5. Return to Products/Stock and confirm on-hand quantity decreased by one.
6. Save or share the receipt PDF. Verify business, sale number, product, quantity, KES totals, payment method, and footer.
7. Make an M-Pesa **mock** sale and confirm it through the mock flow. Explain that no manual receipt number or live STK request is supported in this V1.
8. Add/select a customer and make a credit sale. Open Customers and confirm their balance increased.
9. Record a partial customer payment; confirm sale balance and customer debt decreased.
10. Reduce a product to its low-stock threshold and open Alerts to show the warning.
11. Open Reports and review sales, payment method, customer debt, inventory values, and low-stock items.
12. Export the available CSV summary and inspect the saved file. Explain that report PDF export is not currently available.

## Release gate

Re-run this report’s blocked checks in an environment with writable Flutter tooling, JDK 17+, Docker/PostgreSQL, and an Android emulator or phone. Do not label StockPesa “READY FOR DEMO” until the release build installs and the transaction, role, tenant, payment, receipt, and offline journeys have been exercised end to end.

## Follow-up implementation status

The owner confirmed implementation on 15 November 2026. The prior findings above are preserved as the baseline audit; this section records code changes and retest limits.

| Finding | Code change | Retest status |
|---|---|---|
| QA-001 release signing | Release Gradle config now reads `mobile/android/key.properties`; release builds no longer use the debug key. Missing key properties leave release unsigned. | Static config reviewed. AAB signing/install not verified because Java is unavailable and no keystore was supplied. |
| QA-002 backend coverage | Added an opt-in PostgreSQL API integration suite for roles, tenant isolation, stock/sale idempotency, CSV retry, payments, M-Pesa, returns, balances, audit, and receipt seller name. | Not run: `DATABASE_URL_TEST` is unset and PostgreSQL/Docker are unavailable. The suite rejects URLs whose database name does not contain `test`. |
| QA-003 manual M-Pesa | `/sales` accepts `mpesaReceiptNumber` and amount for a settled manual MPESA payment. Partial payment requires a customer for the outstanding balance. A business-scoped advisory lock rejects reused receipt references. The app has manual/mock mode selection and persists retry input securely. | M-Pesa decision-helper unit tests pass. API/UI journey, duplicate reference, and callback behavior remain pending the integration environment. |
| QA-004 stock intake audit | Intake movement, buying-price update, and `stock.intake` audit row now share the same transaction. | Build passes; an assertion is included in the unrun API integration suite. |
| QA-005 CSV retry | Confirm derives an import identity from file bytes and skip-invalid behavior, serializes retries, records the result in the transaction audit row, and returns the original result on repeat. Caller idempotency keys are also supported and bound to the request hash. | Build passes; repeated CSV assertion is included in the unrun API integration suite. |
| QA-009 receipt cashier | Sale detail now returns the seller’s name from a business-scoped user lookup; receipt service uses that value. | Build and Dart static analysis pass; cross-user device/PDF check remains pending. |
| QA-006, QA-007, QA-008, QA-010 | No additional report dimensions/PDF export, password reset, audit viewer, or production seed tooling added in this pass. | Deferred as new scope or deployment process; see baseline findings. |

### After-change checks

- `cd backend && npm test`: exit 0; backend build and current Node test files pass.
- `cd backend && npx prisma validate`: pass.
- `cd mobile && dart analyze lib test`: exit 0, no errors; Dart SDK reports 38 informational lint suggestions.
- `cd mobile && flutter test`: blocked before test execution because Flutter tries to update engine files in the read-only SDK.
- `cd backend && npm run test:integration`: not run because `DATABASE_URL_TEST` is unset. It requires an isolated PostgreSQL database whose name contains `test`.
- Android release signing/build, HTTP E2E, physical-device QA, and mock callback integration remain unverified.

### Remaining acceptance gaps

The implementation addresses the audited code-level P1/P2 defects listed as changed above, but those runtime-dependent scenarios have not been retested. Report PDF export and additional report dimensions, password reset, a user-facing audit viewer, and full Android/device release validation remain outside the completed work. **Current verdict remains NOT READY until the blocked integration and device checks pass.**
