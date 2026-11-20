# StockPesa — Product Catalogue Redesign: Manual QA Checklist

Scope: Products screen, ProductCard, Product Details, image handling, category chips, filter/sort, seed data, backend image endpoints.
Test account (local demo): `owner@stockpesa.app` / `Demo1234!` (owner), `manager@stockpesa.app` (manager), `cashier@stockpesa.app` (cashier).

## 1. Products screen layout
- [ ] Screen title reads "Products".
- [ ] Header contains: search bar, barcode scan button, filter/sort button, Add Product FAB.
- [ ] Category chips render horizontally scrollable: All, Groceries, Drinks & Beverages, Household Items, Personal Care, Snacks, Cooking Essentials, Hardware, Stationery, Other, user-created categories.
- [ ] "All" chip selected by default and visually highlighted.
- [ ] Tapping a category chip filters the grid; product count shown beside category name where practical.
- [ ] Products render in a responsive image-first grid: 2 columns on phones, 3 on wider tablets.
- [ ] Grid uses `GridView.builder` (visible children only).
- [ ] Infinite scroll / pagination works: scrolling near the bottom loads the next page.
- [ ] Pull-to-refresh reloads the product list.
- [ ] Skeleton loading cards shown while the first page loads.
- [ ] Empty state shown when no products match: "No products found. Add your first product or change filters." with an "Add your first product" button.
- [ ] Error state shown on failure with a "Try again" retry button.
- [ ] Tapping the Add Product FAB opens the create flow and the new product appears in the grid after save.
- [ ] Scroll position and selected filters/category are preserved when navigating back from Product Details.

## 2. Product card (ProductCard)
- [ ] Every card shows: product image (top, 4:5 aspect ratio, BoxFit.cover, rounded top corners), name (max 2 lines, ellipsis), category (small muted), selling price in KES (bold), stock quantity + unit (e.g. "24 pcs"), stock-status chip.
- [ ] Stock-status chip colours: In Stock = green, Low Stock = amber, Out of Stock = red.
- [ ] Discount ("Sale") badge shown when a promotional price exists and is below the selling price.
- [ ] "Fast Moving" / "New" badge shown when the corresponding tag exists.
- [ ] Placeholder shown while the image loads; friendly fallback icon shown if the image fails to load; a broken URL never crashes the card.
- [ ] Card looks correct with and without an image.
- [ ] Card background white, rounded corners 16dp, subtle shadow, 12–16dp internal spacing, clean typography, no text overflow.
- [ ] Tapping the card body opens Product Details.
- [ ] "Add to cart" quick-add button adds 1 × product to the active sale cart (shows confirmation snackbar).
- [ ] Long-press / overflow menu offers: Edit product, Receive stock, Adjust stock, View stock movements, Archive product.
- [ ] Archive menu item hidden/disabled for cashier and storekeeper (owner/manager only).

## 3. Category chips & filtering
- [ ] Selecting "All" shows every product.
- [ ] Selecting a named category filters the grid to that category only.
- [ ] User-created categories (added via /categories) appear as chips.
- [ ] Changing category then navigating to details and back keeps the category filter applied.

## 4. Search
- [ ] Search by product name, SKU, or barcode filters the grid.
- [ ] Search input is debounced (~300 ms) — no request per keystroke.
- [ ] Clearing search returns to the full list.
- [ ] Barcode scan button opens the scanner; scanning a known barcode filters/shows the product; scanning an unknown barcode offers to create a product prefilled with the barcode.

## 5. Filter & sort bottom sheet
- [ ] Opening filter/sort shows: Stock status (All/In Stock/Low Stock/Out of Stock), Category, Brand (optional), Price range min/max (optional), Sort by options.
- [ ] Stock status filter correctly shows only matching products (e.g. Out of Stock shows qty = 0 items).
- [ ] Price range filter excludes products outside the range.
- [ ] Sort options work: Name A–Z, Name Z–A, Price low→high, Price high→low, Stock low→high, Recently added, Best selling.
- [ ] Reset filters clears category, stock status, brand, and price range.
- [ ] Apply applies filters and returns to the grid; Cancel discards.

