import { BadRequestException, Controller, Get, Patch, Param, ParseUUIDPipe, Query, UseGuards, Module, NotFoundException, Post, Body, Put } from "@nestjs/common";
import { ArrayMaxSize, IsArray, IsDateString, IsIn, IsOptional, IsString } from "class-validator";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me, Roles } from "../common/auth";

class ReportExportAuditDto {
  @IsIn(["business_summary"]) reportType: string;
  @IsOptional() @IsDateString() from?: string;
  @IsOptional() @IsDateString() to?: string;
  @IsIn(["csv"]) format: string;
  @IsOptional() @IsIn(["mobile_summary_v1"]) schema?: string;
}

@Controller("alerts") @UseGuards(AuthGuard)
class AlertsController {
  constructor(private db: PrismaService) {}
  @Get() async list(@Me() u, @Query("unread") unread?: string, @Query("page") pageText?: string, @Query("limit") limitText?: string) {
    const page = Math.max(1, Number(pageText) || 1), limit = Math.min(100, Math.max(1, Number(limitText) || 20));
    const unreadFilter = unread === "true" ? Prisma.sql`AND a."read" = false` : Prisma.empty;
    const [totalRows, unreadRows, rows] = await Promise.all([
      this.db.$queryRaw<Array<{ count: bigint }>>(Prisma.sql`
        SELECT COUNT(*) AS count FROM "Alert" a
        WHERE a."businessId" = ${u.businessId}::uuid AND (a."userId" IS NULL OR a."userId" = ${u.sub}::uuid) ${unreadFilter}
      `),
      this.db.$queryRaw<Array<{ count: bigint }>>(Prisma.sql`
        SELECT COUNT(*) AS count FROM "Alert" a
        WHERE a."businessId" = ${u.businessId}::uuid AND (a."userId" IS NULL OR a."userId" = ${u.sub}::uuid) AND a."read" = false
      `),
      this.db.$queryRaw<Array<Record<string, unknown>>>(Prisma.sql`
        SELECT a."id", a."businessId", a."productId", a."userId", a."kind", a."title", a."body", a."data", a."critical", a."read", a."createdAt",
          CASE WHEN p."id" IS NULL THEN NULL ELSE jsonb_build_object('id', p."id", 'name', p."name", 'minStock', p."minStock") END AS product
        FROM "Alert" a LEFT JOIN "Product" p ON p."id" = a."productId" AND p."businessId" = a."businessId"
        WHERE a."businessId" = ${u.businessId}::uuid AND (a."userId" IS NULL OR a."userId" = ${u.sub}::uuid) ${unreadFilter}
        ORDER BY a."createdAt" DESC LIMIT ${limit} OFFSET ${(page - 1) * limit}
      `),
    ]);
    const total = Number(totalRows[0]?.count ?? 0);
    return { data: rows, unreadCount: Number(unreadRows[0]?.count ?? 0), meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
  }
  @Patch("read-all") async readAll(@Me() u) {
    const updated = await this.db.$executeRaw(Prisma.sql`
      UPDATE "Alert" SET "read" = true WHERE "businessId" = ${u.businessId}::uuid
        AND ("userId" IS NULL OR "userId" = ${u.sub}::uuid) AND "read" = false
    `);
    return { updated };
  }
  @Patch(":id/read") async read(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const updated = await this.db.$executeRaw(Prisma.sql`
      UPDATE "Alert" SET "read" = true WHERE "id" = ${id}::uuid AND "businessId" = ${u.businessId}::uuid
        AND ("userId" IS NULL OR "userId" = ${u.sub}::uuid)
    `);
    if (!updated) throw new NotFoundException("Alert not found");
    return { id, read: true };
  }
}

@Controller("reports") @UseGuards(AuthGuard)
class ReportsController {
  constructor(private db: PrismaService) {}
  @Post("export") @Roles("OWNER", "MANAGER") async recordExport(@Me() u, @Body() d: ReportExportAuditDto) {
    const audit = await this.db.auditLog.create({ data: {
      businessId: u.businessId,
      userId: u.sub,
      action: "report.exported",
      entity: "report",
      meta: { reportType: d.reportType, format: d.format, schema: d.schema ?? null, from: d.from ?? null, to: d.to ?? null },
    } });
    return { recorded: true, id: audit.id };
  }
  @Get("dashboard") @Roles("OWNER", "MANAGER", "CASHIER") async dashboard(@Me() u, @Query("period") period = "today", @Query("start_date") startText?: string, @Query("end_date") endText?: string) {
    if (u.role === "CASHIER") period = "today";
    const now = new Date();
    const midnight = new Date(now); midnight.setHours(0, 0, 0, 0);
    let start = midnight, end = new Date(now);
    if (period === "yesterday") { start = new Date(midnight); start.setDate(start.getDate() - 1); end = new Date(midnight.getTime() - 1); }
    else if (period === "last_7_days") { start = new Date(midnight); start.setDate(start.getDate() - 6); }
    else if (period === "last_30_days") { start = new Date(midnight); start.setDate(start.getDate() - 29); }
    else if (period === "this_month") start = new Date(now.getFullYear(), now.getMonth(), 1);
    else if (period === "last_month") { start = new Date(now.getFullYear(), now.getMonth() - 1, 1); end = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59, 999); }
    else if (period === "custom") {
      start = startText ? new Date(startText) : midnight; end = endText ? new Date(endText) : now;
      if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || start > end) throw new BadRequestException("Invalid date range");
    } else if (period !== "today") throw new BadRequestException("Unsupported dashboard period");
    const duration = end.getTime() - start.getTime();
    const previousStart = new Date(start.getTime() - duration - 1), previousEnd = new Date(start.getTime() - 1);
    const saleWhere = { businessId: u.businessId, ...(u.role === "CASHIER" ? { userId: u.sub } : {}), saleDate: { gte: start, lte: end }, status: { notIn: ["void", "refunded"] } };
    const [products, sales, previousSales, itemCount, salesMonth, stockCounts, unreadAlerts, payments, receivables, trend] = await Promise.all([
      this.db.product.count({ where: { businessId: u.businessId, deletedAt: null, active: true } }),
      this.db.sale.aggregate({ where: saleWhere, _sum: { total: true, balanceDue: true }, _count: true }),
      this.db.sale.aggregate({ where: { businessId: u.businessId, ...(u.role === "CASHIER" ? { userId: u.sub } : {}), saleDate: { gte: previousStart, lte: previousEnd }, status: { notIn: ["void", "refunded"] } }, _sum: { total: true }, _count: true }),
      this.db.saleItem.aggregate({ where: { businessId: u.businessId, sale: saleWhere }, _sum: { stockQuantity: true } }),
      this.db.sale.aggregate({ where: { businessId: u.businessId, saleDate: { gte: new Date(new Date().getFullYear(), new Date().getMonth(), 1) }, status: { notIn: ["void", "refunded"] } }, _sum: { total: true }, _count: true }),
      this.db.$queryRaw<Array<{ lowStock: bigint; outOfStock: bigint }>>(Prisma.sql`
        SELECT COUNT(*) FILTER (WHERE COALESCE(s."quantity", 0) <= 0) AS "outOfStock",
          COUNT(*) FILTER (WHERE COALESCE(s."quantity", 0) > 0 AND p."minStock" > 0 AND s."quantity" <= p."minStock") AS "lowStock"
        FROM "Product" p LEFT JOIN "StockLevel" s ON s."productId" = p."id"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
      `),
      // Keep the overview query compatible with databases that have not yet
      // applied the optional per-user notification migration. The dashboard
      // only needs the existing business-wide unread count.
      this.db.alert.count({ where: { businessId: u.businessId, read: false } }),
      this.db.payment.groupBy({ by: ["method"], where: { businessId: u.businessId, ...(u.role === "CASHIER" ? { sale: { userId: u.sub } } : {}), status: "PAID", OR: [{ settledAt: { gte: start, lte: end } }, { settledAt: null, createdAt: { gte: start, lte: end } }] }, _sum: { amount: true } }),
      this.db.customer.aggregate({ where: { businessId: u.businessId, deletedAt: null, balance: { gt: 0 } }, _sum: { balance: true }, _count: true }),
      this.db.$queryRaw<Array<{ day: Date; sales: Prisma.Decimal; transactions: bigint }>>(Prisma.sql`
        SELECT DATE(s."saleDate") AS day, COALESCE(SUM(s."total"), 0)::numeric AS sales, COUNT(*) AS transactions
        FROM "Sale" s WHERE s."businessId" = ${u.businessId}::uuid AND (${u.role === "CASHIER" ? Prisma.sql`s."userId" = ${u.sub}::uuid` : Prisma.sql`TRUE`}) AND s."saleDate" >= ${start} AND s."saleDate" <= ${end} AND s."status" NOT IN ('void','refunded')
        GROUP BY DATE(s."saleDate") ORDER BY day ASC`),
    ]);
    const lowStock = Number(stockCounts[0]?.lowStock ?? 0);
    const outOfStock = Number(stockCounts[0]?.outOfStock ?? 0);
    const total = Number(sales._sum.total ?? 0), previous = Number(previousSales._sum.total ?? 0);
    const cashier = u.role === "CASHIER";
    return { period, startDate: start.toISOString(), endDate: end.toISOString(), productCount: products,
      salesToday: total, sales: total, saleCountToday: sales._count, saleCount: sales._count,
      itemsSold: Number(itemCount._sum.stockQuantity ?? 0), previousSales: previous,
      changePercent: previous === 0 ? null : Math.round((total - previous) / previous * 1000) / 10,
      salesMonth: Number(salesMonth._sum.total ?? 0), saleCountMonth: salesMonth._count,
      lowStock, outOfStock, unreadAlerts,
      trend: trend.map((r) => ({ date: r.day, sales: Number(r.sales), transactions: Number(r.transactions) })),
      paymentMethods: payments.map((r) => ({ method: r.method, amount: Number(r._sum.amount ?? 0) })),
      ...(cashier ? {} : { outstandingCustomerDebt: Number(receivables._sum.balance ?? 0), indebtedCustomers: receivables._count, balanceDue: Number(sales._sum.balanceDue ?? 0) }) };
  }
  @Get("market-insights") @Roles("OWNER", "MANAGER") async marketInsights(@Me() u, @Query("days") daysText?: string) {
    const days = Number(daysText) === 7 ? 7 : 30;
    const since = new Date(Date.now() - days * 86400000);
    const [trend, bestSellers, slowMoving, stockHealth, runningOut] = await Promise.all([
      this.db.$queryRaw<Array<{ day: Date; sales: Prisma.Decimal; transactions: bigint }>>(Prisma.sql`
        SELECT DATE(s."saleDate") AS day, COALESCE(SUM(s."total"), 0)::numeric AS sales,
          COUNT(*) AS transactions
        FROM "Sale" s
        WHERE s."businessId" = ${u.businessId}::uuid AND s."saleDate" >= ${since}
          AND s."status" NOT IN ('void', 'refunded')
        GROUP BY DATE(s."saleDate") ORDER BY day ASC
      `),
      this.db.$queryRaw<Array<{ productId: string; variantId: string | null; name: string; variantName: string | null; unit: string; quantity: Prisma.Decimal; revenue: Prisma.Decimal }>>(Prisma.sql`
        SELECT p."id" AS "productId", v."id" AS "variantId", p."name", v."name" AS "variantName", COALESCE(v."unit", p."unit") AS "unit",
          COALESCE(SUM(CASE WHEN si."quantity" > 0 THEN si."stockQuantity" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END), 0)::numeric AS quantity,
          COALESCE(SUM(CASE WHEN si."quantity" > 0 THEN
            si."lineTotal" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity"
            - CASE WHEN s."subtotal" > 0 THEN s."discount" * si."lineTotal" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" / s."subtotal" ELSE 0 END
            ELSE 0 END), 0)::numeric AS revenue
        FROM "Product" p JOIN "SaleItem" si ON si."productId" = p."id"
        JOIN "Sale" s ON s."id" = si."saleId"
        LEFT JOIN "ProductVariant" v ON v."id" = si."variantId"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL
          AND s."saleDate" >= ${since} AND s."status" NOT IN ('void', 'refunded')
        GROUP BY p."id", v."id", p."name", v."name", COALESCE(v."unit", p."unit") ORDER BY quantity DESC LIMIT 5
      `),
      this.db.$queryRaw<Array<{ productId: string; variantId: string | null; name: string; variantName: string | null; unit: string; quantity: Prisma.Decimal; onHand: Prisma.Decimal }>>(Prisma.sql`
        WITH velocity AS (
          SELECT si."productId", si."variantId", SUM(CASE WHEN si."quantity" > 0 THEN si."stockQuantity" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END)::numeric AS quantity
          FROM "SaleItem" si JOIN "Sale" s ON s."id" = si."saleId"
          WHERE s."businessId" = ${u.businessId}::uuid AND s."saleDate" >= ${since}
            AND s."status" NOT IN ('void', 'refunded') GROUP BY si."productId", si."variantId"
        )
        SELECT p."id" AS "productId", pv."id" AS "variantId", p."name", pv."name" AS "variantName", COALESCE(pv."unit", p."unit") AS "unit",
          COALESCE(v.quantity, 0)::numeric AS quantity, COALESCE(pv."quantity", sl."quantity", 0)::numeric AS "onHand"
        FROM "Product" p
        LEFT JOIN "ProductVariant" pv ON pv."productId" = p."id" AND pv."deletedAt" IS NULL AND pv."active" = true
        LEFT JOIN "StockLevel" sl ON sl."productId" = p."id" AND pv."id" IS NULL
        LEFT JOIN velocity v ON v."productId" = p."id" AND v."variantId" IS NOT DISTINCT FROM pv."id"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
        ORDER BY v.quantity ASC NULLS FIRST, p."name" ASC, pv."name" ASC LIMIT 5
      `),
      this.db.$queryRaw<Array<{ total: bigint; healthy: bigint }>>(Prisma.sql`
        WITH tracked AS (
          SELECT COALESCE(sl."quantity", 0)::numeric AS quantity, p."minStock" AS "minStock"
          FROM "Product" p LEFT JOIN "StockLevel" sl ON sl."productId" = p."id"
          WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
            AND NOT EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId" = p."id" AND v."deletedAt" IS NULL)
          UNION ALL
          SELECT v."quantity"::numeric AS quantity, v."minStock" AS "minStock"
          FROM "ProductVariant" v JOIN "Product" p ON p."id" = v."productId"
          WHERE v."businessId" = ${u.businessId}::uuid AND v."deletedAt" IS NULL
            AND p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
        )
        SELECT COUNT(*) AS total,
          COUNT(*) FILTER (WHERE quantity > "minStock") AS healthy
        FROM tracked
      `),
      this.db.$queryRaw<Array<{ productId: string; variantId: string | null; name: string; variantName: string | null; unit: string; onHand: Prisma.Decimal; daily: Prisma.Decimal }>>(Prisma.sql`
        WITH velocity AS (
          SELECT si."productId", si."variantId", SUM(CASE WHEN si."quantity" > 0 THEN si."stockQuantity" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END)::numeric AS quantity
          FROM "SaleItem" si JOIN "Sale" s ON s."id" = si."saleId"
          WHERE s."businessId" = ${u.businessId}::uuid AND s."saleDate" >= ${since}
            AND s."status" NOT IN ('void', 'refunded') GROUP BY si."productId", si."variantId"
        )
        SELECT p."id" AS "productId", pv."id" AS "variantId", p."name", pv."name" AS "variantName", COALESCE(pv."unit", p."unit") AS "unit", COALESCE(pv."quantity", sl."quantity", 0)::numeric AS "onHand",
          (v.quantity / ${days}::numeric)::numeric AS daily
        FROM "Product" p
        LEFT JOIN "ProductVariant" pv ON pv."productId" = p."id" AND pv."deletedAt" IS NULL AND pv."active" = true
        LEFT JOIN "StockLevel" sl ON sl."productId" = p."id" AND pv."id" IS NULL
        JOIN velocity v ON v."productId" = p."id" AND v."variantId" IS NOT DISTINCT FROM pv."id"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
          AND v.quantity > 0
          AND COALESCE(pv."quantity", sl."quantity", 0) / (v.quantity / ${days}::numeric) <= 14
        ORDER BY COALESCE(pv."quantity", sl."quantity", 0) / (v.quantity / ${days}::numeric) ASC LIMIT 10
      `),
    ]);
    const total = Number(stockHealth[0]?.total ?? 0);
    return {
      source: "This business's recorded sales and stock only",
      days,
      trend: trend.map((r) => ({ date: r.day, sales: Number(r.sales), transactions: Number(r.transactions) })),
      bestSellers: bestSellers.map((r) => ({ id: r.variantId ?? r.productId, productId: r.productId, variantId: r.variantId, name: r.variantName ? `${r.name} · ${r.variantName}` : r.name, unit: r.unit, quantitySold: Number(r.quantity), revenue: Number(r.revenue) })),
      slowMoving: slowMoving.map((r) => ({ id: r.variantId ?? r.productId, productId: r.productId, variantId: r.variantId, name: r.variantName ? `${r.name} · ${r.variantName}` : r.name, unit: r.unit, quantitySold: Number(r.quantity), onHand: Number(r.onHand) })),
      runningOut: runningOut.map((r) => ({ id: r.variantId ?? r.productId, productId: r.productId, variantId: r.variantId, name: r.variantName ? `${r.name} · ${r.variantName}` : r.name, unit: r.unit, onHand: Number(r.onHand), estimatedDaysRemaining: Math.ceil(Number(r.onHand) / Number(r.daily)) })),
      stockHealth: total ? Math.round(Number(stockHealth[0].healthy) / total * 100) : null,
      note: "Run-out timing is an estimate from the selected period's average sales velocity, not a guarantee."
    };
  }
  @Get("sales") @Roles("OWNER", "MANAGER") async sales(@Me() u, @Query("from") from?: string, @Query("to") to?: string, @Query("page") pageText?: string, @Query("limit") limitText?: string) {
    const start = from ? new Date(from) : new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const end = to ? new Date(to) : new Date();
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || start > end) throw new BadRequestException("Invalid date range");
    const page = Math.max(1, Number(pageText) || 1);
    const limit = Math.min(100, Math.max(1, Number(limitText) || 50));
    const where = { businessId: u.businessId, saleDate: { gte: start, lte: end }, status: { not: "void" } };
    const paymentsWhere = { businessId: u.businessId, status: "PAID", OR: [{ settledAt: { gte: start, lte: end } }, { settledAt: null, createdAt: { gte: start, lte: end } }] };
    const [saleTotals, paymentGroups, periodReturns, salesProfit, returnTotals, restockedCost, rows] = await Promise.all([
      this.db.sale.aggregate({ where, _count: { _all: true }, _sum: { subtotal: true, discount: true, tax: true, balanceDue: true } }),
      this.db.payment.groupBy({ by: ["method"], where: paymentsWhere, _sum: { amount: true } }),
      this.db.returnRecord.count({ where: { businessId: u.businessId, createdAt: { gte: start, lte: end } } }),
      this.db.$queryRaw<Array<{ profit: Prisma.Decimal }>>(Prisma.sql`
        SELECT COALESCE(SUM(si."lineTotal" - CASE WHEN s."subtotal" > 0 THEN s."discount" * si."lineTotal" / s."subtotal" ELSE 0 END - si."quantity" * si."unitCost"), 0)::numeric AS profit
        FROM "SaleItem" si JOIN "Sale" s ON s."id" = si."saleId"
        WHERE s."businessId" = ${u.businessId}::uuid AND s."saleDate" >= ${start} AND s."saleDate" <= ${end} AND s."status" <> 'void'
      `),
      this.db.returnRecord.aggregate({ where: { businessId: u.businessId, createdAt: { gte: start, lte: end } }, _sum: { total: true } }),
      this.db.$queryRaw<Array<{ cost: Prisma.Decimal }>>(Prisma.sql`
        SELECT COALESCE(SUM(ri."quantity" * si."unitCost"), 0)::numeric AS cost
        FROM "ReturnRecord" r JOIN "ReturnItem" ri ON ri."returnId" = r."id"
        JOIN "SaleItem" si ON si."id" = ri."saleItemId"
        WHERE r."businessId" = ${u.businessId}::uuid AND r."createdAt" >= ${start} AND r."createdAt" <= ${end} AND r."restock" = true
      `),
      this.db.sale.findMany({ where, select: { id: true, saleNumber: true, saleDate: true, total: true, amountPaid: true, balanceDue: true, status: true, customer: { select: { id: true, name: true } } }, orderBy: { saleDate: "desc" }, skip: (page - 1) * limit, take: limit }),
    ]);
    const paymentMethods: Record<string, number> = {};
    for (const group of paymentGroups) paymentMethods[group.method] = Number(group._sum.amount ?? 0);
    const originalSalesTotal = Number(saleTotals._sum.subtotal ?? 0) - Number(saleTotals._sum.discount ?? 0) + Number(saleTotals._sum.tax ?? 0);
    const returnedTotal = Number(returnTotals._sum.total ?? 0);
    const profit = Number(salesProfit[0]?.profit ?? 0) - returnedTotal + Number(restockedCost[0]?.cost ?? 0);
    const paid = Object.values(paymentMethods).reduce((sum, value) => sum + value, 0);
    return {
      count: saleTotals._count._all,
      total: Math.round((originalSalesTotal - returnedTotal) * 100) / 100,
      paid: Math.round(paid * 100) / 100,
      outstanding: Number(saleTotals._sum.balanceDue ?? 0),
      profit: Math.round(profit * 100) / 100,
      paymentMethods,
      sales: rows,
      returns: { count: periodReturns, total: returnedTotal },
      meta: { page, limit, total: saleTotals._count._all, totalPages: Math.ceil(saleTotals._count._all / limit) },
    };
  }
  @Get("customer-debt") @Roles("OWNER", "MANAGER") async customerDebt(@Me() u, @Query("page") pageText?: string, @Query("limit") limitText?: string) {
    const page = Math.max(1, Number(pageText) || 1);
    const limit = Math.min(100, Math.max(1, Number(limitText) || 100));
    const where = { businessId: u.businessId, deletedAt: null, balance: { gt: 0 } };
    const [summary, count, customers] = await Promise.all([
      this.db.customer.aggregate({ where, _sum: { balance: true } }),
      this.db.customer.count({ where }),
      this.db.customer.findMany({ where, select: { id: true, name: true, phone: true, balance: true }, orderBy: { balance: "desc" }, skip: (page - 1) * limit, take: limit }),
    ]);
    return { total: Number(summary._sum.balance ?? 0), customers, meta: { page, limit, total: count, totalPages: Math.ceil(count / limit) } };
  }
  @Get("products") @Roles("OWNER", "MANAGER") async products(@Me() u) {
    const rows = await this.db.$queryRaw<Array<{ id: string; variantId: string | null; name: string; variantName: string | null; sku: string | null; unit: string; quantitySold: Prisma.Decimal; revenue: Prisma.Decimal; transactions: bigint }>>(Prisma.sql`
      SELECT p."id", v."id" AS "variantId", p."name", v."name" AS "variantName", COALESCE(v."sku", p."sku") AS "sku", COALESCE(v."unit", p."unit") AS "unit",
        COALESCE(SUM(CASE WHEN si."quantity" > 0 THEN si."stockQuantity" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END), 0)::numeric AS "quantitySold",
        COALESCE(SUM(CASE WHEN si."quantity" > 0 THEN si."lineTotal" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END
          - CASE WHEN s."subtotal" > 0 THEN s."discount" * (CASE WHEN si."quantity" > 0 THEN si."lineTotal" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END) / s."subtotal" ELSE 0 END), 0)::numeric AS revenue,
        COUNT(DISTINCT si."saleId") AS transactions
      FROM "SaleItem" si JOIN "Sale" s ON s."id" = si."saleId"
      JOIN "Product" p ON p."id" = si."productId"
      LEFT JOIN "ProductVariant" v ON v."id" = si."variantId"
      WHERE si."businessId" = ${u.businessId}::uuid AND s."status" NOT IN ('void', 'refunded')
      GROUP BY p."id", v."id", p."name", v."name", COALESCE(v."sku", p."sku"), COALESCE(v."unit", p."unit")
      ORDER BY "quantitySold" DESC LIMIT 100
    `);
    return rows.map((row) => ({
      product: { id: row.id, name: row.variantName ? `${row.name} · ${row.variantName}` : row.name, sku: row.sku, unit: row.unit },
      productId: row.id,
      variantId: row.variantId,
      quantitySold: Number(row.quantitySold),
      revenue: Number(row.revenue),
      transactions: Number(row.transactions),
    }));
  }
  @Get("stock-summary") @Roles("OWNER", "MANAGER") async stockSummary(@Me() u) {
    const [row] = await this.db.$queryRaw<Array<{ totalProducts: bigint; stockValue: Prisma.Decimal; retailValue: Prisma.Decimal; lowStock: bigint; outOfStock: bigint }>>(Prisma.sql`
      WITH tracked AS (
        SELECT COALESCE(s."quantity", 0)::numeric AS quantity, p."buyingPrice", p."sellingPrice", p."minStock"
        FROM "Product" p LEFT JOIN "StockLevel" s ON s."productId" = p."id"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
          AND NOT EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId" = p."id" AND v."deletedAt" IS NULL)
        UNION ALL
        SELECT v."quantity"::numeric AS quantity, v."buyingPrice", v."sellingPrice", v."minStock"
        FROM "ProductVariant" v JOIN "Product" p ON p."id" = v."productId"
        WHERE v."businessId" = ${u.businessId}::uuid AND v."deletedAt" IS NULL
          AND p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
      )
      SELECT COUNT(*) AS "totalProducts",
        COALESCE(SUM(quantity * "buyingPrice"), 0)::numeric AS "stockValue",
        COALESCE(SUM(quantity * "sellingPrice"), 0)::numeric AS "retailValue",
        COUNT(*) FILTER (WHERE quantity > 0 AND quantity <= "minStock") AS "lowStock",
        COUNT(*) FILTER (WHERE quantity <= 0) AS "outOfStock"
      FROM tracked
    `);
    const stockValue = Number(row.stockValue), retailValue = Number(row.retailValue);
    return {
      totalProducts: Number(row.totalProducts), stockValue, retailValue,
      lowStock: Number(row.lowStock), outOfStock: Number(row.outOfStock),
      potentialProfit: retailValue - stockValue,
    };
  }
  @Get("low-stock") @Roles("OWNER", "MANAGER", "STOREKEEPER") async lowStock(@Me() u, @Query("page") pageText?: string, @Query("limit") limitText?: string) {
    const page = Math.max(1, Number(pageText) || 1);
    const limit = Math.min(100, Math.max(1, Number(limitText) || 100));
    const tracked = Prisma.sql`WITH tracked AS (
      SELECT p."id", p."id" AS "productId", NULL::uuid AS "variantId", p."name", p."sku", p."unit", p."minStock",
        COALESCE(s."quantity", 0)::numeric AS quantity
      FROM "Product" p LEFT JOIN "StockLevel" s ON s."productId" = p."id"
      WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
        AND NOT EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId" = p."id" AND v."deletedAt" IS NULL)
      UNION ALL
      SELECT v."id", p."id" AS "productId", v."id" AS "variantId", p."name" || ' · ' || v."name" AS "name", v."sku", v."unit", v."minStock",
        v."quantity"::numeric AS quantity
      FROM "ProductVariant" v JOIN "Product" p ON p."id" = v."productId"
      WHERE v."businessId" = ${u.businessId}::uuid AND v."deletedAt" IS NULL AND v."active" = true
        AND p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
    )`;
    const [count, matches] = await Promise.all([
      this.db.$queryRaw<Array<{ count: bigint }>>(Prisma.sql`${tracked} SELECT COUNT(*) AS count FROM tracked WHERE quantity <= "minStock"`),
      this.db.$queryRaw<Array<{ id: string; productId: string; variantId: string | null; name: string; sku: string | null; unit: string; minStock: Prisma.Decimal; quantity: Prisma.Decimal }>>(Prisma.sql`${tracked}
        SELECT * FROM tracked WHERE quantity <= "minStock" ORDER BY "name" ASC LIMIT ${limit} OFFSET ${(page - 1) * limit}
      `),
    ]);
    const data = matches.map((row) => ({
      id: row.id, productId: row.productId, variantId: row.variantId,
      name: row.name, sku: row.sku, unit: row.unit,
      quantity: Number(row.quantity), minStock: Number(row.minStock),
      suggestedReorder: Math.max(Number(row.minStock) * 2 - Number(row.quantity), 0),
    }));
    const total = Number(count[0]?.count ?? 0);
    return { data, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
  }
  @Get("stock-movements") @Roles("OWNER", "MANAGER") movements(@Me() u, @Query("limit") limitText?: string) {
    return this.db.stockMovement.findMany({ where: { businessId: u.businessId }, include: { product: true }, orderBy: { createdAt: "desc" }, take: Math.min(500, Math.max(1, Number(limitText) || 100)) });
  }
}
class DashboardPreferenceDto {
  @IsArray() @ArrayMaxSize(12) @IsString({ each: true }) layout: string[];
  @IsArray() @ArrayMaxSize(12) @IsString({ each: true }) favorites: string[];
}

