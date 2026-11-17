# StockPesa

[![NestJS](https://img.shields.io/badge/backend-NestJS%2010-ea2849.svg)](https://nestjs.com/)
[![Flutter](https://img.shields.io/badge/mobile-Flutter%203-02569B.svg)](https://flutter.dev/)
[![Prisma](https://img.shields.io/badge/ORM-Prisma%205-2D3748.svg)](https://www.prisma.io/)
[![PostgreSQL](https://img.shields.io/badge/database-PostgreSQL%2016-336791.svg)](https://www.postgresql.org/)
[![License](https://img.shields.io/badge/license-Proprietary-blue.svg)](#)

StockPesa is an Android-first inventory and sales management platform tailored for independent retailers and neighborhood shops in Kenya. It establishes a single transaction ledger linking on-hand inventory, stock movements, checkout, customer credit, returns, receipts, and management reporting through a multi-tenant backend API.

---

## Table of Contents

- [Overview & Architecture](#overview--architecture)
- [Repository Structure](#repository-structure)
- [Branching & Git Strategy](#branching--git-strategy)
- [Key Features](#key-features)
- [Quick Start & Local Development](#quick-start--local-development)
  - [Prerequisites](#prerequisites)
  - [Running with Docker Compose](#running-with-docker-compose)
  - [Running the Mobile App](#running-the-mobile-app)
- [Environment Configuration](#environment-configuration)
- [Database, Migrations & Seed Data](#database-migrations--seed-data)
- [API Architecture & Security](#api-architecture--security)
- [Testing & Quality Assurance](#testing--quality-assurance)
- [Documentation Index](#documentation-index)
- [Known Limitations & Roadmap](#known-limitations--roadmap)

---

## Overview & Architecture

Independent retailers often balance purchases, stock levels, daily sales, customer credit, and receipts across physical notebooks and messaging apps. StockPesa replaces fragmented bookkeeping with an atomic, auditable workflow designed for retail operations in Kenya (KES currency, barcode scanning, M-Pesa tracking, and credit sales).

```mermaid
flowchart LR
  M[Flutter Mobile App\nAndroid · Riverpod · GoRouter · Dio] -->|HTTPS / REST API| API[NestJS Backend API\nValidation · JWT · RBAC · Rate Limits]
  API --> DB[(PostgreSQL 16\nPrisma · NUMERIC Cents · Tenant Scoped)]
  API --> AUD[Audit Log & Stock Movement Ledger]
  API --> MP[M-Pesa Flow\nManual Recording & Mock Callback]
```

- **Frontend:** Flutter (Dart 3.10+), Riverpod state management, GoRouter, Dio HTTP client, Flutter Secure Storage, PDF receipt generation.
- **Backend:** NestJS, TypeScript, class-validator, Passport/JWT, bcrypt password hashing.
- **Database & Storage:** PostgreSQL 16, Prisma ORM with exact decimal (`NUMERIC`) currency storage, integer-cent financial arithmetic, and product-level PostgreSQL advisory locks.

---

## Repository Structure

```text
stockpesa/
├── backend/                  # NestJS API application
│   ├── prisma/               # Prisma schema, migrations, and seed script
│   ├── src/                  # Modular backend source code
│   │   ├── auth/             # Authentication & session management
│   │   ├── business/         # Business profile & tenant metadata
│   │   ├── catalog/          # Products, categories, barcode lookup & CSV import
│   │   ├── customers/        # Customer credit ledgers & debt tracking
│   │   ├── insights/         # Analytics, reporting & low-stock alerts
│   │   ├── payments/         # M-Pesa, card, cash payment handling
│   │   ├── sales/            # POS checkout, receipt snapshots & returns
│   │   └── stock/            # Intake, stock adjustments & audit records
│   └── test/                 # Integration & monetary calculation test suites
├── mobile/                   # Flutter Android & iOS application
│   ├── lib/                  # App shell, features, screens & routing
│   │   ├── app/              # App router & responsive shell
│   │   ├── core/             # Dio client, secure session store & theme
│   │   └── features/         # Feature repositories (products, sales, customers, stock)
│   └── test/                 # Widget and unit test suites
├── docs/                     # Specifications, QA checklists & pitch collateral
├── docker-compose.yml        # Local development stack (API + Postgres + Seed)
└── docker-compose.prod.yml   # Production deployment template
```

---

## Branching & Git Strategy

The project follows a modular git workflow with specialized branches pushed to the remote repository (`git@github.com:abdalla-dev453/stockpesa.git`):

| Branch                       | Description                                                                                |
| ---------------------------- | ------------------------------------------------------------------------------------------ |
| `chore/stockpesa-bootstrap`  | Initial repository baseline, ignore rules, and scaffolding                                 |
| `feature/backend-platform`   | NestJS framework, Prisma ORM, database migrations, and Docker Compose configurations       |
| `feature/backend-domain`     | Core API domains: auth, catalog, stock movement ledger, checkout, customers, and reporting |
| `feature/flutter-foundation` | Flutter mobile foundation, theme, routing, API client, and secure session management       |
| `feature/flutter-workflows`  | End-to-end mobile screens: checkout, stock adjustments, customer debt, and receipts        |
| `docs/release-readiness`     | Release readiness audit, QA checklists, integration suites, and deployment collateral      |

---

## Key Features

- **Multi-Tenant Staff RBAC:** Dedicated Owner, Manager, Cashier, and Storekeeper roles with strict endpoint authorization guards.
- **Catalogue & Inventory Control:** Product and category management, barcode search, paginated product browsing, and CSV bulk import with dry-run preview and idempotent execution.
- **V2 Phase A Product Power:** Product variants with separate stock ledgers, component bundles, unit conversion rules, image URL metadata, business tags, promotional prices, product status, and price history. Existing product and sale records remain readable.
- **Stock Movement Ledger:** Audited stock intake, negative stock protection, manager override audit logs, stock counts, and automated low-stock / out-of-stock alerts.
- **Point of Sale (POS) & Checkout:** Instant cash, bank transfer, card, customer credit, M-Pesa mock flow, and manual M-Pesa receipt verification with idempotency keys.
- **Customer Credit & Debt Ledger:** Customer balances, per-customer credit limits, debt repayment tracking, and balance-bounded partial payments.
- **Returns & Restocking:** Full and partial item returns with optional return-to-stock re-entry and atomic sale balance updates.
- **Receipts & Reports:** Printable and shareable PDF receipts with tenant snapshots, daily sales summaries, stock movement reports, and CSV report export.
- **Resilient Mobile UX:** Secure JWT persistence with auto-refresh, offline cart preservation, and strict no-offline-queue integrity guarantees.

---

## Quick Start & Local Development

### Prerequisites

- **Node.js:** 22.22+ and npm
- **Docker & Docker Compose:** for containerized PostgreSQL and API
- **Flutter SDK:** 3.10+ (matching `pubspec.lock`)
- **JDK:** Java 17+ (for Android builds)

### Running with Docker Compose

The simplest way to start the database and API with demo seed data is via Docker Compose:

1. Clone the repository and configure the environment:

   ```bash
   cp backend/.env.example backend/.env
   ```

2. Spin up the API, PostgreSQL database, and seed data:

   ```bash
   docker compose up --build
   ```

   - API Base URL: `http://localhost:3000`
   - Health Check: `http://localhost:3000/health`
   - Interactive Swagger API Docs: `http://localhost:3000/docs`

### Running the Mobile App

1. Navigate to the mobile directory and install dependencies:

   ```bash
   cd mobile
   flutter pub get
   ```

2. Launch on an Android Emulator:
   ```bash
   flutter run --dart-define=API=http://10.0.2.2:3000
   ```
   _(For an iOS Simulator use `http://localhost:3000`; for physical devices, provide your workstation's LAN IP address)._

---

## Environment Configuration

- **`backend/.env.example`**: Documents local development settings (`DATABASE_URL`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `ACCESS_TTL`, `REFRESH_TTL`, `ADJUSTMENT_NOTE_THRESHOLD`, `MPESA_MODE`, `MPESA_CALLBACK_SECRET`, `CORS_ORIGINS`, `TRUST_PROXY_HOPS`).
- **`backend/.env.production.example`**: Template for production infrastructure. Requires strong random secrets from a secrets manager, a TLS database connection, strict `CORS_ORIGINS`, `NODE_ENV=production`, `MPESA_MODE=disabled`, and Swagger disabled by default.
- **`mobile/.env.example`**: Documents Flutter client build-time defines (`API=http://10.0.2.2:3000`).

---

## Database, Migrations & Seed Data

The Prisma migration history is located in `backend/prisma/migrations`.

### Production Migrations

For production deployment, apply migrations using:

```bash
docker compose -f docker-compose.prod.yml run --rm --entrypoint /app/node_modules/.bin/prisma api migrate deploy
```

### Seed Credentials (Local Demo Only)

Local development automatically seeds demo accounts with the password `Demo1234!`:

| Role            | Email                   |
| --------------- | ----------------------- |
| **Owner**       | `owner@stockpesa.app`   |
| **Manager**     | `manager@stockpesa.app` |
| **Cashier**     | `cashier@stockpesa.app` |
| **Storekeeper** | `store@stockpesa.app`   |

_Note: Demo credentials and sample seed data are strictly for local and staging environments._

---

## API Architecture & Security

- **Strict Multi-Tenancy:** Every mutation and query is scoped by the caller's verified `businessId`.
- **Role-Based Access Control:** Handled by NestJS guards enforcing least-privilege permissions.
- **Financial Precision:** All currency figures are stored as PostgreSQL `NUMERIC` and handled in integer cents to eliminate floating-point rounding errors.
- **Concurrency & Idempotency:** Mutations (intake, adjustments, checkout, CSV import) utilize unique `Idempotency-Key` headers and product-level PostgreSQL advisory locks.
- **Audit Trails:** Sensitive changes (stock modifications, sales, returns, staff management, CSV exports) create immutable audit log rows within the database transaction.

---

## Testing & Quality Assurance

Run the test and verification suites across the backend and mobile apps:

```bash
# 1. Backend build & unit/monetary tests
cd backend && npm test

# 2. Backend PostgreSQL integration suite (requires disposable database with 'test' in name)
DATABASE_URL_TEST=postgresql://stockpesa:stockpesa@localhost:5432/stockpesa_test npm run test:integration

# 3. Mobile static code analysis
cd mobile && dart analyze lib test

# 4. Mobile unit & widget tests
cd mobile && flutter test

# 5. Mobile production release build (Android App Bundle)
cd mobile && flutter build appbundle --release --dart-define=API=https://api.yourdomain.com
```

---

## Documentation Index

Comprehensive guides, specifications, and collateral are located in `docs/` and `mobile/`:

| Document                                                       | Purpose                                                                       |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| [Phase 2 API & Manual Tests](docs/PHASE2.md)                   | Endpoint catalog, role matrices, curl examples, and stock intake tests        |
| [Phase 3 Manual E2E Guide](docs/phase-3-manual-e2e.md)         | End-to-end sales, returns, customer credit, M-Pesa, and idempotency checks    |
| [Phase 6 QA Release Checklist](docs/phase6-qa-checklist.md)    | Pre-release verification checklist across backend, mobile, and security       |
| [QA Audit Report](docs/qa-audit-report.md)                     | Complete baseline audit findings, security observations, and follow-up status |
| [Five-Minute Demo Script](docs/demo-script.md)                 | Step-by-step walkthrough script for live merchant demonstrations              |
| [Deployment & Release Checklist](docs/deployment-checklist.md) | Production hardening, release engineering, and Google Play listing draft      |
| [V1.1 Quality & Trust Audit](docs/v1.1-quality-trust-audit.md) | Current baseline, priority order, measurement targets, and notification architecture |
| [Privacy Policy Template](docs/privacy-policy-template.md) | Plain-English privacy draft requiring operator completion and Kenyan legal review |
| [Terms Template](docs/terms-and-conditions-template.md) | Service terms draft requiring operator completion and Kenyan legal review |
| [V1.1 Manual QA](docs/v1.1-manual-qa.md) | Category, theme, consent, regression, push and release-gate checklist |
| [V1.1 Release Notes](docs/v1.1-release-notes.md) | Implemented slice and remaining environment-dependent release work |
| [V1.1 Security Checklist](docs/v1.1-security-compliance-checklist.md) | Deployment security checks and Kenya privacy review items |
| [V2 Phase A Product Power](docs/v2-phase-a-product-power.md) | Phase A schema, API contract, Flutter workflows, verification and demo script |
| [Investor One-Pager](docs/investor-one-pager.md)               | Market opportunity, problem/solution overview, and commercial model           |
| [Mobile Client Guide](mobile/README.md)                        | Flutter application architecture, screen routing map, and mobile test guide   |

---

## Known Limitations & Roadmap

### Current Scope & Known Limitations

- **M-Pesa Integration:** Supports manual receipt recording and demo mock callbacks; live Daraja STK Push integration is slated for subsequent releases.
- **Offline Mode:** Unsaved carts persist locally, but offline checkout queuing is intentionally disabled to avoid inventory divergence.
- **Single Branch:** Designed for single-shop operations with unified stock and staff.

### V1.1 Roadmap

1. Live Daraja STK Push integration with automated payment reconciliation.
2. Accountant-ready PDF and Excel report exports.
3. Merchant-requested reporting intervals and tax configuration.
4. Multi-location / multi-branch stock transfers and consolidated analytics.
