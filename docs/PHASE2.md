# StockPesa Phase 2 — API, curl examples, manual tests

Swagger UI: http://localhost:3000/docs. All routes need `Authorization: Bearer <token>` except /auth/register|login|refresh. Lists return `{data, meta:{page,limit,total,totalPages}}` (limit max 100).
Errors: 400 validation, 401 unauthenticated, 403 role, 404 missing/other-tenant, 409 duplicate SKU/barcode/name, 422 business rule.

## Endpoints (role access)

| Endpoint                                                                                      | Roles                       |
| --------------------------------------------------------------------------------------------- | --------------------------- | --- |
| GET /categories                                                                               | all                         |
| POST/PATCH/DELETE /categories[/:id]                                                           | owner, manager              |
| GET /products, /products/:id, /products/lookup?barcode=                                       | sku=                        | all |
| POST/PATCH/DELETE /products[/:id] (delete = archive if history, else soft-delete)             | owner, manager              |
| POST /products/import/preview, /products/import/confirm[?skipInvalid=true] (multipart `file`) | owner, manager              |
| GET /products/:id/images                                                                      | all                         |
| POST /products/:id/images  {url, altText?, sortOrder?} (must be https)                        | owner, manager              |
| POST /products/:id/images/upload (multipart `file`, jpeg/png/webp, max 5 MB)                  | owner, manager              |
| DELETE /products/:id/images/:imageId                                                          | owner, manager              |
| PATCH /products/:id/main-image  {imageUrl?} (set or clear main image; https required)         | owner, manager              |
| GET /stock, /stock/:productId, /stock/movements                                               | all                         |
| POST /stock/intake, /stock/adjustments (Idempotency-Key header)                               | owner, manager, storekeeper |
| POST /stock-counts, PATCH /stock-counts/:id, POST /:id/complete, /:id/cancel                  | owner, manager              |
| GET /stock-counts[/:id] ; POST /stock-counts/:id/items                                        | owner, manager, storekeeper |
| GET /alerts, PATCH /alerts/read-all, PATCH /alerts/:id/read                                   | all                         |
| GET /reports/stock-summary, /reports/stock-movements                                          | owner, manager              |
| GET /reports/low-stock                                                                        | owner, manager, storekeeper |

## curl

```bash
API=http://localhost:3000
TOKEN=$(curl -s $API/auth/login -H 'Content-Type: application/json' -d '{"identifier":"owner@stockpesa.app","password":"Demo1234!"}' | jq -r .accessToken)
H="Authorization: Bearer $TOKEN"
curl -s "$API/products?stockStatus=LOW_STOCK&sortBy=stockQuantity&limit=5" -H "$H"
curl -s "$API/products/lookup?barcode=61611001000" -H "$H"
curl -s -X POST $API/products -H "$H" -H 'Content-Type: application/json' -d '{"name":"Ketepa Tea 100g","unit":"packet","purchasePrice":60,"sellingPrice":80,"barcode":"6161100999","minStockLevel":5}'
PID=<product id>
curl -s -X POST $API/stock/intake -H "$H" -H 'Idempotency-Key: intake-001' -H 'Content-Type: application/json' -d "{\"productId\":\"$PID\",\"quantity\":24,\"unitCost\":58,\"supplier\":\"Wholesaler\"}"
curl -s -X POST $API/stock/adjustments -H "$H" -H 'Content-Type: application/json' -d "{\"productId\":\"$PID\",\"quantityChange\":-2,\"reason\":\"DAMAGE\"}"
curl -s -F file=@products.csv $API/products/import/preview -H "$H"
curl -s -F file=@products.csv "$API/products/import/confirm" -H "$H"

# Product images (PID = product id)
curl -s "$API/products/$PID/images" -H "$H"
curl -s -X POST $API/products/$PID/images -H "$H" -H 'Content-Type: application/json' -d '{"url":"https://cdn.example.com/product.jpg","altText":"Unga 2kg","sortOrder":0}'
curl -s -F file=@photo.jpg $API/products/$PID/images/upload -H "$H"
curl -s -X DELETE $API/products/$PID/images/<imageId> -H "$H"
curl -s -X PATCH $API/products/$PID/main-image -H "$H" -H 'Content-Type: application/json' -d '{"imageUrl":"https://cdn.example.com/main.jpg"}'
curl -s -X PATCH $API/products/$PID/main-image -H "$H" -H 'Content-Type: application/json' -d '{"imageUrl":null}'

# Product create now also accepts optional "imageUrl" (secure https URL).
CID=$(curl -s -X POST $API/stock-counts -H "$H" -H 'Content-Type: application/json' -d '{"notes":"Friday count"}' | jq -r .id)
curl -s -X POST $API/stock-counts/$CID/items -H "$H" -H 'Content-Type: application/json' -d "{\"productId\":\"$PID\",\"countedQuantity\":20}"
curl -s -X POST $API/stock-counts/$CID/complete -H "$H"
curl -s "$API/alerts?unread=true" -H "$H"; curl -s "$API/reports/stock-summary" -H "$H"
```

CSV: `name,selling_price,unit,sku,barcode,category,brand,purchase_price,opening_stock,min_stock_level,reorder_quantity`

## Manual test checklist

1. Login as each seeded role (password Demo1234!). 2. Cashier: POST /products, /stock/intake, /products/import/preview -> 403; GET /products and lookup -> 200.
2. Intake 24 -> quantity rises, one PURCHASE_IN movement, product purchasePrice updated. Repeat with same Idempotency-Key -> `replayed:true`, no second movement.
3. Adjust -20 on item with 25 (no notes) -> 422; with notes -> ok, LARGE_STOCK_ADJUSTMENT alert. Adjust below zero as storekeeper -> 422 + NEGATIVE_STOCK_ATTEMPT alert; as manager with reason NEGATIVE_STOCK_OVERRIDE -> ok + audit row.
4. Sell/adjust a product down to min -> one LOW_STOCK alert; to 0 -> OUT_OF_STOCK (low one resolved); intake above min -> alerts resolved; repeated moves create no duplicates.
5. Duplicate barcode on create/patch -> 409. Register a 2nd business; its token cannot GET/PATCH/adjust the 1st business's product ids (404).
6. CSV: bad unit, negative price, duplicate SKU in file, SKU already in DB -> preview lists errors; confirm refuses (422) unless skipInvalid=true; valid rows create products + PURCHASE_IN movements.
7. Count: create, add items, complete -> STOCK_COUNT_IN/OUT movements for non-zero differences only; complete twice -> 422; add item after complete -> 422; empty count -> 422.
8. Delete product with history -> archived; with none -> soft-deleted. Delete category with products -> 422.
9. SQL check: for every product, SUM(StockMovement.quantity) = StockLevel.quantity (seed data satisfies this).
