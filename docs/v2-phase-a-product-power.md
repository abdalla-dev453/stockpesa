# StockPesa V2 Phase A: Product power

Phase A extends the V1 product catalogue while keeping existing product IDs and sale history intact. Every path below is available under `/api/v1`; the existing unversioned route remains a compatibility alias.

## Data changes

- `Product` gains status, promotional price/date range, and expiry/batch tracking flags.
- `ProductVariant` stores a sellable option's attributes, identifiers, prices, threshold, and independent quantity.
- `VariantStockMovement` records receipts and sales for variants. Variant sale rows retain the parent `productId` and also save `variantId`.
- `ProductBundle` and `BundleItem` define bundle contents. Bundle sales deduct each component within the sale transaction; bundles cannot contain other bundles.
- `UnitConversion` stores business or product scoped positive conversions between compatible units.
- `ProductImage`, `ProductTag`, `ProductTagAssignment`, and `ProductPriceHistory` provide image metadata, tags, and append-only price snapshots.
- All tenant-owned rows include `businessId`; monetary and quantity columns use PostgreSQL `NUMERIC`.

The migration is additive. Existing products remain non-variant sellable products until variants are added. Once a product has active variants, checkout requires a variant selection. Bundle parents use their set bundle price, while component stock is the inventory source.

## API

| Method | Path | Role | Behavior |
|---|---|---|---|
| `GET/POST` | `/products/:id/variants` | Read / owner or manager | List and create variants |
| `GET/PATCH/DELETE` | `/product-variants/:id` | Read / owner or manager | Read, edit, or archive a variant |
| `POST` | `/product-variants/:id/stock` | Owner, manager, storekeeper | Receive variant stock; supports `Idempotency-Key` |
| `GET` | `/product-variants/:id/movements` | Authenticated staff | Read latest variant movements |
| `GET` | `/products/:id/price-history` | Authenticated staff | Read up to 100 price snapshots |
| `GET/PUT` | `/products/:id/bundle` | Read / owner or manager | Read or replace bundle components |
| `GET/POST` | `/unit-conversions` | Read / owner or manager | List or create compatible conversions |
| `GET/POST` | `/products/:id/images` | Read / owner or manager | Store image URL metadata |
| `DELETE` | `/products/:id/images/:imageId` | Owner or manager | Remove image metadata |
| `GET` | `/product-tags` | Authenticated staff | List this business's tags |
| `PUT` | `/products/:id/tags` | Owner or manager | Replace a product's tags with up to 20 names |
| `PATCH` | `/products/:id` | Owner or manager | Change status and promotional pricing; price changes are recorded |
| `POST` | `/sales` | Owner, manager, cashier | Each item accepts exactly one of `productId` or `variantId`; active promotions apply automatically |

Product search and existing pagination continue on `/products`. Barcode and SKU lookup now checks variants as well as products.

The product list also accepts `brand`, `tag`, `status`, `priceMin`, and `priceMax` filters in addition to its existing `search`, `categoryId`, and `stockStatus` parameters.

### Example variant sale

```json
{
  "items": [{ "variantId": "<variant-uuid>", "quantity": 2 }],
  "method": "MPESA",
  "amountPaid": 300
}
```

### Example bundle setup

```json
{
  "items": [
    { "productId": "<exercise-book-uuid>", "quantity": 2 },
    { "productId": "<pen-uuid>", "quantity": 1 }
  ]
}
```

## Flutter screen map

- **Products list:** existing search, category, stock filters, and add flow.
- **Product details:** status and promotion summary, variants, stock receipt by variant, image URL entries, bundle contents, price history, and existing stock movements.
- **Sell:** selecting a product with variants prompts for the option; barcode lookup adds a matched variant directly.
- **Checkout:** submits `productId` for a regular item and `variantId` for a variant; the cart remains saved as before.

## Verification and demo

Run `cd backend && npm test`, `cd mobile && dart analyze lib test`, and apply migrations to a disposable PostgreSQL database before an end-to-end demo. The integration suite now covers the versioned alias, variant receipt and checkout, movement/idempotency, and bundle component deduction when `DATABASE_URL_TEST` points to a disposable database whose name contains `test`.

Demo: open Cooking Oil 1L, receive its 500ml variant, scan the variant barcode in Sell and complete a sale; then sell the School Starter Pack and confirm exercise-book and pen quantities each fall by one. Show the price-history screen after changing a product price.

## Phase A release notes

- Added an additive product-power migration and sample 500ml cooking-oil variant, school starter bundle, unit conversion, and fast-moving tag.
- Added versioned `/api/v1` compatibility routes while retaining unversioned routes for V1 mobile builds.
- Variant sales and bundle component deductions now share the existing atomic sale transaction and preserve sale idempotency.
- Added role-protected variant, bundle, conversion, image-metadata, tag, promotion, and price-history endpoints.
- Extended product details and POS for variants and the new catalogue controls.

## Current scope boundary

Image records currently store HTTPS URLs. Binary upload, automatic compression, camera/gallery selection, and client image caching need an image-storage provider and are not part of this slice. Unit conversion rules are validated and stored, but purchase receiving and checkout do not yet convert quantities between units. Those workflows need to use the rules in the purchasing and sales phases before merchants rely on cross-unit stock calculations.
