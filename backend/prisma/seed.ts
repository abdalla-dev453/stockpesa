import { PrismaClient, Role } from "@prisma/client";
import * as bcrypt from "bcrypt";
const db = new PrismaClient();
async function seedStressCatalog(businessId: string, requested: number) {
  const count = Math.max(0, Math.min(20_000, Math.floor(requested)));
  if (!count) return;
  const categories = ["Stress Groceries", "Stress Drinks", "Stress Household", "Stress Personal Care", "Stress Hardware", "Stress Stationery", "Stress Produce", "Stress Kitchen"];
  const categoryIds: string[] = [];
  for (const name of categories) categoryIds.push((await db.category.upsert({ where: { businessId_name: { businessId, name } }, create: { businessId, name }, update: {} })).id);
  let created = 0;
  for (let offset = 0; offset < count; offset += 500) {
    const end = Math.min(count, offset + 500);
    const products = Array.from({ length: end - offset }, (_, index) => {
      const n = offset + index + 1, categoryId = categoryIds[n % categoryIds.length];
      const buyingPrice = 15 + (n * 37) % 1800;
      return { businessId, categoryId, name: `Load Test Item ${String(n).padStart(5, "0")}`, sku: `LOAD-${String(n).padStart(6, "0")}`, unit: ["piece", "packet", "bottle", "kg", "pack"][n % 5], buyingPrice, sellingPrice: Math.round(buyingPrice * (1.1 + (n % 6) / 100) * 100) / 100, minStock: 5 + n % 20, reorderQty: 30 + n % 100 };
    });
    await db.product.createMany({ data: products, skipDuplicates: true });
    const saved = await db.product.findMany({ where: { businessId, sku: { in: products.map((p) => p.sku!) } }, select: { id: true, buyingPrice: true, sku: true } });
    const levels = saved.map((p) => ({ businessId, productId: p.id, quantity: 10 + (Number(p.sku?.slice(-3)) % 490) }));
    await db.stockLevel.createMany({ data: levels, skipDuplicates: true });
    created += saved.length;
    console.log(`Load test catalog: ${created}/${count} products prepared`);
  }
}
// Direct, stable Unsplash CDN URLs (not the deprecated source.unsplash.com API).
// Each image is served at ~800px wide to keep card payloads small. If any URL
// becomes unavailable the app shows a graceful fallback instead of breaking.
const IMG = (id: string) =>
  `https://images.unsplash.com/photo-${id}?ixlib=rb-4.0.3&auto=format&fit=crop&w=800&q=80`;