## 6. Product Details
- [ ] Large hero product image shown at top (with rounded bottom corners).
- [ ] Image gallery thumbnail strip shown when multiple images exist; tapping a thumbnail switches the hero image.
- [ ] Product name, category, brand, SKU, barcode, description, unit shown.
- [ ] Buying price, selling price, wholesale price, current stock, minimum stock level, stock status shown.
- [ ] Stock value (qty × buying) and retail value (qty × selling) shown.
- [ ] Stock-status chip matches the card (green/amber/red).
- [ ] Stock movement history shown (most recent first), empty state when none.
- [ ] Variants shown (if any) with name, code, price, quantity.
- [ ] Action buttons: Sell (disabled when out of stock), Receive Stock, Adjust Stock, Edit Product.
- [ ] "Add image URL" and "Upload photo" add images; new images appear in the gallery.
- [ ] Tapping Edit Product opens the editor; saving returns to details with updated values.

## 7. Product creation / editing with image
- [ ] Create product form accepts optional image upload (JPEG/PNG/WEBP).
- [ ] Uploaded image is set as the main product image and appears in the grid/details.
- [ ] Editor shows current main image, allows changing the main image URL or uploading a replacement photo.
- [ ] Editor allows adding/removing additional images.
- [ ] Product create/patch accepts `imageUrl` (secure https URL) and stores it.
- [ ] Deleting the main image falls back to the next additional image or clears it.

## 8. Image handling
- [ ] Images are loaded with `cached_network_image` and cached across screen visits.
- [ ] Images are resized (~800 px) to avoid memory issues.
- [ ] Common formats supported: JPG, PNG, WEBP.
- [ ] Invalid/missing image URLs handled gracefully (fallback icon, no crash).
- [ ] Uploaded files validated: image/jpeg, image/png, image/webp only; max 5 MB; magic-byte signature checked.
- [ ] Image URLs stored securely; tenant ownership enforced (businessId scoping).

## 9. Seed data
- [ ] Seed creates 46 products across: Groceries, Drinks & Beverages, Cooking Essentials, Snacks, Household Items, Cleaning Products, Personal Care, Baby Products, Hardware, Stationery.
- [ ] Every seeded product has a working `imageUrl` (~800×800 Unsplash CDN URL).
- [ ] Every seeded product shows an image in the grid (placeholder → image, fallback only if a source URL dies).
- [ ] Seed is idempotent (rerunning does not duplicate products/users).

## 10. Backend
- [ ] `GET /products` returns `imageUrl` and the `images` array.
- [ ] `POST /products/:id/images`, `DELETE /products/:id/images/:imageId`, `POST /products/:id/images/upload`, `PATCH /products/:id/main-image` all return 200/201 for owner/manager and 403 for cashier/storekeeper.
- [ ] `imageUrl` accepted on product create and patch.
- [ ] Non-https image URLs rejected with 400.
- [ ] Tenant ownership enforced on all image endpoints (404 for other tenant's product/image).
- [ ] Image upload rejects files > 5 MB with 400.
- [ ] Image upload rejects non-JPEG/PNG/WEBP MIME types with 400.
- [ ] Image upload rejects files with invalid magic bytes (not a real image) with 400.
- [ ] `GET /dashboard/board` returns 200 even when `DashboardPreference` table is not provisioned.
- [ ] `GET /products/:id/movements` returns 200.

## 11. Code quality
- [ ] `dart analyze lib` reports zero errors (deprecated `withOpacity` → `withValues`, `initialValue` → controller, `groupValue` → `RadioGroup` resolved).
- [ ] Backend `tsc --noEmit` reports zero errors.
- [ ] `flutter test` — all tests pass.
- [ ] `npm test` — all backend tests pass.

## 12. Regression (existing features must still work)
- [ ] Product creation, editing, archiving.
- [ ] Stock intake, adjustment, movements, counts.
- [ ] Barcode scanning and lookup.
- [ ] CSV import preview/confirm.
- [ ] Sales/checkout (cash, M-Pesa, bank, card, credit), returns, receipts.
- [ ] Customers, dashboard, reports, alerts.

## Environment
- Backend: `docker-compose up --build` (required — provides Postgres on port 5432 and API on port 3000). Then `npm run prisma:seed` (or seed runs automatically with `SEED_DEMO=true`).
- Mobile: `flutter run --dart-define=API=http://10.0.2.2:3000` (Android emulator) — requires a device/emulator; cannot run on headless Linux without a browser.
- Checks: `dart analyze lib test`, `flutter test`, `npm run build` + `npm test`.
