# StockPesa

StockPesa is an Android-first inventory and sales app for small retailers. It links product stock, stock movements, checkout, receipts, customer credit, returns, alerts, and reports through a tenant-scoped API.

## V1 features

- Business and staff accounts with owner, manager, cashier, and storekeeper roles.
- Product/category management, barcode lookup, paginated search, and CSV catalogue import.
- Stock intake, adjustments, stock counts, movement history, and low-stock alerts.
- Cash, bank, card, credit, M-Pesa mock checkout, and manual M-Pesa receipt recording with idempotency and transaction records.
- Customer accounts, payments against credit sales, returns, receipt snapshots, printable/shareable PDFs, and report CSV export.
- Dashboard and sales, product, stock, and debt reports.
- Secure mobile token storage, cart recovery while offline, and explicit no-offline-sale-queue behavior.

## Architecture

```mermaid
flowchart LR
  M[Flutter Android app\nRiverpod · GoRouter · Dio] -->|HTTPS / JSON| API[NestJS API\nValidation · JWT · Roles · Rate limits]
  API --> DB[(PostgreSQL\nPrisma · NUMERIC money · tenant IDs)]
  API --> AUD[Audit log and stock ledger]
  API --> MP[M-Pesa mock callback path]
```

**Stack:** Flutter/Dart 3.10+, NestJS/TypeScript, Prisma, PostgreSQL 16, Docker Compose for local development.

## Local development

Requirements: Node.js 22.22+, Docker Compose, Flutter/Dart matching the lockfile, and JDK 17+ for Android builds.

1. Create the local API environment file:

   ```sh
   cp backend/.env.example backend/.env
   ```

2. Start PostgreSQL/API and seeded development data:

   ```sh
   docker compose up --build
   ```

   API: `http://localhost:3000`; health: `/health`; Swagger: `/docs`.

3. Run the Flutter app:

   ```sh
   cd mobile
   flutter pub get
   flutter run --dart-define=API=http://10.0.2.2:3000
   ```

   Android emulator uses `10.0.2.2` to reach the host. iOS Simulator uses `http://localhost:3000`; a physical phone uses the development computer's LAN IP. Native mobile requests do not use browser CORS. Production builds must use HTTPS.

## Environment variables

`backend/.env.example` documents local variables: `DATABASE_URL`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `ACCESS_TTL`, `REFRESH_TTL`, `ADJUSTMENT_NOTE_THRESHOLD`, `MPESA_MODE`, `MPESA_CALLBACK_SECRET`, `CORS_ORIGINS`, and `TRUST_PROXY_HOPS`.

`backend/.env.production.example` is a template only. Supply unique random secrets from a secret manager, a TLS database URL, exact `CORS_ORIGINS`, `NODE_ENV=production`, `MPESA_MODE=disabled`, and the trusted proxy hop count. Production startup rejects placeholder/short secrets and missing or wildcard CORS origins. Do not commit `.env` files or put credentials in Flutter build defines.

## Database and seed data

The checked-in initial migration is in `backend/prisma/migrations`. For an empty production database, review and apply it before launching the API:

```sh
docker compose -f docker-compose.prod.yml build api
docker compose -f docker-compose.prod.yml run --rm --entrypoint /app/node_modules/.bin/prisma api migrate deploy
docker compose -f docker-compose.prod.yml up -d api
```

The local Compose stack uses `prisma db push` and seeds only because it explicitly sets `SEED_DEMO=true`. Never run the local Compose configuration on production. An existing database created using `db push` needs a reviewed Prisma migration baseline; do not apply the initial migration to existing tables without a backup and rehearsed baseline plan.

Seeded local accounts use `Demo1234!`:

- Owner: `owner@stockpesa.app`
- Manager: `manager@stockpesa.app`
- Cashier: `cashier@stockpesa.app`
- Storekeeper: `store@stockpesa.app`

Demo credentials and sample data are for local/staging demonstrations only.

## API documentation and security

Local Swagger documentation is available at `/docs`. Production disables Swagger by default. The API applies validation/whitelisting, role checks, business-scoped database queries, security headers, bounded JSON bodies, and per-process rate limits to login/register/refresh/M-Pesa callback endpoints. The production Compose file is only a deployment template; place it behind TLS and apply a shared gateway limit before scaling horizontally.

Sensitive stock, sale, return, staff, business-profile, and report-export actions write audit records in their transaction. Stock changes use a movement ledger. Money is persisted in PostgreSQL `NUMERIC` columns; checkout, returns, and customer payment decisions use integer-cent arithmetic.

## Checks and QA

```sh
cd backend && npm test
cd mobile && flutter analyze
cd mobile && flutter test
cd mobile && flutter build appbundle --release --dart-define=API=https://YOUR_API_HOST
```

Backend tests compile the API and exercise monetary rounding and M-Pesa checkout rules. A PostgreSQL-backed integration suite covers tenant boundaries, role denial, stock and sale idempotency, CSV retry safety, manual/mock M-Pesa, customer payments, returns, and audit entries. Run it only against a disposable database named with `test` in its name:

```sh
cd backend
DATABASE_URL_TEST=postgresql://stockpesa:stockpesa@localhost:5432/stockpesa_test npx prisma db push
DATABASE_URL_TEST=postgresql://stockpesa:stockpesa@localhost:5432/stockpesa_test npm run test:integration
```

Database-backed authorization and transaction scenarios are also listed in [docs/phase6-qa-checklist.md](docs/phase6-qa-checklist.md); run them before release. Mobile unit/widget tests cover money/date formatting, checkout math, Kenyan phone/email validation, and auth-screen rendering. Device journeys still require an Android emulator or phone.

## Demo and delivery docs

- [Five-minute demo script](docs/demo-script.md)
- [Investor one-pager](docs/investor-one-pager.md)
- [Deployment checklist, release instructions, and store-listing draft](docs/deployment-checklist.md)
- [Flutter routes, API mapping, and mobile manual tests](mobile/README.md)

## Known limitations

- M-Pesa supports manual receipt recording and a demo mock callback. There is no live Daraja STK Push/provider settlement integration.
- Sales cannot be recorded offline; saved carts are not queued for later synchronization.
- Tax calculation/configuration, product image upload, password reset, custom return permissions, and staff reactivation are not supported by current API routes.
- Return refund method follows the original payment behavior; there is no refund-method selector.
- Rate limits are in-process. Production needs a gateway/shared limit for multiple API replicas.
- Error-monitoring integration and CI/CD workflows are not configured. Database backup, restore, TLS, secrets, Play signing, and rollout remain deployment operator responsibilities.
- Product performance and report values depend on correct shop data and should be verified during a controlled pilot.

## V1.1 roadmap

Prioritize from pilot evidence: live M-Pesa integration with reconciliation and callback testing; operational error monitoring and shared rate limiting; accountant-friendly exports and merchant-requested report ranges; reduced onboarding friction; and additional localization. Multi-branch workflows should follow only after single-shop usage and retention are validated.
