# Deployment readiness checklist

Production is **not deployed by this repository**. The production Compose file is a template and requires a managed database, real secrets, a TLS proxy, and an operator-reviewed migration.

## Environment and database

1. Create a production PostgreSQL database with TLS, private networking, least-privilege credentials, automated backups, and point-in-time recovery if available.
2. Copy `backend/.env.production.example` to a deployment secret store. Set unique random `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, and `MPESA_CALLBACK_SECRET` values (at least 32 characters), exact `CORS_ORIGINS`, managed `DATABASE_URL`, `NODE_ENV=production`, and `MPESA_MODE=disabled` until a provider is integrated.
3. Do not use `docker-compose.yml` in production. It is the local development setup and enables demo seeding. Never expose demo accounts publicly.
4. Review the checked-in initial Prisma migration against the target database. For a new database, apply it with the production image before starting the API:

   ```sh
   docker compose -f docker-compose.prod.yml build api
   docker compose -f docker-compose.prod.yml run --rm --entrypoint /app/node_modules/.bin/prisma api migrate deploy
   docker compose -f docker-compose.prod.yml up -d api
   ```

   Existing databases created with `prisma db push` need a reviewed baseline procedure before `migrate deploy`; do not run the initial migration over existing tables. Back up and rehearse first.

5. Confirm `GET /health` succeeds from the trusted network. Swagger is disabled in production unless explicitly enabled.

## Operations and recovery

- **Backup:** schedule encrypted `pg_dump -Fc` backups to private object storage at least daily; retain a short daily window and longer weekly/monthly copies according to business recovery needs. Test restore into an isolated database monthly. Store encryption keys separately from backup files.
- **Logging:** API logs go to stdout/stderr. Collect them centrally with access control and retention; alert on sustained 5xx, 429 spikes, database connection failures, and restart loops. Query strings and request bodies are not logged.
- **Monitoring:** `/health` checks database connectivity. Error monitoring (for example Sentry/OpenTelemetry) is not integrated yet; add DSN/collector secrets only after privacy, retention, and sampling review.
- **Rate limits:** built-in login/register/refresh/callback limits are per API process. Put a shared limit at the ingress/gateway for horizontally scaled deployments.
- **TLS/proxy:** terminate TLS at a maintained reverse proxy/load balancer. Configure `TRUST_PROXY_HOPS` only to the exact number of trusted proxy hops. Keep port 3000 private.
- **Secrets:** use a secret manager or orchestrator secrets, rotate credentials, and never put production secrets in `.env`, Compose files, frontend defines, or logs.
- **M-Pesa:** production mock mode is disabled. Live Daraja/STK support, provider credential rotation, webhook onboarding, reconciliation, and settlement monitoring are not part of this V1.

## CI/CD outline

1. On pull request: install from lockfiles, run `npm test`, `flutter analyze`, and `flutter test`; validate Prisma schema and Compose configuration.
2. Build backend and Android release artifacts once, tag with commit SHA, scan dependencies/container, and retain build provenance.
3. Deploy to staging; run migrations as a reviewed one-off job and execute the Phase 6 QA checklist with seeded staging data.
4. Require a human release approval. Back up production before migrations; deploy API with health checks and rollback instructions.
5. Distribute Android through internal testing first. Publish to Play only after signing, privacy/data-safety declarations, support contacts, and screenshots are approved.

No CI workflow or error-monitoring integration is configured in this repository yet.

## Android release build

1. Install the Flutter SDK required by `mobile/pubspec.lock` and JDK 17 or newer.
2. Create an upload keystore outside the repository. Put its absolute path and passwords in ignored `mobile/android/key.properties`; `.gitignore` excludes this file. The release build is unsigned when this file is absent and never falls back to the debug key.
3. Use this local-only properties shape in `mobile/android/key.properties`; keep the file and keystore out of version control:

   ```properties
   storeFile=/absolute/path/to/stockpesa-upload.jks
   storePassword=...
   keyAlias=stockpesa
   keyPassword=...
   ```

   CI should inject equivalent values from its secret store. Do not hardcode passwords.
4. Supply the HTTPS production API URL and build:

   ```sh
   cd mobile
   flutter pub get
   flutter analyze
   flutter test
   flutter build appbundle --release --dart-define=API=https://api.example.com
   ```

5. Verify the AAB signature, install from an internal track, test login, camera, receipts, offline banner, and permissions, then promote through staged rollout. Keep the upload key and Play credentials backed up securely.

The current project has a custom StockPesa icon/splash, but the release signing configuration and production backend URL must still be supplied by the operator.

## Store listing draft

- **App name:** StockPesa – Shop Stock & Sales
- **Short description:** Track stock, record sales, and manage customer balances.
- **Full description:** StockPesa helps small retailers keep a clear record of products, stock received, stock adjustments, sales, receipts, and customer credit. Search or scan products at checkout, review low-stock alerts, manage staff access, and export business reports. Requires an internet connection to record sales. M-Pesa support in the current V1 is a demonstration mode only; live payments are not enabled.
- **Keywords:** stock management, inventory, shop sales, retail, receipts, customer credit, Kenya, biashara
- **Screenshots plan:** Dashboard with stock summary; product list and barcode scan; cart/payment; receipt preview; customer debt/payment; alerts and reports. Use synthetic demo data only and hide personal information.
- **Before publishing:** confirm final name/trademark, support email/site, privacy policy, data safety form, age rating, screenshots, test-device coverage, Play signing, and live-payment claims.
