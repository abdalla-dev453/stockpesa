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
// [name, category, buy, sell, qty, min]
const P: [string, string, number, number, number, number][] = [
  ["Unga Jogoo 2kg", "Groceries", 150, 175, 40, 10],
  ["Sugar 1kg", "Groceries", 130, 160, 6, 10],
  ["Cooking Oil 1L", "Groceries", 260, 310, 0, 8],
  ["Rice Pishori 1kg", "Groceries", 170, 210, 25, 8],
  ["Maize Flour 1kg", "Groceries", 70, 90, 50, 15],
  ["Bread 400g", "Groceries", 55, 65, 12, 10],
  ["Eggs Tray", "Groceries", 380, 450, 5, 5],
  ["Salt 500g", "Groceries", 25, 40, 30, 10],
  ["Tea Leaves 250g", "Groceries", 90, 120, 18, 6],
  ["Soda 500ml", "Drinks", 45, 60, 48, 24],
  ["Bottled Water 1L", "Drinks", 30, 50, 3, 12],
  ["Juice 1L", "Drinks", 110, 150, 14, 6],
  ["Milk 500ml", "Drinks", 55, 65, 0, 12],
  ["Energy Drink", "Drinks", 70, 100, 9, 6],
  ["Omo 1kg", "Household", 280, 340, 10, 4],
  ["Bar Soap", "Household", 90, 120, 22, 8],
  ["Jik 750ml", "Household", 120, 160, 7, 5],
  ["Toilet Paper 4pk", "Household", 140, 190, 15, 6],
  ["Matchbox", "Household", 5, 10, 60, 20],
  ["Candles 6pk", "Household", 60, 90, 4, 5],
  ["Toothpaste", "Personal Care", 100, 140, 16, 6],
  ["Lotion 400ml", "Personal Care", 250, 330, 8, 4],
  ["Sanitary Pads", "Personal Care", 70, 100, 2, 8],
  ["Razor", "Personal Care", 20, 40, 30, 10],
  ["Cement 50kg", "Hardware", 720, 800, 30, 10],
  ["Nails 3in kg", "Hardware", 160, 220, 12, 5],
  ["Padlock", "Hardware", 180, 280, 0, 3],
  ["Exercise Book", "Stationery", 35, 50, 60, 20],
  ["Pen Blue", "Stationery", 8, 15, 100, 30],
  ["Airtime Scratch Card", "Stationery", 95, 100, 25, 10],
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
  for (const [n, c, buy, sell, qty, min] of P) {
    cats[c] ??= (
      await db.category.create({ data: { businessId: b.id, name: c } })
    ).id;
    const p = await db.product.create({
      data: {
        businessId: b.id,
        categoryId: cats[c],
        name: n,
        sku: "SKU" + (prods.length + 1),
        buyingPrice: buy,
        sellingPrice: sell,
        minStock: min,
        reorderQty: min * 3,
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
  const oil = prods[P.findIndex((row) => row[0] === "Cooking Oil 1L")];
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
      { businessId: b.id, bundleProductId: stationeryBundle.id, componentId: prods[P.findIndex((row) => row[0] === "Exercise Book")].id, quantity: 1 },
      { businessId: b.id, bundleProductId: stationeryBundle.id, componentId: prods[P.findIndex((row) => row[0] === "Pen Blue")].id, quantity: 1 },
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
  const sellable = prods.filter((p) => P[prods.indexOf(p)][4] > 0);
  // Historical sales keep the levels, ledger, payments, receipts and debt consistent.
  for (let i = 0; i < 24; i++) {
    const p = sellable[i % sellable.length];
    const base = P[prods.indexOf(p)];
    const q = Math.min(1 + (i % 3), base[4]);
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
