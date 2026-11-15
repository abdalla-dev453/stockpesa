import { BadRequestException, ConflictException, Controller, Get, Post, Patch, Delete, Param, ParseUUIDPipe, Query, Body, Headers, UseGuards, Module, NotFoundException } from "@nestjs/common";
import { createHash } from "node:crypto";
import { Type } from "class-transformer";
import { IsIn, IsNumber, IsOptional, IsString, IsUUID, Min, MinLength, MaxLength, Matches } from "class-validator";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me, Roles } from "../common/auth";
import { cents, money } from "../common/money";
import { KENYAN_MOBILE_PATTERN, normalizeKenyanPhone } from "../common/phone";

class CustomerDto {
  @IsString() @MinLength(2) @MaxLength(100) name: string;
  @IsOptional() @IsString() @Matches(KENYAN_MOBILE_PATTERN, { message: "Enter a valid Kenyan mobile number" }) phone?: string;
  @IsOptional() @IsString() @MaxLength(1000) notes?: string;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) creditLimit?: number;
}
class PaymentDto {
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0.01) amount: number;
  @IsIn(["CASH", "MPESA", "BANK", "CARD"]) method: string;
  @IsOptional() @IsString() @MaxLength(100) reference?: string;
  @IsUUID() saleId: string;
}

@Controller("customers") @UseGuards(AuthGuard)
class CustomersController {
  constructor(private db: PrismaService) {}
  @Get() @Roles("OWNER", "MANAGER", "CASHIER") async list(@Me() u, @Query("search") search?: string) {
    return this.db.customer.findMany({
      where: { businessId: u.businessId, deletedAt: null, ...(search ? { OR: [{ name: { contains: search, mode: "insensitive" } }, { phone: { contains: search } }] } : {}) },
      orderBy: { name: "asc" }, take: 200,
    });
  }
  @Get(":id") @Roles("OWNER", "MANAGER", "CASHIER") async get(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const c = await this.db.customer.findFirst({ where: { id, businessId: u.businessId, deletedAt: null }, include: { sales: { where: { balanceDue: { gt: 0 } }, orderBy: { saleDate: "asc" }, take: 100 }, payments: { orderBy: { createdAt: "desc" }, take: 50 } } });
    if (!c) throw new NotFoundException("Customer not found");
    return c;
  }
  @Post() @Roles("OWNER", "MANAGER", "CASHIER") async create(@Me() u, @Body() d: CustomerDto) {
    return this.db.customer.create({ data: { ...d, name: d.name.trim(), phone: d.phone ? normalizeKenyanPhone(d.phone) : undefined, businessId: u.businessId } });
  }
  @Patch(":id") @Roles("OWNER", "MANAGER", "CASHIER") async update(@Me() u, @Param("id", ParseUUIDPipe) id: string, @Body() d: CustomerDto) {
    const c = await this.db.customer.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!c) throw new NotFoundException("Customer not found");
    return this.db.customer.update({ where: { id }, data: { ...d, ...(d.name ? { name: d.name.trim() } : {}), ...(d.phone ? { phone: normalizeKenyanPhone(d.phone) } : {}) } });
  }
  @Delete(":id") @Roles("OWNER", "MANAGER") async remove(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const c = await this.db.customer.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!c) throw new NotFoundException("Customer not found");
    if (Number(c.balance) > 0) throw new BadRequestException("Settle the customer's outstanding balance before archiving them");
    await this.db.$transaction(async (tx) => {
      await tx.customer.update({ where: { id }, data: { deletedAt: new Date() } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "customer.archived", entity: "customer", entityId: id, meta: { name: c.name } } });
    });
    return { id, deleted: true };
  }
  @Post(":id/payments") @Roles("OWNER", "MANAGER", "CASHIER") async payment(@Me() u, @Param("id", ParseUUIDPipe) id: string, @Body() d: PaymentDto, @Headers("idempotency-key") key?: string) {
    if (key && (key.length > 128 || !/^[\w.-]+$/.test(key))) throw new BadRequestException("Invalid Idempotency-Key");
    const payload = createHash("sha256").update(JSON.stringify({ customerId: id, ...d })).digest("hex");
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${d.saleId + ":return"}))`;
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${id + ":customer"}))`;
      if (key) {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":payment-idempotency:" + key}))`;
        const prior = await tx.payment.findFirst({ where: { businessId: u.businessId, idempotencyKey: key } });
        if (prior) {
          if (prior.idempotencyPayload !== payload) throw new ConflictException("Idempotency-Key was already used for a different payment");
          return prior;
        }
      }
      const c = await tx.customer.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
      if (!c) throw new NotFoundException("Customer not found");
      const sale = await tx.sale.findFirst({ where: { id: d.saleId, businessId: u.businessId, customerId: id } });
      if (!sale) throw new NotFoundException("Customer sale not found");
      const amountCents = cents(d.amount);
      if (amountCents > cents(sale.balanceDue)) throw new BadRequestException("Payment exceeds the sale balance");
      if (amountCents > cents(c.balance)) throw new BadRequestException("Payment exceeds the customer's outstanding balance");
      const hasReturns = (await tx.returnRecord.count({ where: { saleId: sale.id } })) > 0;
      const amount = money(amountCents);
      await tx.sale.update({ where: { id: sale.id }, data: { amountPaid: { increment: amount }, balanceDue: { decrement: amount }, status: hasReturns ? "partially_returned" : amountCents === cents(sale.balanceDue) ? "completed" : "partially_paid" } });
      const payment = await tx.payment.create({ data: { businessId: u.businessId, customerId: id, saleId: d.saleId, method: d.method as any, amount, settledAt: new Date(), reference: d.reference, idempotencyKey: key, idempotencyPayload: key ? payload : undefined } });
      await tx.customer.update({ where: { id }, data: { balance: { decrement: amount } } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "customer.payment.recorded", entity: "payment", entityId: payment.id, meta: { saleId: sale.id, customerId: id, amount, method: d.method, reference: d.reference ?? null } } });
      return payment;
    });
  }
}
@Module({ controllers: [CustomersController], providers: [AuthGuard] })
export class CustomersModule {}