type SeedProduct = {
  name: string;
  category: string;
  unit: string;
  buy: number;
  sell: number;
  qty: number;
  min: number;
  barcode?: string;
  imageId: string;
};
const P: SeedProduct[] = [
  { name: "Unga 2kg", category: "Groceries", unit: "kg", buy: 150, sell: 175, qty: 40, min: 10, barcode: "5000101000012", imageId: "1505242570764-6ff0315c0e71" },
  { name: "Sugar 1kg", category: "Groceries", unit: "kg", buy: 130, sell: 160, qty: 6, min: 10, barcode: "5000101000029", imageId: "1550609962-097fce309400" },
  { name: "Cooking Oil 1L", category: "Cooking Essentials", unit: "litre", buy: 260, sell: 310, qty: 0, min: 8, barcode: "5000101000036", imageId: "1562325230-42a4a8c6a584" },
  { name: "Rice Pishori 2kg", category: "Groceries", unit: "kg", buy: 170, sell: 210, qty: 25, min: 8, barcode: "5000101000043", imageId: "1586201375761-83865001e358" },
  { name: "Maize Flour 1kg", category: "Groceries", unit: "kg", buy: 70, sell: 90, qty: 50, min: 15, barcode: "5000101000050", imageId: "1528395527540-eb9c2d9b7c0d" },
  { name: "Bread 400g", category: "Groceries", unit: "packet", buy: 55, sell: 65, qty: 12, min: 10, barcode: "5000101000067", imageId: "1514750813155-d7a5e1e0a849" },
  { name: "Eggs Tray", category: "Groceries", unit: "carton", buy: 380, sell: 450, qty: 5, min: 5, barcode: "5000101000074", imageId: "1532737473052-d747196405f6" },
  { name: "Salt 500g", category: "Groceries", unit: "packet", buy: 25, sell: 40, qty: 30, min: 10, barcode: "5000101000081", imageId: "1542838132-92c53300491e" },
  { name: "Tea Leaves 250g", category: "Groceries", unit: "packet", buy: 90, sell: 120, qty: 18, min: 6, barcode: "5000101000098", imageId: "1544161516-470561b97a83" },
  { name: "Soda 500ml", category: "Drinks & Beverages", unit: "bottle", buy: 45, sell: 60, qty: 48, min: 24, barcode: "5000201000010", imageId: "1541742458872-cead5989b4f5" },
  { name: "Bottled Water 500ml", category: "Drinks & Beverages", unit: "bottle", buy: 30, sell: 50, qty: 3, min: 12, barcode: "5000201000027", imageId: "1559840167-733b1e1e0f4b" },
  { name: "Juice 1L", category: "Drinks & Beverages", unit: "bottle", buy: 110, sell: 150, qty: 14, min: 6, barcode: "5000201000034", imageId: "1600891964492-431692897fe2" },
  { name: "Milk 500ml", category: "Drinks & Beverages", unit: "bottle", buy: 55, sell: 65, qty: 0, min: 12, barcode: "5000201000041", imageId: "1528548438156-dab693e52f3c" },
  { name: "Energy Drink", category: "Drinks & Beverages", unit: "bottle", buy: 70, sell: 100, qty: 9, min: 6, barcode: "5000201000058", imageId: "1564507592333-c60697eea623" },
  { name: "Chapati Snack Pack", category: "Snacks", unit: "packet", buy: 30, sell: 50, qty: 20, min: 8, barcode: "5000301000018", imageId: "1567620905672-5b5e3308c0c3" },
  { name: "Mandazi 10pcs", category: "Snacks", unit: "packet", buy: 40, sell: 70, qty: 15, min: 6, barcode: "5000301000025", imageId: "1534436050767-84997075919b" },
  { name: "Crisps 150g", category: "Snacks", unit: "packet", buy: 60, sell: 90, qty: 25, min: 10, barcode: "5000301000032", imageId: "1544454011-3739999a82f7" },
  { name: "Omo 1kg", category: "Cleaning Products", unit: "kg", buy: 280, sell: 340, qty: 10, min: 4, barcode: "5000401000016", imageId: "1581091226825-a6a2a5aee158" },
  { name: "Bar Soap", category: "Household Items", unit: "piece", buy: 90, sell: 120, qty: 22, min: 8, barcode: "5000401000023", imageId: "1556228578-0d85b5f1a465" },
  { name: "Jik 750ml", category: "Cleaning Products", unit: "bottle", buy: 120, sell: 160, qty: 7, min: 5, barcode: "5000401000030", imageId: "1558641768-533a4d2b5b1b" },
  { name: "Toilet Paper 4pk", category: "Household Items", unit: "pack", buy: 140, sell: 190, qty: 15, min: 6, barcode: "5000401000047", imageId: "1547904781-19000a369e1f" },
  { name: "Detergent 1kg", category: "Cleaning Products", unit: "kg", buy: 180, sell: 240, qty: 12, min: 5, barcode: "5000401000054", imageId: "1527933721751-58e6d95e9d8e" },
  { name: "Matchbox", category: "Household Items", unit: "piece", buy: 5, sell: 10, qty: 60, min: 20, barcode: "5000401000061", imageId: "1517373171896-11f137c8c51b" },
  { name: "Candles 6pk", category: "Household Items", unit: "pack", buy: 60, sell: 90, qty: 4, min: 5, barcode: "5000401000078", imageId: "1531483560287-1e1c8f4e68b1" },
  { name: "Toothpaste", category: "Personal Care", unit: "piece", buy: 100, sell: 140, qty: 16, min: 6, barcode: "5000501000014", imageId: "1592175539279-4e709000214c" },
  { name: "Shampoo 400ml", category: "Personal Care", unit: "bottle", buy: 220, sell: 300, qty: 8, min: 4, barcode: "5000501000021", imageId: "1522336769275-4d7b7b1c6a17" },
  { name: "Lotion 400ml", category: "Personal Care", unit: "bottle", buy: 250, sell: 330, qty: 8, min: 4, barcode: "5000501000038", imageId: "1571789693351-58e71b8b052d" },
  { name: "Sanitary Pads", category: "Personal Care", unit: "packet", buy: 70, sell: 100, qty: 2, min: 8, barcode: "5000501000045", imageId: "1543601043-7b99b9b1e1a7" },
  { name: "Razor", category: "Personal Care", unit: "piece", buy: 20, sell: 40, qty: 30, min: 10, barcode: "5000501000052", imageId: "1589719082156-e9066d0b0f8b" },
  { name: "Hand Sanitizer 250ml", category: "Personal Care", unit: "bottle", buy: 150, sell: 200, qty: 14, min: 6, barcode: "5000501000069", imageId: "1557384163-1a0b9e8c8e3b" },
  { name: "Diapers (Newborn)", category: "Baby Products", unit: "pack", buy: 450, sell: 550, qty: 6, min: 4, barcode: "5000601000012", imageId: "1590470640051-6c3ef6f4b4f0" },
  { name: "Baby Soap", category: "Baby Products", unit: "piece", buy: 110, sell: 150, qty: 10, min: 5, barcode: "5000601000029", imageId: "1534518112165-0d0c3d8e8c1b" },
  { name: "Baby Lotion 200ml", category: "Baby Products", unit: "bottle", buy: 240, sell: 320, qty: 7, min: 4, barcode: "5000601000036", imageId: "1576096919687-20e4b0c6e76c" },
  { name: "Infant Wipes", category: "Baby Products", unit: "pack", buy: 180, sell: 240, qty: 8, min: 4, barcode: "5000601000043", imageId: "1526552585272-22e3c6e4c3a1" },
  { name: "Cement 50kg", category: "Hardware", unit: "kg", buy: 720, sell: 800, qty: 30, min: 10, barcode: "5000701000010", imageId: "1518189360283-8e1a0b4e6c1b" },
  { name: "Nails 3in kg", category: "Hardware", unit: "kg", buy: 160, sell: 220, qty: 12, min: 5, barcode: "5000701000027", imageId: "1504197413875-5471b72f07e1" },
  { name: "Padlock", category: "Hardware", unit: "piece", buy: 180, sell: 280, qty: 0, min: 3, barcode: "5000701000034", imageId: "1556761175-5973dc0f32e7" },
  { name: "Paint Brush", category: "Hardware", unit: "piece", buy: 70, sell: 100, qty: 9, min: 5, barcode: "5000701000041", imageId: "1513461618604-6b3b8e9c8e1b" },
  { name: "Exercise Book", category: "Stationery", unit: "piece", buy: 35, sell: 50, qty: 60, min: 20, barcode: "5000801000018", imageId: "1544947951-fa47a19c32e7" },
  { name: "Pen Blue", category: "Stationery", unit: "piece", buy: 8, sell: 15, qty: 100, min: 30, barcode: "5000801000025", imageId: "1513461618604-6b3b8e9c8e2b" },
  { name: "Airtime Scratch Card", category: "Stationery", unit: "piece", buy: 95, sell: 100, qty: 25, min: 10, barcode: "5000801000032", imageId: "1555650397-69d4f7b1e1a7" },
  { name: "Notebook A4", category: "Stationery", unit: "piece", buy: 120, sell: 160, qty: 18, min: 6, barcode: "5000801000049", imageId: "1531236570241-637e956e5e1b" },
  { name: "Pencil 12pk", category: "Stationery", unit: "pack", buy: 60, sell: 100, qty: 22, min: 8, barcode: "5000801000056", imageId: "1522364677364-824f2e8c8e1b" },
  { name: "Body Spray", category: "Personal Care", unit: "bottle", buy: 280, sell: 380, qty: 10, min: 5, barcode: "5000501000076", imageId: "1583292072559-0b6d4f7c8e1b" },
  { name: "Toilet Cleaner 750ml", category: "Cleaning Products", unit: "bottle", buy: 130, sell: 180, qty: 9, min: 5, barcode: "5000401000085", imageId: "1544454011-3739999a82f7" },
  { name: "Dish Soap 500ml", category: "Cleaning Products", unit: "bottle", buy: 110, sell: 150, qty: 11, min: 5, barcode: "5000401000092", imageId: "1584446906422-349a3e6a1c0b" },
];
async function main() {
  if (Number(process.env.STRESS_PRODUCT_COUNT ?? 0) > 0 && process.env.NODE_ENV === "production") {
    throw new Error("Stress-test catalog seeding is disabled in production");
  }
  const seeded = await db.user.findFirst({ where: { email: "owner@stockpesa.app" } });
  if (seeded) {
    const count = Number(process.env.STRESS_PRODUCT_COUNT ?? 0);
    if (count > 0) await seedStressCatalog(seeded.businessId, count);
    console.log("StockPesa demo data already exists; skipping seed.");
    return;
  }
  const pw = await bcrypt.hash("Demo1234!", 10);
  const b = await db.business.create({
    data: {
      name: "Mama Njeri Mini Mart",
      type: "retail shop",
      location: "Nairobi",
      phone: "0712345678",
      receiptFooter: "Asante! Karibu tena.",
    },
  });
  const mk = (n: string, e: string, ph: string, r: Role) =>
    db.user.create({
      data: {
        businessId: b.id,
        fullName: n,
        email: e,
        phone: ph,
        passwordHash: pw,
        role: r,
      },
    });
  const owner = await mk(
    "Njeri Wanjiku",
    "owner@stockpesa.app",
    "0712345678",
    "OWNER",
  );
  await mk("Kamau Manager", "manager@stockpesa.app", "0712345679", "MANAGER");
  const cashier = await mk(
    "Amina Cashier",
    "cashier@stockpesa.app",
    "0712345680",
    "CASHIER",
  );
  await mk("Otieno Store", "store@stockpesa.app", "0712345681", "STOREKEEPER");
  const cats: Record<string, string> = {};
  const prods: any[] = [];
  for (const { name, category, unit, buy, sell, qty, min, barcode, imageId } of P) {
    cats[category] ??= (
      await db.category.create({ data: { businessId: b.id, name: category } })
    ).id;
    const p = await db.product.create({
      data: {
        businessId: b.id,
        categoryId: cats[category],
        name,
        sku: "SKU" + (prods.length + 1),
        barcode,
        unit,
        brand: "StockPesa",
        description: `${name} — ${category}`,
        buyingPrice: buy,
        sellingPrice: sell,
        minStock: min,
        reorderQty: min * 3,
        imageUrl: IMG(imageId),
        active: true,
      },
    });
    await db.stockLevel.create({
      data: { productId: p.id, businessId: b.id, quantity: qty },
    });
    await db.stockMovement.create({
      data: {
        businessId: b.id,
        productId: p.id,
        userId: owner.id,
        type: "purchase_in",
        quantityChange: qty,
        unitCost: buy,
        reason: "opening stock",
      },
    });
    if (qty <= min)
      await db.alert.create({
        data: {
          businessId: b.id,
          productId: p.id,
          kind: qty === 0 ? "out_of_stock" : "low_stock",
        },
      });
    prods.push(p);
  }
  const oil = prods[P.findIndex((row) => row.name === "Cooking Oil 1L")];
  const oilVariant = await db.productVariant.create({
    data: {
      businessId: b.id,
      productId: oil.id,
      name: "500ml",
      attributes: { size: "500ml" },
      sku: "OIL-500ML",
      unit: "bottle",
      buyingPrice: 135,
      sellingPrice: 165,
      minStock: 8,
      quantity: 24,
    },
  });
  await db.variantStockMovement.create({
    data: {
      businessId: b.id,
      variantId: oilVariant.id,
      userId: owner.id,
      quantityChange: 24,
      unitCost: 135,
      reason: "Opening stock",
    },
  });
  const stationeryBundle = await db.product.create({
    data: {
      businessId: b.id,
      categoryId: cats.Stationery,
      name: "School Starter Pack",
      sku: "BUNDLE-SCHOOL-01",
      unit: "pack",
      buyingPrice: 51,
      sellingPrice: 70,
    },
  });
  await db.productBundle.create({ data: { businessId: b.id, productId: stationeryBundle.id } });
  await db.bundleItem.createMany({
    data: [
      { businessId: b.id, bundleProductId: stationeryBundle.id, componentId: prods[P.findIndex((row) => row.name === "Exercise Book")].id, quantity: 1 },
      { businessId: b.id, bundleProductId: stationeryBundle.id, componentId: prods[P.findIndex((row) => row.name === "Pen Blue")].id, quantity: 1 },
    ],
  });
  await db.unitConversion.create({
    data: { businessId: b.id, productId: oil.id, fromUnit: "litre", toUnit: "millilitre", multiplier: 1000 },
  });
  const promoTag = await db.productTag.create({ data: { businessId: b.id, name: "Fast-moving" } });
  await db.productTagAssignment.create({ data: { businessId: b.id, productId: prods[0].id, tagId: promoTag.id } });
  const cust = await db.customer.create({
    data: {
      businessId: b.id,
      name: "Mama Otis",
      phone: "0722000111",
      creditLimit: 5000,
      balance: 0,
    },
  });
  let customerDebt = 0;
  const sellable = prods.filter((p) => P[prods.indexOf(p)].qty > 0);
  // Historical sales keep the levels, ledger, payments, receipts and debt consistent.
  for (let i = 0; i < 24; i++) {
    const p = sellable[i % sellable.length];
    const base = P[prods.indexOf(p)];
    const q = Math.min(1 + (i % 3), base.qty);
    const d = new Date(Date.now() - (i % 14) * 864e5);
    const total = Number(p.sellingPrice) * q;
    const credit = i % 8 === 0;
    if (credit) customerDebt += total;
    const s = await db.sale.create({
      data: {
        businessId: b.id,
        userId: cashier.id,
        customerId: credit ? cust.id : null,
        saleNumber: "S-" + String(1000 + i),
        saleDate: d,
        subtotal: total,
        total,
        amountPaid: credit ? 0 : total,
        balanceDue: credit ? total : 0,
        status: credit ? "unpaid" : "completed",
        items: {
          create: [
            {
              businessId: b.id,
              productId: p.id,
              quantity: q,
              unit: p.unit,
              stockQuantity: q,
              unitPrice: p.sellingPrice,
              unitCost: p.buyingPrice,
              lineTotal: total,
            },
          ],
        },
      },
    });
    await db.payment.create({
      data: {
        businessId: b.id,
        saleId: s.id,
        method: credit ? "CREDIT" : i % 2 ? "MPESA" : "CASH",
        amount: credit ? 0 : total,
        status: "PAID",
        settledAt: d,
        createdAt: d,
      },
    });
    await db.stockMovement.create({
      data: {
        businessId: b.id,
        productId: p.id,
        userId: cashier.id,
        type: "sale_out",
        quantityChange: -q,
        reference: s.saleNumber,
        createdAt: d,
      },
    });
    await db.stockLevel.update({ where: { productId: p.id }, data: { quantity: { decrement: q } } });
    await db.receipt.create({ data: { businessId: b.id, saleId: s.id, receiptNumber: s.saleNumber, snapshot: { businessName: b.name, businessPhone: b.phone, receiptFooter: b.receiptFooter, currency: b.currency, saleNumber: s.saleNumber, saleDate: d.toISOString(), subtotal: total, discount: 0, tax: 0, total, amountPaid: credit ? 0 : total, balanceDue: credit ? total : 0, method: credit ? "CREDIT" : i % 2 ? "MPESA" : "CASH", paymentStatus: "PAID", items: [{ name: p.name, sku: p.sku, quantity: q, unitPrice: Number(p.sellingPrice), lineDiscount: 0, lineTotal: total }] } } });
    await db.auditLog.create({ data: { businessId: b.id, userId: cashier.id, action: "sale.completed", entity: "sale", entityId: s.id, meta: { saleNumber: s.saleNumber, total, seeded: true } } });
  }
  await db.customer.update({ where: { id: cust.id }, data: { balance: customerDebt } });
  await db.stockMovement.create({
    data: {
      businessId: b.id,
      productId: prods[1].id,
      userId: owner.id,
      type: "adjustment",
      quantityChange: -2,
      reason: "damage",
      notes: "Torn packets",
    },
  });
  await db.stockLevel.update({ where: { productId: prods[1].id }, data: { quantity: { decrement: 2 } } });
  await db.alert.deleteMany({ where: { businessId: b.id } });
  const finalLevels = await db.product.findMany({ where: { businessId: b.id }, include: { stock: true } });
  for (const p of finalLevels) {
    const qty = Number(p.stock?.quantity ?? 0);
    if (qty <= Number(p.minStock)) await db.alert.create({ data: { businessId: b.id, productId: p.id, kind: qty <= 0 ? "out_of_stock" : "low_stock" } });
  }
  const stressCount = Number(process.env.STRESS_PRODUCT_COUNT ?? 0);
  if (stressCount > 0) await seedStressCatalog(b.id, stressCount);
}
main().finally(() => db.$disconnect());
