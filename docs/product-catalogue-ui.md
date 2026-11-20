# StockPesa — Product Catalogue UI Description

## Visual theme
- Background: off-white (`#F7F8F7`), ink text (`#10221A`), muted (`#5F6B65`), borders (`#E3E7E4`), emerald primary (`#0B7A4B`), amber (`#F5A524`), coral (`#FF6B35`).
- Cards: white background, 16 dp rounded corners, 1 dp elevation subtle shadow, 12–16 dp internal spacing, clean Plus Jakarta Sans typography.
- Stock-status chips: In Stock = green (`#16A34A`), Low Stock = amber (`#F59E0B`), Out of Stock = red (`#DC2626`).

## Products screen (catalogue)
Header:
- App bar title "Products" with actions: barcode scan, filter/sort (tune icon), CSV import.
- Below the app bar: a prominent filled search bar (hint "Search name, SKU or barcode", search icon, clear/submit actions).
- Floating action button (coral) labelled "Add product".

Category chips (horizontally scrollable, 46 dp tall):
- "All" selected by default, highlighted with emerald fill + white text and a checkmark avatar.
- Category chips: Groceries, Drinks & Beverages, Household Items, Personal Care, Snacks, Cooking Essentials, Hardware, Stationery, Baby Products, Cleaning Products, plus any user-created categories.
- Each chip shows the product count in parentheses (e.g. "Groceries (12)").
- Unselected chips are white with emerald/gray outline; selected chip is emerald-filled.
- Tapping a chip re-filters the grid and keeps the selection when returning from details.

Product grid (`GridView.builder`):
- 2 columns on phones, 3 on tablets (width >= 700 dp); 12 dp cross/main axis spacing; card aspect ratio 0.72.
- Skeleton cards (4) while the first page loads; infinite scroll loads the next page near the bottom.
- Pull-to-refresh on the whole grid.

ProductCard (image-first):
- Image at top: 4:5 aspect ratio, BoxFit.cover, rounded top corners. Cached via `cached_network_image` (~800 px). Placeholder while loading; broken-image fallback icon on error. Looks good with or without an image.
- Overlay badges (top-left area of info): "Sale" (coral) when a promotional price is active; "Fast Moving" (emerald) / "New" (coral) from tags.
- Product name: max 2 lines, ellipsis, bold.
- Category: small muted, 1 line ellipsis.
- Price: "KES 1,250.00" bold; below it quantity + unit (e.g. "24 pcs").
- Stock-status chip at the right of the price row (green/amber/red).
- Action bar: "Add to cart" quick-add outlined button (emerald) + overflow menu (Edit product, Receive stock, Adjust stock, View stock movements, Archive product — archive owner/manager only).
- Tapping the card body opens Product Details.

Empty state: empty-products illustration + "No products found." + "Add your first product or change filters." + "Add your first product" button.
Error state: cloud-off icon, message, "Try again" button.

## Product Details screen
- App bar with product name and Edit button.
- Hero image: large (260 dp), BoxFit.cover, rounded bottom corners; stock-status chip badge overlaid bottom-right.
- Thumbnail gallery strip when multiple images exist (72 dp squares, selected one has emerald check); tapping switches the hero image.
- Product name (headline), category chip, optional brand pill.
- Meta line: SKU · Barcode · Unit.
- Description (when present).
- Pricing cards: Selling price (large), Buying price, Wholesale (when set).
- Stock card: quantity + unit (large), minimum level, stock-status chip, stock value, retail value.
- Actions row: Sell (filled emerald; disabled when out of stock), Receive Stock, Adjust Stock, Edit Product.
- Images management: Add image URL / Upload photo buttons.
- Recent stock movements list (most recent first, empty state when none).
- Variants list (when present) with name, code, price, quantity.

## Image handling
- Product images loaded through `cached_network_image` with memory-cache resizing (~400×500 logical px scaled by device pixel ratio).
- Main image = `Product.imageUrl`; additional images in `ProductImage` table (url, altText, sortOrder).
- Upload endpoint accepts JPEG/PNG/WEBP up to 5 MB, validates magic bytes, stores under `/uploads/products/` served statically with CORS.
- Placeholder while loading; broken-image fallback icon on failure; never breaks the card.

## Seed data
- 46 seeded products across all 10 required categories (Groceries, Drinks & Beverages, Cooking Essentials, Snacks, Household Items, Cleaning Products, Personal Care, Baby Products, Hardware, Stationery) including Unga 2kg, Cooking Oil 1L, Sugar 1kg, Rice 2kg, Milk 500ml, Soda 500ml, Bottled Water 500ml, Bread, Soap, Toothpaste, Shampoo, Airtime, Exercise Book, Pen, Cement, Nails, Paint Brush, Detergent, Toilet Paper, Diapers.
- Every seeded product has a stable Unsplash CDN image URL (~800×800). Direct `images.unsplash.com` URLs are used (not the deprecated `source.unsplash.com`).
