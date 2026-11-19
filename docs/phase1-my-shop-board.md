# Phase 1: My Shop Board

## Product decision

The home screen is a daily operating board. It leads with attention items and frequent actions, while preserving the existing dashboard sales totals as a compact summary tile. Owners and managers start with the full board; cashiers see selling shortcuts and fast movers; storekeepers see stock and receiving actions. Every role can customize and save its own board.

## Screen map

- **My Shop Board**: personalized greeting, business name, local date, attention items, quick actions, fast movers, sales summary, stock health, and customer debt.
- **Customize your board**: reorder visible tiles, hide or add tiles, pin frequent actions, or pin one of the displayed fast movers.
- **Existing workflows**: board shortcuts navigate to the existing sale, product, stock intake, barcode scanner, customer, report, and stock count flows.

The role defaults are presentation defaults, not authorization rules. Existing API role guards continue to control access. Fast movers are the eight products with the highest sold quantity over the last 30 days. If there is no sales history, the board gives an empty state instead of showing arbitrary products.

## Database change

Add `DashboardPreference`, with tenant and user foreign keys, a role, ordered tile IDs in JSON, and pinned action/product IDs in JSON. The `(userId, role)` unique key allows a user's role layouts to remain distinct. The preference is optional; absence means the client uses that role's defaults. The migration is additive and does not change sales or inventory records.

## API contract

All endpoints require the existing bearer token and derive tenant/user/role from the authenticated request.

### `GET /dashboard/board`

Returns the current user and business display names, role defaults, optional saved layout, pinned IDs, and up to eight fast movers.

```json
{
  "user": { "name": "Mama Njeri", "role": "OWNER" },
  "businessName": "Kijiji Mini Mart",
  "defaultLayout": ["attention", "quick_actions", "fast_movers", "sales_summary", "stock_health", "debt"],
  "layout": null,
  "favorites": [],
  "fastMovers": [{ "id": "product-uuid", "name": "Unga 2kg", "sellingPrice": 180, "quantity": 8, "unit": "packet", "minStock": 5, "imageUrl": null }]
}
```

### `PUT /dashboard/board/preferences`

Replaces the current user's saved visible tile order and pinned actions/product IDs. Unknown tile/action IDs are rejected, values are deduplicated, and each array is limited to 12 entries.

```json
{
  "layout": ["quick_actions", "fast_movers", "attention", "sales_summary"],
  "favorites": ["new_sale", "stock_count", "product-uuid"]
}
```

Tile IDs: `attention`, `quick_actions`, `fast_movers`, `sales_summary`, `stock_health`, `debt`.

Action IDs: `new_sale`, `add_product`, `receive_stock`, `scan_barcode`, `view_debt`, `view_reports`, `stock_count`.

## Demo script

1. Sign in as the seeded owner and show the name, business, attention cards, and today's sales summary.
2. Open **Edit board**, hide Stock health, reorder Fast movers above Quick actions, pin Stock count, and save.
3. Refresh the board and show that the chosen order and shortcut remain.
4. Tap a fast mover and confirm the product is placed into the existing sale cart.
5. Sign in as cashier and storekeeper; show their role-specific defaults and verify existing API permissions still apply.
6. Open the barcode shortcut and scan a seeded barcode into the sale flow.

## Phase boundary

This phase does not create purchase orders, capture sales offline, add branch selection, or introduce business-type onboarding. The board surfaces current debt, stock, sales, and unread-alert data only; expiry and approval cards wait for supporting workflows/data.