const BOARD_TILES = ["attention", "quick_actions", "fast_movers", "sales_summary", "stock_health", "debt"];
const BOARD_ACTIONS = ["new_sale", "add_product", "receive_stock", "scan_barcode", "view_debt", "view_reports", "stock_count"];

@Controller("dashboard") @UseGuards(AuthGuard)
class DashboardBoardController {
  constructor(private db: PrismaService) {}

  @Get("board") async board(@Me() u) {
    const [user, preference, fastMovers, stockSummary, unreadAlerts] = await Promise.all([
      this.db.user.findFirst({ where: { id: u.sub, businessId: u.businessId }, select: { fullName: true, business: { select: { name: true } } } }),
      this.db.$queryRaw<Array<{ layout: unknown; favorites: unknown }>>(Prisma.sql`SELECT "layout", "favorites" FROM "DashboardPreference" WHERE "userId" = ${u.sub}::uuid AND "businessId" = ${u.businessId}::uuid AND "role" = ${u.role}::"Role" LIMIT 1`),
      this.db.$queryRaw<Array<Record<string, unknown>>>(Prisma.sql`
        SELECT p."id", p."name", p."sellingPrice", p."imageUrl", p."unit", p."minStock",
          COALESCE(sl."quantity", 0) AS "quantity", SUM(si."stockQuantity") AS "quantitySold"
        FROM "SaleItem" si JOIN "Sale" s ON s."id" = si."saleId" AND s."businessId" = si."businessId"
        JOIN "Product" p ON p."id" = si."productId" AND p."businessId" = si."businessId"
        LEFT JOIN "StockLevel" sl ON sl."productId" = p."id"
        WHERE si."businessId" = ${u.businessId}::uuid AND s."saleDate" >= NOW() - INTERVAL '30 days'
          AND s."status" NOT IN ('void','refunded') AND p."active" = true AND p."deletedAt" IS NULL
          AND NOT EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId" = p."id" AND v."deletedAt" IS NULL AND v."active" = true)
          AND (${u.role === "CASHIER" ? Prisma.sql`s."userId" = ${u.sub}::uuid` : u.role === "STOREKEEPER" ? Prisma.sql`FALSE` : Prisma.sql`TRUE`})
        GROUP BY p."id", sl."quantity" ORDER BY SUM(si."stockQuantity") DESC LIMIT 8
      `),
      this.db.$queryRaw<Array<{ productCount: bigint; lowStock: bigint; outOfStock: bigint }>>(Prisma.sql`
        WITH tracked AS (
          SELECT p."id", p."minStock", COALESCE(sl."quantity", 0)::numeric AS quantity
          FROM "Product" p LEFT JOIN "StockLevel" sl ON sl."productId" = p."id"
          WHERE p."businessId" = ${u.businessId}::uuid AND p."active" = true AND p."deletedAt" IS NULL
            AND NOT EXISTS (SELECT 1 FROM "ProductVariant" v WHERE v."productId" = p."id" AND v."deletedAt" IS NULL)
          UNION ALL
          SELECT v."id", v."minStock", v."quantity"::numeric
          FROM "ProductVariant" v JOIN "Product" p ON p."id" = v."productId"
          WHERE v."businessId" = ${u.businessId}::uuid AND v."active" = true AND v."deletedAt" IS NULL AND p."deletedAt" IS NULL AND p."active" = true
        )
        SELECT (SELECT COUNT(*) FROM "Product" WHERE "businessId" = ${u.businessId}::uuid AND "active" = true AND "deletedAt" IS NULL) AS "productCount",
          COUNT(*) FILTER (WHERE quantity > 0 AND "minStock" > 0 AND quantity <= "minStock") AS "lowStock",
          COUNT(*) FILTER (WHERE quantity <= 0) AS "outOfStock" FROM tracked
      `),
      this.db.alert.count({ where: { businessId: u.businessId, read: false, OR: [{ userId: null }, { userId: u.sub }] } }),
    ]);
    const defaults: Record<string, string[]> = {
      OWNER: BOARD_TILES, MANAGER: BOARD_TILES,
      CASHIER: ["quick_actions", "fast_movers", "sales_summary"],
      STOREKEEPER: ["attention", "quick_actions", "stock_health"],
    };
    const layout = preference[0]?.layout as string[] | undefined;
    const favorites = preference[0]?.favorites as string[] | undefined;
    const favoriteIds = favorites?.filter((id) => /^[0-9a-f-]{36}$/i.test(id)) ?? [];
    const favoriteProducts = favoriteIds.length ? await this.db.product.findMany({
      where: { id: { in: favoriteIds }, businessId: u.businessId, deletedAt: null, active: true },
      select: { id: true, name: true, sellingPrice: true, imageUrl: true, unit: true, minStock: true, stock: { select: { quantity: true } } },
    }) : [];
    return {
      user: { name: user?.fullName ?? "there", role: u.role },
      businessName: user?.business.name ?? "Your shop",
      defaultLayout: defaults[u.role] ?? ["quick_actions", "fast_movers"],
      preferencesSaved: preference.length > 0,
      layout: layout?.filter((id) => BOARD_TILES.includes(id)) ?? null,
      favorites: favorites?.filter((id) => BOARD_ACTIONS.includes(id) || /^[0-9a-f-]{36}$/i.test(id)) ?? [],
      favoriteProducts: favoriteProducts.map((p) => ({ id: p.id, name: p.name, sellingPrice: Number(p.sellingPrice), imageUrl: p.imageUrl, unit: p.unit, minStock: Number(p.minStock), quantity: Number(p.stock?.quantity ?? 0) })),
      summary: { ...stockSummary[0], productCount: Number(stockSummary[0]?.productCount ?? 0), lowStock: Number(stockSummary[0]?.lowStock ?? 0), outOfStock: Number(stockSummary[0]?.outOfStock ?? 0), unreadAlerts },
      fastMovers: fastMovers.map((p) => ({ ...p, quantity: Number(p.quantity), quantitySold: Number(p.quantitySold), sellingPrice: Number(p.sellingPrice), minStock: Number(p.minStock) })),
    };
  }

