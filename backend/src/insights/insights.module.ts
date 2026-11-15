import { BadRequestException, Controller, Get, Patch, Param, ParseUUIDPipe, Query, UseGuards, Module, NotFoundException, Post, Body } from "@nestjs/common";
import { IsDateString, IsIn, IsOptional } from "class-validator";
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
    const where: any = { businessId: u.businessId, ...(unread === "true" ? { read: false } : {}) };
    const [total, unreadCount, rows] = await Promise.all([
      this.db.alert.count({ where }),
      this.db.alert.count({ where: { businessId: u.businessId, read: false } }),
      this.db.alert.findMany({ where, orderBy: { createdAt: "desc" }, skip: (page - 1) * limit, take: limit }),
    ]);
    const products = await this.db.product.findMany({ where: { id: { in: rows.map((a) => a.productId) }, businessId: u.businessId }, select: { id: true, name: true, minStock: true } });
    return { data: rows.map((a) => ({ ...a, product: products.find((p) => p.id === a.productId) ?? null })), unreadCount, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
  }
  @Patch("read-all") async readAll(@Me() u) {
    const result = await this.db.alert.updateMany({ where: { businessId: u.businessId, read: false }, data: { read: true } });
    return { updated: result.count };
  }
  @Patch(":id/read") async read(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const result = await this.db.alert.updateMany({ where: { id, businessId: u.businessId }, data: { read: true } });
    if (!result.count) throw new NotFoundException("Alert not found");
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
  @Get("dashboard") @Roles("OWNER", "MANAGER", "CASHIER") async dashboard(@Me() u) {
    const [products, salesToday, salesMonth, stockCounts, unreadAlerts] = await Promise.all([
      this.db.product.count({ where: { businessId: u.businessId, deletedAt: null, active: true } }),
      this.db.sale.aggregate({ where: { businessId: u.businessId, saleDate: { gte: new Date(new Date().setHours(0, 0, 0, 0)) }, status: { notIn: ["void", "refunded"] } }, _sum: { total: true }, _count: true }),
      this.db.sale.aggregate({ where: { businessId: u.businessId, saleDate: { gte: new Date(new Date().getFullYear(), new Date().getMonth(), 1) }, status: { notIn: ["void", "refunded"] } }, _sum: { total: true }, _count: true }),
      this.db.$queryRaw<Array<{ lowStock: bigint; outOfStock: bigint }>>(Prisma.sql`
        SELECT COUNT(*) FILTER (WHERE COALESCE(s."quantity", 0) <= 0) AS "outOfStock",
          COUNT(*) FILTER (WHERE COALESCE(s."quantity", 0) > 0 AND p."minStock" > 0 AND s."quantity" <= p."minStock") AS "lowStock"
        FROM "Product" p LEFT JOIN "StockLevel" s ON s."productId" = p."id"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
      `),
      this.db.alert.count({ where: { businessId: u.businessId, read: false } }),
    ]);
    const lowStock = Number(stockCounts[0]?.lowStock ?? 0);
    const outOfStock = Number(stockCounts[0]?.outOfStock ?? 0);
    return { productCount: products, salesToday: Number(salesToday._sum.total ?? 0), saleCountToday: salesToday._count, salesMonth: Number(salesMonth._sum.total ?? 0), saleCountMonth: salesMonth._count, lowStock, outOfStock, unreadAlerts };
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
    const rows = await this.db.$queryRaw<Array<{ id: string; name: string; sku: string | null; quantitySold: Prisma.Decimal; revenue: Prisma.Decimal; transactions: bigint }>>(Prisma.sql`
      SELECT p."id", p."name", p."sku",
        COALESCE(SUM(GREATEST(si."quantity" - si."returnedQty", 0)), 0)::numeric AS "quantitySold",
        COALESCE(SUM(CASE WHEN si."quantity" > 0 THEN si."lineTotal" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END
          - CASE WHEN s."subtotal" > 0 THEN s."discount" * (CASE WHEN si."quantity" > 0 THEN si."lineTotal" * GREATEST(si."quantity" - si."returnedQty", 0) / si."quantity" ELSE 0 END) / s."subtotal" ELSE 0 END), 0)::numeric AS revenue,
        COUNT(DISTINCT si."saleId") AS transactions
      FROM "SaleItem" si JOIN "Sale" s ON s."id" = si."saleId"
      JOIN "Product" p ON p."id" = si."productId"
      WHERE si."businessId" = ${u.businessId}::uuid AND s."status" NOT IN ('void', 'refunded')
      GROUP BY p."id", p."name", p."sku"
      ORDER BY "quantitySold" DESC LIMIT 100
    `);
    return rows.map((row) => ({
      product: { id: row.id, name: row.name, sku: row.sku },
      quantitySold: Number(row.quantitySold),
      revenue: Number(row.revenue),
      transactions: Number(row.transactions),
    }));
  }
  @Get("stock-summary") @Roles("OWNER", "MANAGER") async stockSummary(@Me() u) {
    const [row] = await this.db.$queryRaw<Array<{ totalProducts: bigint; stockValue: Prisma.Decimal; retailValue: Prisma.Decimal; lowStock: bigint; outOfStock: bigint }>>(Prisma.sql`
      SELECT COUNT(*) AS "totalProducts",
        COALESCE(SUM(COALESCE(s."quantity", 0) * p."buyingPrice"), 0)::numeric AS "stockValue",
        COALESCE(SUM(COALESCE(s."quantity", 0) * p."sellingPrice"), 0)::numeric AS "retailValue",
        COUNT(*) FILTER (WHERE COALESCE(s."quantity", 0) > 0 AND COALESCE(s."quantity", 0) <= p."minStock") AS "lowStock",
        COUNT(*) FILTER (WHERE COALESCE(s."quantity", 0) <= 0) AS "outOfStock"
      FROM "Product" p LEFT JOIN "StockLevel" s ON s."productId" = p."id"
      WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
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
    const [count, matches] = await Promise.all([
      this.db.$queryRaw<Array<{ count: bigint }>>(Prisma.sql`
        SELECT COUNT(*) AS count FROM "Product" p LEFT JOIN "StockLevel" s ON s."productId" = p."id"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
          AND COALESCE(s."quantity", 0) <= p."minStock"
      `),
      this.db.$queryRaw<Array<{ id: string }>>(Prisma.sql`
        SELECT p."id" FROM "Product" p LEFT JOIN "StockLevel" s ON s."productId" = p."id"
        WHERE p."businessId" = ${u.businessId}::uuid AND p."deletedAt" IS NULL AND p."active" = true
          AND COALESCE(s."quantity", 0) <= p."minStock"
        ORDER BY p."name" ASC LIMIT ${limit} OFFSET ${(page - 1) * limit}
      `),
    ]);
    const rows = matches.length ? await this.db.product.findMany({ where: { id: { in: matches.map((row) => row.id) }, businessId: u.businessId }, include: { stock: true, category: true } }) : [];
    const byId = new Map(rows.map((row) => [row.id, row]));
    const data = matches.flatMap(({ id }) => {
      const product = byId.get(id);
      if (!product) return [];
      const quantity = Number(product.stock?.quantity ?? 0);
      return [{ ...product, quantity, suggestedReorder: Math.max(Number(product.minStock) * 2 - quantity, 0) }];
    });
    const total = Number(count[0]?.count ?? 0);
    return { data, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
  }
  @Get("stock-movements") @Roles("OWNER", "MANAGER") movements(@Me() u, @Query("limit") limitText?: string) {
    return this.db.stockMovement.findMany({ where: { businessId: u.businessId }, include: { product: true }, orderBy: { createdAt: "desc" }, take: Math.min(500, Math.max(1, Number(limitText) || 100)) });
  }
}
@Module({ controllers: [AlertsController, ReportsController], providers: [AuthGuard] })
export class InsightsModule {}
