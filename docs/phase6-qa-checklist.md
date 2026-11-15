# StockPesa V1 QA checklist

Use a local development database with demo data. Do not run destructive checks against production. For transaction/idempotency checks, use API requests with a stable `Idempotency-Key` and compare database rows before and after.

## End-to-end merchant flow

- [ ] Start PostgreSQL and the API using `docker compose up --build`; confirm `/health` returns `{"status":"ok","database":"ok"}`.
- [ ] Register a business using a valid email and Kenyan mobile number. Try invalid email, invalid mobile number, short password, blank business name, and unchecked terms; confirm each is rejected before submission.
- [ ] Sign out, sign in with email and with phone, and confirm the same business data appears.
- [ ] Create a category and product. Try negative prices, too many decimal places, blank name, duplicate SKU/barcode, and a category belonging to another business.
- [ ] Preview a valid CSV. Preview malformed quotes, duplicate headers, mismatched column counts, invalid units, negative values, and prices/quantities with excess decimals; confirm bad rows are identified and not silently imported. Confirm opening stock creates a `purchase_in` movement.
- [ ] Confirm a CSV containing rows without SKU/barcode twice; the second identical confirmation must return the original result without creating duplicate products. Reuse a caller idempotency key with changed content and confirm conflict.
- [ ] Receive stock and adjust stock. Confirm each quantity change has exactly one movement and a same-transaction `stock.intake` / `stock.adjust` audit row. Try a large negative adjustment without notes and confirm it is rejected.
- [ ] Complete a stock count, including a positive adjustment and a negative adjustment. Try completion with an uncounted item and a second completion; confirm it is rejected. Confirm `stock_count.completed` and stock movements are present.
- [ ] Scan a known barcode and search by name/SKU. Create a product from an unknown barcode. Confirm search/status filters and page counts stay consistent.
- [ ] Make a cash sale. Verify sale, sale items, stock movement, payment, receipt snapshot, and audit record exist; stock decreases once. Retry the same API payload and idempotency key and confirm the original sale is returned. Reuse that key with a changed payload and confirm conflict.
- [ ] Record a manual M-Pesa payment by entering a receipt and amount. Confirm a partial amount updates sale/customer balance, receipt reference, and audit; retry the same receipt on another sale and confirm rejection.
- [ ] Make an M-Pesa sale with `MPESA_MODE=mock`. Confirm it begins pending, the mock endpoint settles it once, and replaying the callback does not double count. Try an invalid signature and confirm rejection.
- [ ] Make a credit sale for a customer. Confirm sale balance and customer balance agree and remain within credit limit. Try a sale above the limit and confirm no partial sale, movement, payment, receipt, or audit record remains.
- [ ] Open the receipt preview, share the PDF, and verify business, sale number/date, items, quantities, discount, totals, payment status, customer, and footer match the API snapshot.
- [ ] View a cashier-created receipt while signed in as owner and confirm the PDF shows the actual cashier name.
- [ ] Record a customer payment. Confirm amount and method, sale balance, customer balance, receipt, and audit record update. Try paying above either outstanding amount and race two payments; confirm neither sale nor customer balance becomes negative.
- [ ] Return part of a sale with restocking on. Confirm quantity, refund, balance, `RETURN_IN` movement, payment record, and audit are correct. Repeat without restocking and confirm no stock movement. Try returning more than remaining quantity and replay the idempotent request.
- [ ] As cashier, confirm the return action is hidden and the endpoint returns 403. As manager, confirm it is available.
- [ ] Trigger low-stock and out-of-stock conditions. Confirm alerts, unread badge, filters, mark-read behavior, and product navigation.
- [ ] Check dashboard and reports against database/API totals for the same period. Export CSV as owner and manager; verify values, formula-safe text cells, saved file contents, and `report.exported` audit row. Confirm cashier cannot read detailed reports or export.
- [ ] As owner, create a manager/cashier/storekeeper, change a role, update a staff account, and deactivate it. Confirm each action is audited and deactivated staff cannot refresh or use an existing access token. Confirm manager cannot administer staff.
- [ ] Change business profile and confirm the audit record and next receipt reflect the profile. Confirm the owner cannot grant another user OWNER role.
- [ ] Create a second business. Try using its product, customer, sale, movement, alert, and staff IDs with the first business token; confirm all API requests fail without disclosing records.
- [ ] Sign out, confirm local tokens and saved carts are removed, sign in again, and confirm the correct business session restores. Expire the access token and confirm safe GET refresh; confirm a failed mutation is not automatically replayed.
- [ ] Disable network. Confirm offline status, saved cart messaging, and disabled checkout; reconnect and refresh.

## Release checks

- [ ] `cd backend && npm test`
- [ ] `cd mobile && flutter analyze`
- [ ] `cd mobile && flutter test`
- [ ] `cd mobile && flutter build appbundle --release --dart-define=API=https://YOUR_API_HOST`
- [ ] Install the signed build on at least one supported Android phone and check login, scan camera permission, PDF share/save, keyboard layout, rotation, and dark mode.
- [ ] Run production configuration checks with missing/short JWT secrets, wildcard/missing CORS, mock M-Pesa, and Swagger disabled. Unsafe settings must prevent startup or payment processing.
