import {
  Module,
  Controller,
  Post,
  Get,
  Param,
  ParseUUIDPipe,
  NotFoundException,
  Body,
  UseGuards,
  BadRequestException,
  ForbiddenException,
  Headers,
  ConflictException,
  ServiceUnavailableException,
} from "@nestjs/common";
import {
  IsArray,
  IsOptional,
  IsString,
  IsNumber,
  IsUUID,
  IsIn,
  Min,
  ValidateNested,
  ArrayMinSize,
  IsNotEmpty,
  IsBoolean,
  Matches,
  MaxLength,
} from "class-validator";
import { Type } from "class-transformer";
import { createHash } from "node:crypto";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me, Roles } from "../common/auth";
import { enqueuePushEvent } from "../notifications/push_outbox";
import { StockModule, StockService } from "../stock/stock.module";
import { cents, money, multiplyUnitCents, quantityMilli } from "../common/money";
import { planMpesaCheckout } from "../common/mpesa-checkout";
class ItemDto {
  @IsOptional() @IsUUID() productId?: string;
  @IsOptional() @IsUUID() variantId?: string;
  @IsOptional() @IsString() unit?: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) quantity: number;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) discount?: number;
}
class SaleDto {
  @IsArray() @ArrayMinSize(1) @ValidateNested({ each: true }) @Type(() => ItemDto) items: ItemDto[];
  @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) discount?: number;
  @IsIn(["CASH", "MPESA", "BANK", "CARD", "CREDIT"]) method: string;
  @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) amountPaid: number;
  @IsOptional() @IsUUID() customerId?: string;
  @IsOptional() @IsString() overrideReason?: string;
  @IsOptional() @IsString() @MaxLength(32) @Matches(/^[A-Za-z0-9]{6,32}$/) mpesaReceiptNumber?: string;
}
class ReturnItemDto {
  @IsUUID() saleItemId: string;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) quantity: number;
}
class ReturnDto {
  @IsArray() @ArrayMinSize(1) @ValidateNested({ each: true }) @Type(() => ReturnItemDto) items: ReturnItemDto[];
  @IsString() @IsNotEmpty() reason: string;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) refundAmount: number;
  @IsBoolean() restock: boolean;
}
@Controller("sales")
@UseGuards(AuthGuard)
class SalesController {
  constructor(
    private db: PrismaService,
    private stock: StockService,
  ) {}
  @Post() @Roles("OWNER", "MANAGER", "CASHIER") create(@Me() u, @Body() d: SaleDto, @Headers("idempotency-key") key?: string) {
    if (!d.items?.length) throw new BadRequestException("Cart is empty");
    if (d.items.some((item) => (!!item.productId === !!item.variantId)))
      throw new BadRequestException("Choose exactly one product or product variant for each sale item");
    if (key && (key.length > 128 || !/^[\w.-]+$/.test(key))) throw new BadRequestException("Invalid Idempotency-Key");
    const payload = createHash("sha256").update(JSON.stringify(d)).digest("hex");
    return this.db.$transaction(async (tx) => {
      if (key) {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":sale-idempotency:" + key}))`;
        const prior = await tx.sale.findFirst({ where: { businessId: u.businessId, idempotencyKey: key }, include: { items: true, payments: true } });
        if (prior) {
          if (prior.idempotencyPayload !== payload) throw new ConflictException("Idempotency-Key was already used for a different sale");
          return prior;
        }
      }
      let subtotalCents = 0;
      const lines = [];
      for (const it of d.items) {
        const variant = it.variantId ? await tx.productVariant.findFirst({
          where: { id: it.variantId, businessId: u.businessId, deletedAt: null, active: true, product: { deletedAt: null, active: true, status: "ACTIVE" } },
          include: { product: true },
        }) : null;
        const product: any = it.productId ? await tx.product.findFirst({
          where: { id: it.productId, businessId: u.businessId, deletedAt: null, active: true, status: "ACTIVE" },
          include: { stock: true, variants: { where: { deletedAt: null } } },
        }) : variant?.product ?? null;
        if (!product || (it.variantId && !variant)) throw new BadRequestException("Product not found");
        if (!it.variantId && product.variants.length > 0) throw new BadRequestException(`Choose a variant for ${product.name}`);
        const bundleComponents: any[] = it.productId ? await tx.bundleItem.findMany({
          where: { businessId: u.businessId, bundleProductId: product.id },
          include: { component: { include: { stock: true } } },
        }) : [];
        if (bundleComponents.length) {
          for (const item of bundleComponents) {
            const available = Number(item.component.stock?.quantity ?? 0);
            const required = Number(item.quantity) * it.quantity;
            if (required > available && (!["OWNER", "MANAGER"].includes(u.role) || !d.overrideReason))
              throw new BadRequestException(`Only ${available} of ${item.component.name} in stock for this bundle`);
          }
        }
        const saleProduct: any = variant ?? product;
        const enteredUnit = it.unit?.trim().toLowerCase() || saleProduct.unit;
        let factor = 1;
        if (enteredUnit !== saleProduct.unit) {
          if (variant || bundleComponents.length) throw new BadRequestException("Unit conversion is unavailable for variants and bundles");
          factor = await this.stock.conversionFactor(tx, u.businessId, product.id, enteredUnit, product.unit);
        }
        const rawStockQuantity = it.quantity * factor;
        const stockQuantity = Math.round(rawStockQuantity * 1000) / 1000;
        if (!Number.isFinite(stockQuantity) || Math.abs(rawStockQuantity - stockQuantity) > 1e-8)
          throw new BadRequestException("Converted quantity must be precise to at most 3 decimal places");
        const avail = bundleComponents.length ? Infinity : Number(variant?.quantity ?? product.stock?.quantity ?? 0);
        const now = new Date();
        const promoPrice = saleProduct.promotionalPrice != null &&
          (!saleProduct.promotionStartsAt || saleProduct.promotionStartsAt <= now) &&
          (!saleProduct.promotionEndsAt || saleProduct.promotionEndsAt >= now)
          ? saleProduct.promotionalPrice : null;
        const bundleCost = bundleComponents.reduce((sum, row) => sum + Number(row.component.buyingPrice) * Number(row.quantity), 0);
        const priced = { ...product, ...saleProduct, id: product.id, variantId: variant?.id, name: variant ? `${product.name} · ${variant.name}` : product.name,
          sku: variant?.sku ?? product.sku, sellingPrice: Math.round(Number(promoPrice ?? saleProduct.sellingPrice) * factor * 100) / 100, buyingPrice: bundleComponents.length ? bundleCost : Math.round(Number(saleProduct.buyingPrice) * factor * 100) / 100 };
        if (stockQuantity > avail) {
          if (!["OWNER", "MANAGER"].includes(u.role))
            throw new ForbiddenException(`Only ${avail} of ${priced.name} in stock`);
          if (!d.overrideReason)
            throw new BadRequestException(
              `Only ${avail} of ${priced.name} in stock. Provide overrideReason to oversell`,
            );
        }
        const lineCents = multiplyUnitCents(priced.sellingPrice, it.quantity) - cents(it.discount);
        if (lineCents < 0) throw new BadRequestException(`Discount exceeds the line total for ${priced.name}`);
        subtotalCents += lineCents;
        lines.push({ p: priced, it, variant, bundleComponents, enteredUnit, stockQuantity, line: money(lineCents) });
      }
      const subtotal = money(subtotalCents);
      const totalCents = subtotalCents - cents(d.discount);
      if (totalCents < 0)
        throw new BadRequestException("Discounts cannot exceed the sale subtotal");
      const total = money(totalCents);
      if (d.mpesaReceiptNumber && d.method !== "MPESA")
        throw new BadRequestException("An M-Pesa receipt number can only be used with M-Pesa");
      const mpesaPlan = d.method === "MPESA" ? planMpesaCheckout({
        receiptNumber: d.mpesaReceiptNumber,
        requestedPaidCents: cents(d.amountPaid),
        totalCents,
        mode: process.env.MPESA_MODE,
      }) : null;
      if (mpesaPlan?.error === "receipt_amount_required")
        throw new BadRequestException("Enter the amount received through M-Pesa");
      if (mpesaPlan?.error === "amount_exceeds_total")
        throw new BadRequestException("M-Pesa amount cannot exceed the sale total");
      if (mpesaPlan?.error === "mock_disabled")
        throw new ServiceUnavailableException("M-Pesa mock checkout is not configured; use a recorded M-Pesa receipt or another payment method.");
      if (mpesaPlan?.error === "mock_requires_full_amount")
        throw new BadRequestException("Mock M-Pesa checkout must request the full sale total");
      const manualMpesa = mpesaPlan?.manual ?? false;
      const mpesaPending = mpesaPlan?.pending ?? false;
      if (d.method === "CREDIT" && !d.customerId)
        throw new BadRequestException("Select a customer for credit sales");
      if (d.method === "CREDIT" && d.amountPaid > 0)
        throw new BadRequestException("Choose the actual payment method when collecting money at checkout");
      const requestedPaidCents = cents(d.amountPaid);
      if (requestedPaidCents > totalCents)
        throw new BadRequestException("Amount paid cannot exceed the sale total");
      const confirmedPaidCents = mpesaPlan ? mpesaPlan.salePaidCents : requestedPaidCents;
      const confirmedPaid = money(confirmedPaidCents);
      const dueAmount = money(totalCents - confirmedPaidCents);
      if (dueAmount > 0 && d.method !== "MPESA" && !d.customerId) throw new BadRequestException("Select a customer for the unpaid balance");
      if (d.customerId)
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${d.customerId + ":customer"}))`;
      const customer = d.customerId ? await tx.customer.findFirst({
        where: { id: d.customerId, businessId: u.businessId, deletedAt: null },
        select: { id: true, name: true, balance: true, creditLimit: true },
      }) : null;
      if (d.customerId && !customer) throw new BadRequestException("Customer not found");
      const amountDue = Math.max(dueAmount, 0);
      if (customer?.creditLimit != null && cents(customer.balance) + cents(amountDue) > cents(customer.creditLimit))
        throw new BadRequestException("This sale would exceed the customer's credit limit");
      if (manualMpesa) {
        const receiptNumber = d.mpesaReceiptNumber!.toUpperCase();
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":mpesa-receipt:" + receiptNumber}))`;
        const duplicateReceipt = await tx.payment.findFirst({ where: {
          businessId: u.businessId,
          method: "MPESA",
          reference: { equals: receiptNumber, mode: "insensitive" },
        }, select: { id: true } });
        if (duplicateReceipt) throw new ConflictException("This M-Pesa receipt number has already been recorded");
      }
      // Keep count-based sale numbers unique when two sales arrive together.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":sale-number"}))`;
      const count = await tx.sale.count({
        where: { businessId: u.businessId },
      });
      const sale = await tx.sale.create({
        data: {
          businessId: u.businessId,
          userId: u.sub,
          customerId: d.customerId,
          saleNumber: "S-" + (1000 + count),
          idempotencyKey: key,
          idempotencyPayload: key ? payload : undefined,
          subtotal,
          discount: d.discount ?? 0,
          total,
          amountPaid: confirmedPaid,
          balanceDue: dueAmount,
          status: mpesaPending ? "payment_pending" : dueAmount === 0 ? "completed" : confirmedPaid === 0 ? "unpaid" : "partially_paid",
          items: {
            create: lines.map((l) => ({
              businessId: u.businessId,
              productId: l.p.id,
              ...(l.variant ? { variantId: l.variant.id } : {}),
              quantity: l.it.quantity,
              unit: l.enteredUnit,
              stockQuantity: l.stockQuantity,
              unitPrice: l.p.sellingPrice,
              unitCost: l.p.buyingPrice,
              discount: l.it.discount ?? 0,
              lineTotal: l.line,
            })),
          },
        },
        include: { items: true },
      });
      for (const l of lines) {
        if (l.bundleComponents.length) {
          for (const component of l.bundleComponents) await this.stock.move(tx, {
            businessId: u.businessId, userId: u.sub, productId: component.componentId,
            type: "sale_out", change: -Number(component.quantity) * l.it.quantity,
            reference: sale.saleNumber,
            allowNegative: ["OWNER", "MANAGER"].includes(u.role) && !!d.overrideReason,
            overrideReason: d.overrideReason,
          });
        } else if (l.variant) {
          await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":variant:" + l.variant.id}))`;
          const updated = await tx.productVariant.updateMany({ where: { id: l.variant.id, businessId: u.businessId, ...( !( ["OWNER", "MANAGER"].includes(u.role) && !!d.overrideReason) ? { quantity: { gte: l.stockQuantity } } : {}) }, data: { quantity: { decrement: l.stockQuantity } } });
          if (updated.count !== 1) throw new ForbiddenException(`Not enough ${l.p.name} in stock`);
          await tx.variantStockMovement.create({ data: { businessId: u.businessId, variantId: l.variant.id, userId: u.sub, quantityChange: -l.stockQuantity, reason: "sale", reference: sale.saleNumber } });
        } else await this.stock.move(tx, {
          businessId: u.businessId,
          userId: u.sub,
          productId: l.p.id,
          type: "sale_out",
          change: -l.stockQuantity,
          reference: sale.saleNumber,
          allowNegative: ["OWNER", "MANAGER"].includes(u.role) && !!d.overrideReason,
          overrideReason: d.overrideReason,
        });
      }
      const payment = d.method === "CREDIT" ? null : await tx.payment.create({
          data: {
            businessId: u.businessId,
            saleId: sale.id,
            customerId: d.customerId,
            method: d.method as any,
            amount: mpesaPending ? total : confirmedPaid,
            status: mpesaPending ? "PENDING" : "PAID",
            settledAt: mpesaPending ? undefined : new Date(),
            ...(d.method === "MPESA" && manualMpesa ? { reference: d.mpesaReceiptNumber!.toUpperCase() } : {}),
            ...(mpesaPending ? { checkoutRequestId: `mock_${sale.id}` } : {}),
          },
        });
      if (sale.balanceDue.gt(0) && d.customerId)
        await tx.customer.update({
          where: { id: d.customerId },
          data: { balance: { increment: sale.balanceDue } },
        });
      if (sale.balanceDue.gt(0) && customer) {
        const oldBalance = Number(customer.balance);
        const newBalance = oldBalance + Number(sale.balanceDue);
        await enqueuePushEvent(tx, {
          businessId: u.businessId,
          eventKey: `credit-sale:${sale.id}`,
          kind: "credit_sale",
          title: "Customer credit sale",
          body: `${customer.name}: KES ${Number(sale.balanceDue).toFixed(2)} added to their balance.`,
          data: { customerId: customer.id, path: `/customers/${customer.id}`, saleId: sale.id },
        });
        await enqueuePushEvent(tx, {
          businessId: u.businessId,
          eventKey: `debt-threshold:${sale.id}`,
          kind: "debt_threshold",
          title: "Customer balance threshold",
          body: `${customer.name}'s balance is now KES ${newBalance.toFixed(2)}.`,
          data: { customerId: customer.id, path: `/customers/${customer.id}`, oldBalance, newBalance },
        });
      }
      await enqueuePushEvent(tx, {
        businessId: u.businessId,
        eventKey: `new-sale:${sale.id}`,
        kind: "new_sale",
        title: "Sale completed",
        body: `${sale.saleNumber}: KES ${total.toFixed(2)} recorded.`,
        data: { saleId: sale.id, path: "/reports" },
      });
      const businessSnapshot = await tx.business.findUnique({ where: { id: u.businessId }, select: { name: true, phone: true, receiptFooter: true, currency: true } });
      const receipt = await tx.receipt.create({ data: {
        businessId: u.businessId, saleId: sale.id, receiptNumber: sale.saleNumber,
        snapshot: { businessName: businessSnapshot?.name, businessPhone: businessSnapshot?.phone, receiptFooter: businessSnapshot?.receiptFooter, currency: businessSnapshot?.currency, saleNumber: sale.saleNumber, saleDate: sale.saleDate.toISOString(), subtotal, discount: d.discount ?? 0, tax: 0, total, amountPaid: confirmedPaid, balanceDue: Number(sale.balanceDue), method: d.method, paymentStatus: payment?.status ?? "CREDIT", items: lines.map((l, index) => ({ saleItemId: sale.items[index]?.id, name: l.p.name, sku: l.p.sku, quantity: l.it.quantity, unit: l.enteredUnit, unitPrice: Number(l.p.sellingPrice), lineDiscount: l.it.discount ?? 0, lineTotal: l.line })) },
      } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: sale.status === "completed" ? "sale.completed" : "sale.created", entity: "sale", entityId: sale.id, meta: { saleNumber: sale.saleNumber, total, amountPaid: confirmedPaid, balanceDue: Number(sale.balanceDue), receiptId: receipt.id, paymentId: payment?.id ?? null, ...(manualMpesa ? { mpesaReceiptNumber: d.mpesaReceiptNumber!.toUpperCase() } : {}) } } });
      return { ...sale, payments: payment ? [payment] : [] };
    });
  }
  @Get() @Roles("OWNER", "MANAGER", "CASHIER") list(@Me() u) {
    return this.db.sale.findMany({
      where: { businessId: u.businessId },
      include: { items: { include: { product: true } }, customer: true },
      orderBy: { saleDate: "desc" },
      take: 50,
    });
  }
  @Get(":id") @Roles("OWNER", "MANAGER", "CASHIER") async one(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const sale = await this.db.sale.findFirst({
      where: { id, businessId: u.businessId },
      include: { items: { include: { product: true } }, customer: true, payments: true, receipts: true, returns: { include: { items: { include: { saleItem: { include: { product: true } } } } }, orderBy: { createdAt: "desc" } } },
    });
    if (!sale) throw new NotFoundException("Sale not found");
    const cashier = await this.db.user.findFirst({
      where: { id: sale.userId, businessId: u.businessId },
      select: { fullName: true },
    });
    return { ...sale, cashierName: cashier?.fullName ?? null };
  }
  @Post(":id/returns") @Roles("OWNER", "MANAGER") async returnSale(
    @Me() u, @Param("id", ParseUUIDPipe) id: string, @Body() d: ReturnDto, @Headers("idempotency-key") key?: string,
  ) {
    if (!d.items?.length) throw new BadRequestException("Select at least one item to return");
    if (key && (key.length > 128 || !/^[\w.-]+$/.test(key))) throw new BadRequestException("Invalid Idempotency-Key");
    const payload = createHash("sha256").update(JSON.stringify(d)).digest("hex");
    if (new Set(d.items.map((i) => i.saleItemId)).size !== d.items.length) throw new BadRequestException("Each sale item can only appear once");
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${id + ":return"}))`;
      if (key) {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":return-idempotency:" + key}))`;
        const prior = await tx.returnRecord.findFirst({ where: { businessId: u.businessId, idempotencyKey: key } });
        if (prior) {
          if (prior.idempotencyPayload !== payload) throw new ConflictException("Idempotency-Key was already used for a different return");
          const currentSale = await tx.sale.findUnique({ where: { id } });
          return { id: prior.id, saleId: id, returnedTotal: Number(prior.total), refunded: Number(prior.refundAmount), balanceDue: Number(currentSale?.balanceDue ?? 0), replayed: true };
        }
      }
      const sale = await tx.sale.findFirst({ where: { id, businessId: u.businessId }, include: { items: true } });
      if (!sale) throw new NotFoundException("Sale not found");
      if (sale.status === "payment_pending") throw new BadRequestException("Resolve the pending M-Pesa payment before recording a return");
      if (["void", "refunded"].includes(sale.status)) throw new BadRequestException("This sale can no longer be returned");
      if (sale.customerId)
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${sale.customerId + ":customer"}))`;
      const returned: any[] = []; let returnTotalCents = 0;
      for (const request of d.items) {
        const item = sale.items.find((i) => i.id === request.saleItemId);
        if (!item) throw new NotFoundException("Sale item not found");
        const remainingMilli = quantityMilli(item.quantity) - quantityMilli(item.returnedQty);
        const requestMilli = quantityMilli(request.quantity);
        if (requestMilli > remainingMilli) throw new BadRequestException(`Only ${remainingMilli / 1000} units remain eligible for return`);
        const grossLineCents = Math.round((cents(item.lineTotal) * requestMilli) / quantityMilli(item.quantity));
        const allocatedDiscountCents = cents(sale.subtotal) > 0
          ? Math.round((cents(sale.discount) * grossLineCents) / cents(sale.subtotal))
          : 0;
        const lineCents = Math.max(0, grossLineCents - allocatedDiscountCents);
        returnTotalCents += lineCents;
        returned.push({ item, quantity: request.quantity, lineCents });
      }
      const allReturned = sale.items.every((i) => quantityMilli(i.returnedQty) + quantityMilli(returned.find((r) => r.item.id === i.id)?.quantity) >= quantityMilli(i.quantity));
      if (allReturned && returned.length) {
        returned[returned.length - 1].lineCents += cents(sale.total) - returnTotalCents;
        returnTotalCents = cents(sale.total);
      }
      const returnTotal = money(returnTotalCents);
      const newTotalCents = allReturned ? 0 : Math.max(0, cents(sale.total) - returnTotalCents);
      const minimumRefundCents = Math.max(0, cents(sale.amountPaid) - newTotalCents);
      const refundCents = cents(d.refundAmount);
      const maximumRefundCents = Math.min(returnTotalCents, cents(sale.amountPaid));
      if (refundCents < minimumRefundCents || refundCents > maximumRefundCents)
        throw new BadRequestException(`Refund must be between ${money(minimumRefundCents)} and ${money(maximumRefundCents)}`);
      const newPaid = money(cents(sale.amountPaid) - refundCents);
      const newTotal = money(newTotalCents);
      const newBalance = money(Math.max(newTotalCents - cents(newPaid), 0));
      const refundAmount = money(refundCents);
      const record = await tx.returnRecord.create({ data: {
        businessId: u.businessId, saleId: sale.id, userId: u.sub, reason: d.reason.trim(), total: returnTotal, refundAmount, restock: d.restock, idempotencyKey: key, idempotencyPayload: key ? payload : undefined,
        items: { create: returned.map(({ item, quantity, lineCents }) => ({ saleItemId: item.id, quantity, unitPrice: money(Math.round(lineCents * 1000 / quantityMilli(quantity))), lineTotal: money(lineCents) })) },
      } });
      if (refundCents > 0) {
        const refundMethod = await tx.payment.findFirst({ where: { saleId: sale.id, status: "PAID", amount: { gt: 0 } }, orderBy: { createdAt: "desc" } });
        await tx.payment.create({ data: { businessId: u.businessId, saleId: sale.id, customerId: sale.customerId, method: refundMethod?.method ?? "CASH", amount: -refundAmount, status: "PAID", settledAt: new Date(), reference: `RETURN-${record.id}` } });
      }
      for (const row of returned) {
        await tx.saleItem.update({ where: { id: row.item.id }, data: { returnedQty: { increment: row.quantity } } });
        if (d.restock && row.item.variantId) {
          await tx.productVariant.update({ where: { id: row.item.variantId }, data: { quantity: { increment: row.quantity } } });
          await tx.variantStockMovement.create({ data: { businessId: u.businessId, variantId: row.item.variantId, userId: u.sub, quantityChange: row.quantity, reason: `return: ${d.reason}`, reference: sale.saleNumber } });
        } else if (d.restock) {
          const components = await tx.bundleItem.findMany({ where: { businessId: u.businessId, bundleProductId: row.item.productId } });
          if (components.length) {
            for (const component of components) await this.stock.move(tx, { businessId: u.businessId, userId: u.sub, productId: component.componentId, type: "return_in", change: Number(component.quantity) * row.quantity, reason: d.reason, reference: sale.saleNumber });
          } else {
            const factor = Number(row.item.stockQuantity) / Number(row.item.quantity);
            await this.stock.move(tx, { businessId: u.businessId, userId: u.sub, productId: row.item.productId, type: "return_in", change: row.quantity * factor, reason: d.reason, reference: sale.saleNumber });
          }
        }
      }
      await tx.sale.update({ where: { id: sale.id }, data: { total: newTotal, amountPaid: newPaid, balanceDue: newBalance, status: allReturned ? "refunded" : "partially_returned" } });
      if (sale.customerId) {
        const balanceChangeCents = cents(newBalance) - cents(sale.balanceDue);
        if (balanceChangeCents) await tx.customer.update({ where: { id: sale.customerId }, data: { balance: { increment: money(balanceChangeCents) } } });
      }
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "sale.returned", entity: "sale", entityId: sale.id, meta: { returnId: record.id, total: returnTotal, refundAmount, restock: d.restock } } });
      return { id: record.id, saleId: sale.id, returnedTotal: returnTotal, refunded: refundAmount, balanceDue: newBalance };
    }, { timeout: 120000 });
  }
}
@Module({
  imports: [StockModule],
  controllers: [SalesController],
  providers: [AuthGuard],
})
export class SalesModule {}
