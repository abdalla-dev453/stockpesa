import { BadRequestException, ConflictException, Controller, Get, Post, Patch, Param, ParseUUIDPipe, Body, UseGuards, Module, NotFoundException } from "@nestjs/common";
import { Type } from "class-transformer";
import { IsNumber, IsOptional, IsString, IsUUID, Min } from "class-validator";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me, Roles } from "../common/auth";
import { StockModule, StockService } from "../stock/stock.module";

class CountCreateDto {
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsUUID() clientId?: string;
}
class CountItemDto {
  @IsUUID() productId: string;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) countedQuantity?: number;
}

@Controller("stock-counts") @UseGuards(AuthGuard)
class StockCountsController {
  constructor(private db: PrismaService, private stock: StockService) {}
  @Post() @Roles("OWNER", "MANAGER") async create(@Me() u, @Body() d: CountCreateDto) {
    return this.db.$transaction(async (tx) => {
      if (d.clientId) {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":stock-count-create:" + d.clientId}))`;
        const existing = await tx.stockCount.findFirst({
          where: { id: d.clientId, businessId: u.businessId },
          include: { items: { include: { product: true } } },
        });
        if (existing) {
          if (existing.userId !== u.sub || existing.notes !== d.notes) {
            throw new ConflictException("Stock count ID was already used for a different request");
          }
          return existing;
        }
      }
      const products = await tx.product.findMany({
        where: { businessId: u.businessId, deletedAt: null, active: true },
        include: { stock: true }, orderBy: { name: "asc" },
      });
      if (!products.length) throw new BadRequestException("There are no active products to count");
      const count = await tx.stockCount.create({ data: {
        ...(d.clientId ? { id: d.clientId } : {}),
        businessId: u.businessId, userId: u.sub, notes: d.notes,
        items: { create: products.map((p) => ({ productId: p.id, systemQty: p.stock?.quantity ?? 0 })) },
      }, include: { items: { include: { product: true } } } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "stock_count.started", entity: "stock_count", entityId: count.id, meta: { itemCount: products.length } } });
      return count;
    });
  }
  @Get() @Roles("OWNER", "MANAGER", "STOREKEEPER") list(@Me() u) {
    return this.db.stockCount.findMany({ where: { businessId: u.businessId }, include: { _count: { select: { items: true } } }, orderBy: { createdAt: "desc" }, take: 100 });
  }
  @Get(":id") @Roles("OWNER", "MANAGER", "STOREKEEPER") async get(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const count = await this.db.stockCount.findFirst({ where: { id, businessId: u.businessId }, include: { items: { include: { product: true } } } });
    if (!count) throw new NotFoundException("Stock count not found");
    return count;
  }
  @Post(":id/items") @Roles("OWNER", "MANAGER", "STOREKEEPER") async addOrCount(
    @Me() u, @Param("id", ParseUUIDPipe) id: string, @Body() d: CountItemDto,
  ) {
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${id + ":stock-count"}))`;
      const count = await tx.stockCount.findFirst({ where: { id, businessId: u.businessId } });
      if (!count) throw new NotFoundException("Stock count not found");
      if (count.status !== "open") throw new BadRequestException("This stock count is already closed");
      const product = await tx.product.findFirst({ where: { id: d.productId, businessId: u.businessId, deletedAt: null } });
      if (!product) throw new NotFoundException("Product not found");
      const current = await tx.stockCountItem.findFirst({ where: { stockCountId: id, productId: d.productId } });
      if (current) return tx.stockCountItem.update({ where: { id: current.id }, data: { countedQty: d.countedQuantity } });
      const level = await tx.stockLevel.findUnique({ where: { productId: d.productId } });
      return tx.stockCountItem.create({ data: { stockCountId: id, productId: d.productId, systemQty: level?.quantity ?? 0, countedQty: d.countedQuantity } });
    });
  }
  @Post(":id/complete") @Roles("OWNER", "MANAGER") async complete(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${id + ":stock-count"}))`;
      const count = await tx.stockCount.findFirst({ where: { id, businessId: u.businessId }, include: { items: true } });
      if (!count) throw new NotFoundException("Stock count not found");
      if (count.status !== "open") throw new BadRequestException("This stock count is already closed");
      if (!count.items.length || count.items.some((i) => i.countedQty === null))
        throw new BadRequestException("Enter a counted quantity for every item before completing the count");
      const results = [];
      for (const item of count.items) {
        const currentLevel = await tx.stockLevel.findUnique({ where: { productId: item.productId } });
        const change = Number(item.countedQty) - Number(currentLevel?.quantity ?? 0);
        if (change) results.push(await this.stock.move(tx, {
          businessId: u.businessId, userId: u.sub, productId: item.productId,
          type: change > 0 ? "adjustment" : "adjustment", change,
          reason: "stock count", reference: id,
        }));
      }
      await tx.stockCount.update({ where: { id }, data: { status: "completed" } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "stock_count.completed", entity: "stock_count", entityId: id, meta: { adjustments: results.length } } });
      return { id, status: "completed", adjustments: results.length };
    }, { timeout: 120000 });
  }
  @Post(":id/cancel") @Roles("OWNER", "MANAGER") async cancel(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${id + ":stock-count"}))`;
      const count = await tx.stockCount.findFirst({ where: { id, businessId: u.businessId } });
      if (!count) throw new NotFoundException("Stock count not found");
      if (count.status !== "open") throw new BadRequestException("Only an open count can be cancelled");
      await tx.stockCount.update({ where: { id }, data: { status: "cancelled" } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "stock_count.cancelled", entity: "stock_count", entityId: id } });
      return { id, status: "cancelled" };
    });
  }
}
@Module({ imports: [StockModule], controllers: [StockCountsController], providers: [AuthGuard] })
export class StockCountsModule {}