  @Put("board/preferences") async save(@Me() u, @Body() dto: DashboardPreferenceDto) {
    if (dto.layout.some((id) => !BOARD_TILES.includes(id)) || dto.favorites.some((id) => !BOARD_ACTIONS.includes(id) && !/^[0-9a-f-]{36}$/i.test(id)))
      throw new BadRequestException("Unknown dashboard tile or favorite");
    const layout = [...new Set(dto.layout)];
    const favorites = [...new Set(dto.favorites)];
    const productIds = favorites.filter((id) => !BOARD_ACTIONS.includes(id));
    if (productIds.length && await this.db.product.count({ where: { id: { in: productIds }, businessId: u.businessId, deletedAt: null, active: true } }) !== productIds.length)
      throw new NotFoundException("One or more favorite products were not found");
    const rows = await this.db.$queryRaw<Array<{ layout: unknown; favorites: unknown; updatedAt: Date }>>(Prisma.sql`
      INSERT INTO "DashboardPreference" ("id", "businessId", "userId", "role", "layout", "favorites", "createdAt", "updatedAt")
      VALUES (gen_random_uuid(), ${u.businessId}::uuid, ${u.sub}::uuid, ${u.role}::"Role", ${JSON.stringify(layout)}::jsonb, ${JSON.stringify(favorites)}::jsonb, NOW(), NOW())
      ON CONFLICT ("userId", "role") DO UPDATE SET "layout" = EXCLUDED."layout", "favorites" = EXCLUDED."favorites", "updatedAt" = NOW()
      WHERE "DashboardPreference"."businessId" = ${u.businessId}::uuid
      RETURNING "layout", "favorites", "updatedAt"
    `);
    if (!rows.length) throw new NotFoundException("Dashboard preferences not found");
    return rows[0];
  }
}

@Module({ controllers: [AlertsController, ReportsController, DashboardBoardController], providers: [AuthGuard] })
export class InsightsModule {}
