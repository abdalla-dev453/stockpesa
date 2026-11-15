import { BadRequestException, Body, Controller, ForbiddenException, Get, Headers, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Post, UseGuards } from "@nestjs/common";
import { IsInt, IsOptional, IsString } from "class-validator";
import { createHmac, timingSafeEqual } from "node:crypto";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me, Roles } from "../common/auth";
import { cents, money } from "../common/money";

class MpesaCallbackDto {
  @IsString() checkoutRequestId: string;
  @IsInt() resultCode: number;
  @IsOptional() @IsString() receiptNumber?: string;
}

@Injectable()
class MpesaService {
  constructor(private db: PrismaService) {}
  private signature(payload: MpesaCallbackDto) {
    const secret = process.env.MPESA_CALLBACK_SECRET;
    if (!secret) throw new ForbiddenException("M-Pesa callback is not configured");
    return createHmac("sha256", secret).update(`${payload.checkoutRequestId}.${payload.resultCode}.${payload.receiptNumber ?? ""}`).digest("hex");
  }
  async callback(payload: MpesaCallbackDto, signature?: string) {
    if (process.env.MPESA_MODE === "disabled") throw new ForbiddenException("M-Pesa callback is disabled");
    if (!signature || !/^[a-f0-9]{64}$/i.test(signature)) throw new ForbiddenException("Invalid M-Pesa callback signature");
    const expected = Buffer.from(this.signature(payload), "hex"), actual = Buffer.from(signature, "hex");
    if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) throw new ForbiddenException("Invalid M-Pesa callback signature");
    return this.db.$transaction(async (tx) => {
      let payment = await tx.payment.findUnique({ where: { checkoutRequestId: payload.checkoutRequestId } });
      if (!payment || payment.method !== "MPESA" || !payment.saleId) throw new NotFoundException("Pending M-Pesa payment not found");
      const nextStatus = payload.resultCode === 0 ? "PAID" : "FAILED";
      if (payment.status !== "PENDING") {
        if (payment.status === nextStatus) return { accepted: true, replayed: true, status: payment.status };
        throw new BadRequestException("Payment has already been finalized");
      }
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${payment.saleId + ":return"}))`;
      payment = await tx.payment.findUnique({ where: { checkoutRequestId: payload.checkoutRequestId } });
      if (!payment) throw new NotFoundException("Pending M-Pesa payment not found");
      if (payment.status !== "PENDING") {
        if (payment.status === nextStatus) return { accepted: true, replayed: true, status: payment.status };
        throw new BadRequestException("Payment has already been finalized");
      }
      const sale = await tx.sale.findFirst({ where: { id: payment.saleId, businessId: payment.businessId } });
      if (!sale) throw new NotFoundException("Sale not found");
      if (sale.customerId) await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${sale.customerId + ":customer"}))`;
      const paid = nextStatus === "PAID";
      await tx.payment.update({ where: { id: payment.id }, data: { status: nextStatus, settledAt: paid ? new Date() : null, reference: payload.receiptNumber ?? payment.reference } });
      if (paid) {
        const paymentCents = cents(payment.amount);
        const saleDueCents = cents(sale.balanceDue);
        if (paymentCents > saleDueCents) throw new BadRequestException("M-Pesa amount exceeds the current sale balance");
        const due = money(Math.max(0, saleDueCents - paymentCents));
        const status = sale.status === "partially_returned" ? "partially_returned" : due === 0 ? "completed" : "partially_paid";
        await tx.sale.update({ where: { id: sale.id }, data: { amountPaid: { increment: payment.amount }, balanceDue: due, status } });
        if (sale.customerId) {
          const customer = await tx.customer.findFirst({ where: { id: sale.customerId, businessId: sale.businessId } });
          if (!customer || cents(customer.balance) < paymentCents) throw new BadRequestException("Customer balance is inconsistent with the pending payment");
          await tx.customer.update({ where: { id: sale.customerId }, data: { balance: { decrement: payment.amount } } });
        }
        const receipt = await tx.receipt.findUnique({ where: { saleId: sale.id } });
        if (receipt) {
          const old = receipt.snapshot as Record<string, unknown>;
          await tx.receipt.update({ where: { id: receipt.id }, data: { snapshot: { ...old, paymentStatus: "PAID", amountPaid: money(cents(sale.amountPaid) + paymentCents), balanceDue: due, paymentReference: payload.receiptNumber ?? null } } });
        }
      } else if (sale.status === "payment_pending") {
        await tx.sale.update({ where: { id: sale.id }, data: { status: Number(sale.amountPaid) > 0 ? "partially_paid" : "unpaid" } });
      }
      if (!paid) {
        const receipt = await tx.receipt.findUnique({ where: { saleId: sale.id } });
        if (receipt) {
          const old = receipt.snapshot as Record<string, unknown>;
          await tx.receipt.update({ where: { id: receipt.id }, data: { snapshot: { ...old, paymentStatus: "FAILED" } } });
        }
      }
      await tx.auditLog.create({ data: { businessId: payment.businessId, userId: sale.userId, action: paid ? "payment.mpesa.confirmed" : "payment.mpesa.failed", entity: "payment", entityId: payment.id, meta: { checkoutRequestId: payment.checkoutRequestId, receiptNumber: payload.receiptNumber ?? null, resultCode: payload.resultCode } } });
      if (paid) await tx.auditLog.create({ data: { businessId: payment.businessId, userId: sale.userId, action: "sale.completed", entity: "sale", entityId: sale.id, meta: { saleNumber: sale.saleNumber, total: Number(sale.total), amountPaid: money(cents(sale.amountPaid) + cents(payment.amount)), balanceDue: money(Math.max(0, cents(sale.balanceDue) - cents(payment.amount))), paymentId: payment.id, mpesaReceipt: payload.receiptNumber ?? null } } });
      return { accepted: true, status: nextStatus };
    });
  }
  async mockConfirm(u: any, id: string) {
    if (process.env.MPESA_MODE !== "mock") throw new ForbiddenException("M-Pesa mock mode is disabled");
    const payment = await this.db.payment.findFirst({ where: { id, businessId: u.businessId, method: "MPESA", status: "PENDING" } });
    if (!payment?.checkoutRequestId) throw new NotFoundException("Pending M-Pesa payment not found");
    const payload: MpesaCallbackDto = { checkoutRequestId: payment.checkoutRequestId, resultCode: 0, receiptNumber: `MOCK-${payment.id.slice(0, 8).toUpperCase()}` };
    return this.callback(payload, this.signature(payload));
  }
}

@Controller("payments/mpesa")
class MpesaController {
  constructor(private mpesa: MpesaService) {}
  @Get("config") config() { return { mockEnabled: process.env.MPESA_MODE === "mock" }; }
  @Post("callback") callback(@Body() body: MpesaCallbackDto, @Headers("x-mpesa-signature") signature?: string) { return this.mpesa.callback(body, signature); }
  @UseGuards(AuthGuard) @Roles("OWNER", "MANAGER", "CASHIER") @Post("mock/:id/confirm") mock(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) { return this.mpesa.mockConfirm(u, id); }
}

@Module({ controllers: [MpesaController], providers: [MpesaService, AuthGuard] })
export class PaymentsModule {}
