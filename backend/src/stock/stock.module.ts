import {
  Module,
  Injectable,
  Controller,
  Get,
  Post,
  Body,
  Query,
  UseGuards,
  BadRequestException,
  UnprocessableEntityException,
  Headers,
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import { IsString, IsNumber, IsOptional, IsUUID, Min } from "class-validator";
import { PrismaService } from "../prisma.service";
import { Prisma } from "@prisma/client";
import { enqueuePushEvent } from "../notifications/push_outbox";
import { AuthGuard, Roles, Me } from "../common/auth";
class IntakeDto {
  @IsUUID() productId: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) quantity: number;
  @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) unitCost: number;
  @IsOptional() @IsString() supplier?: string;
  @IsOptional() @IsString() reference?: string;
  @IsOptional() @IsString() notes?: string;
}
class AdjustDto {
  @IsUUID() productId: string;
  @IsNumber({ maxDecimalPlaces: 3 }) quantityChange: number;
  @IsString() reason: string;
  @IsOptional() @IsString() notes?: string;
}
@Injectable()
export class StockService {
  constructor(private db: PrismaService) {}
  async run(u: any, key: string | undefined, work: (tx: any) => Promise<any>, expected?: any) {
    if (!key) return this.db.$transaction(work);
    if (key.length > 128) throw new BadRequestException("Idempotency-Key must be 128 characters or fewer");
    const find = () => this.db.stockMovement.findFirst({ where: { businessId: u.businessId, idempotencyKey: key } });
    const sameRequest = (movement: any) => !expected || (
      movement.productId === expected.productId && movement.type === expected.type &&
      Number(movement.quantityChange) === expected.quantity &&
      (movement.reason ?? "") === (expected.reason ?? "") &&
      (movement.supplier ?? "") === (expected.supplier ?? "") &&
      (movement.unitCost == null ? null : Number(movement.unitCost)) === (expected.unitCost ?? null) &&
      (movement.reference ?? "") === (expected.reference ?? "") && (movement.notes ?? "") === (expected.notes ?? "")
    );
    const replay = (movement: any) => {
      if (!sameRequest(movement)) throw new ConflictException("Idempotency-Key was already used for a different request");
      return { replayed: true, movement };
    };
    const previous = await find();
    if (previous) return replay(previous);
    try { return await this.db.$transaction(work); }
    catch (e: any) { if (e.code === "P2002") { const movement = await find(); if (movement) return replay(movement); } throw e; }
  }
  /** The ONLY place stock changes: level update + movement + alert, in one transaction. */
  async move(
    tx: any,
    o: {
      businessId: string;
      userId: string;
      productId: string;
      type: any;
      change: number;
      unitCost?: number;
      reason?: string;
      reference?: string;
      supplier?: string;
      notes?: string;
      allowNegative?: boolean;
      overrideReason?: string;
      idempotencyKey?: string;
    },
  ) {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${o.productId + ":stock"}))`;
    const product = await tx.product.findFirst({
      where: { id: o.productId, businessId: o.businessId, deletedAt: null },
      select: { id: true, name: true, minStock: true },
    });
    if (!product) throw new NotFoundException("Product not found");
    const current = await tx.stockLevel.findUnique({ where: { productId: o.productId } });
    const next = Number(current?.quantity ?? 0) + o.change;
    if (next < 0 && !o.allowNegative)
      throw new UnprocessableEntityException("Insufficient stock available");
    if (next < 0 && o.allowNegative)
      await tx.auditLog.create({ data: {
        businessId: o.businessId, userId: o.userId,
        action: "sale.negative_stock_override", entity: "product", entityId: product.id,
        meta: { reason: o.overrideReason, quantityBefore: Number(current?.quantity ?? 0), quantityChange: o.change, quantityAfter: next },
      } });
    const lvl = await tx.stockLevel.upsert({
      where: { productId: o.productId },
      update: { quantity: next },
      create: {
        productId: o.productId,
        businessId: o.businessId,
        quantity: next,
      },
    });
    await tx.stockMovement.create({
      data: {
        businessId: o.businessId,
        productId: o.productId,
        userId: o.userId,
        type: o.type,
        quantityChange: o.change,
        unitCost: o.unitCost,
        reason: o.reason,
        reference: o.reference,
        supplier: o.supplier,
        notes: o.notes,
        idempotencyKey: o.idempotencyKey,
      },
    });
    const q = Number(lvl.quantity);
    const previousQuantity = Number(current?.quantity ?? 0);
    let pushKind: string | null = null;
    if (q <= 0 && previousQuantity > 0) pushKind = "out_of_stock";
    else if (q > 0 && q <= Number(product.minStock) && (
      previousQuantity > Number(product.minStock) || previousQuantity <= 0
    )) pushKind = "low_stock";
    if (q > Number(product.minStock)) {
      await tx.alert.updateMany({ where: { businessId: o.businessId, productId: product.id, read: false }, data: { read: true } });
    } else {
      const kind = q <= 0 ? "out_of_stock" : "low_stock";
      await tx.alert.updateMany({ where: { businessId: o.businessId, productId: product.id, read: false, kind: { not: kind } }, data: { read: true } });
      if (!(await tx.alert.findFirst({ where: { businessId: o.businessId, productId: product.id, read: false, kind } }))) {
        const alert = await tx.alert.create({ data: { businessId: o.businessId, productId: product.id, kind } });
        if (pushKind === kind) {
          const title = kind === "out_of_stock" ? "Out of stock" : "Low stock";
          const body = kind === "out_of_stock"
            ? `${product.name} is out of stock (0 remaining).`
            : `${product.name}: ${q} remaining, minimum ${Number(product.minStock)}.`;
          await enqueuePushEvent(tx, {
            businessId: o.businessId,
            eventKey: `stock:${alert.id}`,
            kind,
            title,
            body,
            data: { productId: product.id, path: `/products/${product.id}`, quantity: q, minStock: Number(product.minStock) },
            inApp: false,
          });
          await tx.$executeRaw(Prisma.sql`
            UPDATE "Alert" SET "title" = ${title}, "body" = ${body},
              "data" = ${JSON.stringify({ productId: product.id, path: `/products/${product.id}`, quantity: q, minStock: Number(product.minStock) })}::jsonb,
              "critical" = ${kind === "out_of_stock"}, "dedupeKey" = ${`stock:${alert.id}`}
            WHERE "id" = ${alert.id}::uuid
          `);
        }
      }
    }
    return lvl;
  }
}
@Controller("stock")
@UseGuards(AuthGuard)
class StockController {
  constructor(
    private s: StockService,
    private db: PrismaService,
  ) {}
  @Get() list(@Me() u, @Query("status") status?: string) {
    return this.db.product
      .findMany({
        where: { businessId: u.businessId, deletedAt: null, active: true },
        include: { stock: true, category: true },
        orderBy: { name: "asc" },
      })
      .then((ps) =>
        ps
          .map((p) => {
            const q = Number(p.stock?.quantity ?? 0);
            return {
              ...p,
              quantity: q,
              stockValue: q * Number(p.buyingPrice),
              retailValue: q * Number(p.sellingPrice),
              status: q <= 0 ? "out" : q <= Number(p.minStock) ? "low" : "ok",
            };
          })
          .filter((p) => !status || status === "all" || p.status === status),
      );
  }
  @Post("intake")
  @Roles("OWNER", "MANAGER", "STOREKEEPER")
  intake(@Me() u, @Body() d: IntakeDto, @Headers("idempotency-key") key?: string) {
    if (d.quantity <= 0)
      throw new BadRequestException("Quantity must be more than 0");
    if (!Number.isFinite(d.unitCost) || d.unitCost < 0)
      throw new BadRequestException("Unit cost must be zero or more");
    return this.s.run(u, key, async (tx) => {
      const result = await this.s.move(tx, {
        businessId: u.businessId,
        userId: u.sub,
        productId: d.productId,
        type: "purchase_in",
        change: d.quantity,
        unitCost: d.unitCost,
        supplier: d.supplier,
        reference: d.reference,
        notes: d.notes,
        idempotencyKey: key,
      });
      await tx.product.update({ where: { id: d.productId }, data: { buyingPrice: d.unitCost } });
      await tx.auditLog.create({ data: {
        businessId: u.businessId,
        userId: u.sub,
        action: "stock.intake",
        entity: "product",
        entityId: d.productId,
        meta: {
          quantity: d.quantity,
          unitCost: d.unitCost,
          supplier: d.supplier ?? null,
          reference: d.reference ?? null,
          notes: d.notes ?? null,
        },
      } });
      return result;
    }, { productId: d.productId, type: "purchase_in", quantity: d.quantity, unitCost: d.unitCost, supplier: d.supplier, reference: d.reference, notes: d.notes, reason: undefined });
  }
  @Post("adjustments")
  @Roles("OWNER", "MANAGER", "STOREKEEPER")
  adjust(@Me() u, @Body() d: AdjustDto, @Headers("idempotency-key") key?: string) {
    if (!d.quantityChange)
      throw new BadRequestException("Quantity change cannot be zero");
    if (!d.reason.trim()) throw new BadRequestException("A stock adjustment reason is required");
    const limit = Number(process.env.ADJUSTMENT_NOTE_THRESHOLD ?? 10);
    if (d.quantityChange < -limit && !d.notes?.trim())
      throw new BadRequestException(
        `Notes required when reducing more than ${limit}`,
      );
    return this.s.run(u, key, async (tx) => {
      await tx.auditLog.create({
        data: {
          businessId: u.businessId,
          userId: u.sub,
          action: "stock.adjust",
          entity: "product",
          entityId: d.productId,
          meta: d as any,
        },
      });
      return this.s.move(tx, {
        businessId: u.businessId,
        userId: u.sub,
        productId: d.productId,
        type: "adjustment",
        change: d.quantityChange,
        reason: d.reason,
        notes: d.notes,
        idempotencyKey: key,
      });
    }, { productId: d.productId, type: "adjustment", quantity: d.quantityChange, reason: d.reason, notes: d.notes });
  }
  @Get("movements") movements(@Me() u) {
    return this.db.stockMovement.findMany({
      where: { businessId: u.businessId },
      include: { product: true },
      orderBy: { createdAt: "desc" },
      take: 100,
    });
  }
}
@Module({
  controllers: [StockController],
  providers: [StockService, AuthGuard],
  exports: [StockService],
})
export class StockModule {}
