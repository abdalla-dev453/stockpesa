import {
  BadRequestException,
  ConflictException,
  Controller,
  Delete,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Body,
  Query,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  Headers,
  UnprocessableEntityException,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { Type } from "class-transformer";
import {
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Min,
  IsNotEmpty,
  IsInt,
  Max,
  IsArray,
  ArrayMinSize,
  IsObject,
  IsUrl,
  IsDateString,
  IsPositive,
  ValidateNested,
} from "class-validator";
import { PrismaService } from "../prisma.service";
import { Prisma } from "@prisma/client";
import { createHash } from "node:crypto";
import { AuthGuard, Me, Roles } from "../common/auth";
import { StockModule, StockService } from "../stock/stock.module";
import { StorageModule } from "../common/storage/storage.module";
import { STORAGE_PROVIDER } from "../common/storage/storage.token";
import { StorageProvider } from "../common/storage/storage.interface";
import { Inject } from "@nestjs/common";
import { Throttle } from "@nestjs/throttler";

const UNITS = ["piece", "kg", "gram", "litre", "millilitre", "packet", "carton", "bale", "dozen", "bottle", "pack", "other"];
class CategoryDto {
  @IsString() @IsNotEmpty() name: string;
}
class ProductDto {
  @IsString() @IsNotEmpty() name: string;
  @IsOptional() @IsString() sku?: string;
  @IsOptional() @IsString() barcode?: string;
  @IsOptional() @IsUUID() categoryId?: string;
  @IsOptional() @IsString() brand?: string;
  @IsIn(UNITS) unit: string;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) buyingPrice: number;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) sellingPrice: number;
  @IsOptional() @IsUrl({ require_protocol: true }) imageUrl?: string;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) minStock?: number;
}
class ProductPatchDto {
  @IsOptional() @IsString() @IsNotEmpty() name?: string;
  @IsOptional() @IsString() sku?: string;
  @IsOptional() @IsString() barcode?: string;
  @IsOptional() @IsUUID() categoryId?: string;
  @IsOptional() @IsString() brand?: string;
  @IsOptional() @IsIn(UNITS) unit?: string;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) buyingPrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) sellingPrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) minStock?: number;
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) wholesalePrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) promotionalPrice?: number | null;
  @IsOptional() @IsDateString() promotionStartsAt?: string | null;
  @IsOptional() @IsDateString() promotionEndsAt?: string | null;
  @IsOptional() @IsIn(["ACTIVE", "INACTIVE", "DISCONTINUED", "OUT_OF_SEASON"]) status?: string;
  @IsOptional() @IsBoolean() expiryTracking?: boolean;
  @IsOptional() @IsBoolean() batchTracking?: boolean;
  @IsOptional() @IsUrl({ require_protocol: true }) imageUrl?: string | null;
}
class ListQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page = 1;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 20;
  @IsOptional() @IsString() search?: string;
  @IsOptional() @IsString() brand?: string;
  @IsOptional() @IsString() tag?: string;
  @IsOptional() @IsIn(["ACTIVE", "INACTIVE", "DISCONTINUED", "OUT_OF_SEASON", "ALL"]) status = "ACTIVE";
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) priceMin?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) priceMax?: number;
  @IsOptional() @IsUUID() categoryId?: string;
  @IsOptional() @IsIn(["ALL", "IN_STOCK", "LOW_STOCK", "OUT_OF_STOCK"]) stockStatus?: string;
  @IsOptional() @IsIn(["name", "createdAt", "stockQuantity", "sellingPrice"]) sortBy = "name";
  @IsOptional() @IsIn(["ASC", "DESC"]) sortOrder = "ASC";
}

function parseCsv(text: string): string[][] {
  const rows: string[][] = []; let row: string[] = [], field = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) { if (c === '"' && text[i + 1] === '"') { field += '"'; i++; } else if (c === '"') quoted = false; else field += c; }
    else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(field); if (row.some((x) => x.trim())) rows.push(row); row = []; field = ''; }
    else field += c;
  }
  if (quoted) throw new BadRequestException("CSV contains an unclosed quoted field");
  row.push(field); if (row.some((x) => x.trim())) rows.push(row);
  return rows;
}

@Controller("categories")
@UseGuards(AuthGuard)
class CategoriesController {
  constructor(private db: PrismaService) {}
  @Get() list(@Me() u) {
    return this.db.category.findMany({
      where: { businessId: u.businessId },
      include: { _count: { select: { products: { where: { deletedAt: null } } } } },
      orderBy: { name: "asc" },
    });
  }
  @Post() @Roles("OWNER", "MANAGER") async create(@Me() u, @Body() d: CategoryDto) {
    try {
      return await this.db.category.create({ data: { name: d.name.trim(), businessId: u.businessId } });
    } catch (e: any) {
      if (e.code === "P2002") throw new ConflictException("Category already exists");
      throw e;
    }
  }
  @Patch(":id") @Roles("OWNER", "MANAGER") async update(
    @Me() u, @Param("id", ParseUUIDPipe) id: string, @Body() d: CategoryDto,
  ) {
    const row = await this.db.category.findFirst({ where: { id, businessId: u.businessId } });
    if (!row) throw new NotFoundException("Category not found");
    try {
      return await this.db.category.update({ where: { id }, data: { name: d.name.trim() } });
    } catch (e: any) {
      if (e.code === "P2002") throw new ConflictException("Category already exists");
      throw e;
    }
  }
  @Delete(":id") @Roles("OWNER", "MANAGER") async remove(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const row = await this.db.category.findFirst({ where: { id, businessId: u.businessId } });
    if (!row) throw new NotFoundException("Category not found");
    if (await this.db.product.count({ where: { categoryId: id, deletedAt: null } }))
      throw new BadRequestException("Move products out of this category first");
    await this.db.$transaction(async (tx) => {
      await tx.category.delete({ where: { id } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "category.deleted", entity: "category", entityId: id, meta: { name: row.name } } });
    });
    return { deleted: true };
  }
}

@Controller("products")
@UseGuards(AuthGuard)
class ProductsController {
  constructor(private db: PrismaService, private stock: StockService) {}
  private async lockIdentifiers(tx: any, businessId: string) {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${businessId + ":product-identifiers"}))`;
  }
  private async assertIdentifiers(tx: any, businessId: string, sku?: string | null, barcode?: string | null, exceptId?: string) {
    const identifiers = [sku, barcode].filter(Boolean);
    if (!identifiers.length) return;
    const existing = await tx.product.findFirst({ where: {
      businessId,
      OR: [{ sku: { in: identifiers } }, { barcode: { in: identifiers } }],
      ...(exceptId ? { id: { not: exceptId } } : {}),
    }, select: { id: true } });
    if (existing) throw new ConflictException("SKU or barcode is already used by another product in this business");
  }
  @Get() async list(@Me() u, @Query() q: ListQuery) {
    if (q.priceMin !== undefined && q.priceMax !== undefined && q.priceMin > q.priceMax) throw new BadRequestException("Minimum price must be less than maximum price");
    const page = Math.max(1, Number(q.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(q.limit) || 20));
    let statusIds: string[] | undefined;
    if (q.stockStatus && q.stockStatus !== "ALL") {
      const stockCondition = q.stockStatus === "OUT_OF_STOCK"
        ? Prisma.sql`(s."quantity" IS NULL OR s."quantity" <= 0)`
        : q.stockStatus === "LOW_STOCK"
          ? Prisma.sql`(s."quantity" > 0 AND s."quantity" <= p."minStock")`
          : Prisma.sql`(s."quantity" > p."minStock")`;
      const categoryCondition = q.categoryId
        ? Prisma.sql`p."categoryId" = ${q.categoryId}::uuid`
        : Prisma.sql`TRUE`;
      const searchPattern = `%${q.search ?? ""}%`;
      const searchCondition = q.search
        ? Prisma.sql`(p."name" ILIKE ${searchPattern} OR p."sku" ILIKE ${searchPattern} OR p."barcode" ILIKE ${searchPattern})`
        : Prisma.sql`TRUE`;
      const statusCondition = q.status === "ALL" ? Prisma.sql`TRUE` : Prisma.sql`p."status" = ${q.status}::"ProductStatus"`;
      const matches = await this.db.$queryRaw<Array<{ id: string }>>(Prisma.sql`
        SELECT p."id" FROM "Product" p
        LEFT JOIN "StockLevel" s ON s."productId" = p."id"
        WHERE p."businessId" = ${u.businessId}::uuid
          AND p."deletedAt" IS NULL AND ${statusCondition}
          AND ${categoryCondition} AND ${searchCondition}
          AND ${stockCondition}
      `);
      statusIds = matches.map((row) => row.id);
    }
    const where: any = {
      businessId: u.businessId, deletedAt: null,
      ...(q.status !== "ALL" ? { status: q.status } : {}),
      ...(q.status === "ACTIVE" ? { active: true } : {}),
      ...(statusIds ? { id: { in: statusIds } } : {}),
      ...(q.categoryId ? { categoryId: q.categoryId } : {}),
      ...(q.brand ? { brand: { contains: q.brand, mode: "insensitive" } } : {}),
      ...(q.tag ? { productTags: { some: { tag: { name: { contains: q.tag, mode: "insensitive" } } } } } : {}),
      ...(q.priceMin !== undefined || q.priceMax !== undefined ? { sellingPrice: { ...(q.priceMin !== undefined ? { gte: q.priceMin } : {}), ...(q.priceMax !== undefined ? { lte: q.priceMax } : {}) } } : {}),
      ...(q.search ? { OR: [
        { name: { contains: q.search, mode: "insensitive" } },
        { sku: { contains: q.search, mode: "insensitive" } },
        { barcode: { contains: q.search, mode: "insensitive" } },
      ] } : {}),
    };
    const direction = q.sortOrder === "DESC" ? "desc" : "asc";
    const orderBy: any = q.sortBy === "stockQuantity"
      ? [{ stock: { quantity: direction } }, { name: "asc" }]
      : [{ [q.sortBy ?? "name"]: direction }];
    const [total, products] = await this.db.$transaction([
      this.db.product.count({ where }),
      this.db.product.findMany({ where, include: { category: true, stock: true, variants: { where: { deletedAt: null, active: true } }, images: { orderBy: { sortOrder: "asc" } }, productTags: { include: { tag: true } } }, orderBy, skip: (page - 1) * limit, take: limit }),
    ]);
    const data = products.map((p: any) => {
      const quantity = Number(p.stock?.quantity ?? 0);
      const stockStatus = quantity <= 0 ? "OUT_OF_STOCK" : quantity <= Number(p.minStock) ? "LOW_STOCK" : "IN_STOCK";
      return { ...p, quantity, stockStatus, stockValue: quantity * Number(p.buyingPrice), retailValue: quantity * Number(p.sellingPrice) };
    });
    return { data, meta: { page, limit, total, totalPages: Math.ceil(total / limit) } };
  }
  @Get("lookup") async lookup(@Me() u, @Query("barcode") barcode?: string, @Query("sku") sku?: string) {
    if (!!barcode === !!sku) throw new BadRequestException("Provide exactly one barcode or SKU");
    const variant = await this.db.productVariant.findFirst({
      where: { businessId: u.businessId, deletedAt: null, active: true, ...(barcode ? { barcode } : { sku }), product: { deletedAt: null, active: true } },
      include: { product: true },
    });
    if (variant) return {
      ...variant,
      id: variant.id,
      variantId: variant.id,
      parentProductId: variant.productId,
      name: `${variant.product.name} · ${variant.name}`,
      brand: variant.product.brand,
      categoryId: variant.product.categoryId,
      category: null,
      quantity: Number(variant.quantity),
    };
    const p = await this.db.product.findFirst({
      where: { businessId: u.businessId, deletedAt: null, active: true, ...(barcode ? { barcode } : { sku }) },
      include: { category: true, stock: true, variants: { where: { deletedAt: null, active: true } } },
    });
    if (!p) throw new NotFoundException("Product not found");
    return { ...p, quantity: Number(p.stock?.quantity ?? 0) };
  }
  @Get(":id") async get(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const p = await this.db.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null }, include: { category: true, stock: true, variants: { where: { deletedAt: null, active: true } }, images: { orderBy: { sortOrder: "asc" } }, productTags: { include: { tag: true } }, bundleItems: { include: { component: true } } } });
    if (!p) throw new NotFoundException("Product not found");
    return { ...p, quantity: Number(p.stock?.quantity ?? 0) };
  }
  @Post() @Roles("OWNER", "MANAGER") async create(@Me() u, @Body() d: ProductDto) {
    if (d.categoryId && !(await this.db.category.findFirst({ where: { id: d.categoryId, businessId: u.businessId } })))
      throw new NotFoundException("Category not found");
    try { return await this.db.$transaction(async (tx) => {
      await this.lockIdentifiers(tx, u.businessId);
      await this.assertIdentifiers(tx, u.businessId, d.sku, d.barcode);
      return tx.product.create({ data: { ...d, businessId: u.businessId } });
    }); }
    catch (e: any) { if (e.code === "P2002") throw new ConflictException("SKU or barcode is already in use"); throw e; }
  }
  @Patch(":id") @Roles("OWNER", "MANAGER") async update(@Me() u, @Param("id", ParseUUIDPipe) id: string, @Body() d: ProductPatchDto) {
    const p = await this.db.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!p) throw new NotFoundException("Product not found");
    if (d.promotionStartsAt && d.promotionEndsAt && new Date(d.promotionStartsAt) > new Date(d.promotionEndsAt)) throw new BadRequestException("Promotion start must be before its end");
    if (d.categoryId && !(await this.db.category.findFirst({ where: { id: d.categoryId, businessId: u.businessId } })))
      throw new NotFoundException("Category not found");
    try { return await this.db.$transaction(async (tx) => {
      await this.lockIdentifiers(tx, u.businessId);
      await this.assertIdentifiers(tx, u.businessId, d.sku ?? p.sku, d.barcode ?? p.barcode, id);
      const updated = await tx.product.update({ where: { id }, data: { ...d, ...(d.status ? { active: d.status === "ACTIVE" } : {}) } as any });
      if (d.buyingPrice !== undefined || d.sellingPrice !== undefined || d.wholesalePrice !== undefined) {
        await tx.productPriceHistory.create({ data: {
          businessId: u.businessId, userId: u.sub, productId: id,
          oldBuyingPrice: p.buyingPrice,
          oldSellingPrice: p.sellingPrice,
          oldWholesalePrice: p.wholesalePrice,
          buyingPrice: d.buyingPrice ?? p.buyingPrice,
          sellingPrice: d.sellingPrice ?? p.sellingPrice,
          wholesalePrice: d.wholesalePrice ?? p.wholesalePrice,
          reason: "Product price updated",
        } });
      }
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.updated", entity: "product", entityId: id, meta: { changedFields: Object.keys(d) } } });
      return updated;
    }); }
    catch (e: any) { if (e.code === "P2002") throw new ConflictException("SKU or barcode is already in use"); throw e; }
  }
  private async analyzeCsv(u: any, file: any) {
    if (!file?.buffer) throw new BadRequestException('Upload a CSV file in the "file" field');
    if (!/\.csv$/i.test(file.originalname ?? "")) throw new BadRequestException("Upload a .csv file");
    const rows = parseCsv(file.buffer.toString("utf8").replace(/^\uFEFF/, ""));
    if (rows.length < 2) throw new UnprocessableEntityException("CSV needs a header and at least one product row");
    if (rows.length > 1001) throw new UnprocessableEntityException("Import is limited to 1,000 products");
    const headers = rows[0].map((v) => v.trim().toLowerCase());
    if (new Set(headers).size !== headers.length)
      throw new UnprocessableEntityException("CSV contains duplicate column names");
    const missing = ["name", "selling_price", "unit"].filter((v) => !headers.includes(v));
    if (missing.length) throw new UnprocessableEntityException(`Missing columns: ${missing.join(", ")}`);
    const col = (r: string[], k: string) => r[headers.indexOf(k)]?.trim() ?? "";
    const products = await this.db.product.findMany({ where: { businessId: u.businessId }, select: { sku: true, barcode: true } });
    const skuSet = new Set(products.map((p) => p.sku).filter(Boolean));
    const barcodeSet = new Set(products.map((p) => p.barcode).filter(Boolean));
    const seenSku = new Set<string>(), seenBarcode = new Set<string>();
    const valid: any[] = [], invalid: any[] = [];
    rows.slice(1).forEach((r, index) => {
      const d = { name: col(r,"name"), sku: col(r,"sku") || undefined, barcode: col(r,"barcode") || undefined,
        category: col(r,"category") || undefined, brand: col(r,"brand") || undefined, unit: col(r,"unit").toLowerCase(),
        sellingPrice: Number(col(r,"selling_price")), buyingPrice: col(r,"purchase_price") === "" ? 0 : Number(col(r,"purchase_price")),
        openingStock: col(r,"opening_stock") === "" ? 0 : Number(col(r,"opening_stock")),
        minStock: col(r,"min_stock_level") === "" ? 0 : Number(col(r,"min_stock_level")) };
      const errors: string[] = [];
      if (r.length !== headers.length) errors.push("Row has a different number of columns than the header");
      if (!d.name) errors.push("Product name is required");
      if (d.name.length > 160 || (d.sku?.length ?? 0) > 80 || (d.barcode?.length ?? 0) > 80 || (d.brand?.length ?? 0) > 100)
        errors.push("Name, SKU, barcode, or brand is too long");
      if (!col(r, "selling_price")) errors.push("Selling price is required");
      if (!UNITS.includes(d.unit)) errors.push(`Unit must be one of: ${UNITS.join(", ")}`);
      for (const [label, n, precision] of [["selling_price",d.sellingPrice,2],["purchase_price",d.buyingPrice,2],["opening_stock",d.openingStock,3],["min_stock_level",d.minStock,3]] as [string,number,number][]) {
        if (!Number.isFinite(n) || n < 0) errors.push(`${label} must be zero or more`);
        else if ((col(r, label).split(".")[1]?.length ?? 0) > precision) errors.push(`${label} allows at most ${precision} decimal places`);
      }
      if (d.sku) { if (seenSku.has(d.sku) || seenBarcode.has(d.sku) || skuSet.has(d.sku) || barcodeSet.has(d.sku)) errors.push("Duplicate SKU"); seenSku.add(d.sku); }
      if (d.barcode) { if (seenBarcode.has(d.barcode) || seenSku.has(d.barcode) || barcodeSet.has(d.barcode) || skuSet.has(d.barcode)) errors.push("Duplicate barcode"); seenBarcode.add(d.barcode); }
      (errors.length ? invalid : valid).push({ line: index + 2, data: d, errors });
    });
    return { valid, invalid };
  }
  @Post("import/preview") @Roles("OWNER", "MANAGER") @UseInterceptors(FileInterceptor("file", { limits: { fileSize: 2 * 1024 * 1024 } }))
  async previewCsv(@Me() u, @UploadedFile() file: any) {
    const result = await this.analyzeCsv(u, file);
    return { totalRows: result.valid.length + result.invalid.length, validCount: result.valid.length, invalidCount: result.invalid.length, ...result };
  }
  @Post("import/confirm") @Roles("OWNER", "MANAGER") @UseInterceptors(FileInterceptor("file", { limits: { fileSize: 2 * 1024 * 1024 } }))
  async confirmCsv(@Me() u, @UploadedFile() file: any, @Query("skipInvalid") skipInvalid?: string, @Headers("idempotency-key") requestKey?: string) {
    if (!file?.buffer) throw new BadRequestException('Upload a CSV file in the "file" field');
    if (requestKey && (requestKey.length > 128 || !/^[\w.-]+$/.test(requestKey)))
      throw new BadRequestException("Invalid Idempotency-Key");
    // Content-derived identity protects retries even if the client loses the response.
    // A caller key remains supported and is bound to the exact file/options payload.
    const requestHash = createHash("sha256")
      .update(file.buffer)
      .update(`|skipInvalid=${skipInvalid === "true"}`)
      .digest("hex");
    const importKey = requestKey ?? `csv-${requestHash}`;
    const result = await this.analyzeCsv(u, file);
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":csv-import:" + importKey}))`;
      const previous = await tx.auditLog.findFirst({
        where: { businessId: u.businessId, action: "product.csv_import", entity: "products", entityId: importKey },
        select: { meta: true },
      });
      if (previous) {
        const meta = previous.meta as { requestHash?: string; created?: number; skipped?: number } | null;
        if (meta?.requestHash !== requestHash)
          throw new ConflictException("Idempotency-Key was already used for a different CSV import");
        return { created: meta.created ?? 0, skipped: meta.skipped ?? 0, replayed: true };
      }
      if (result.invalid.length && skipInvalid !== "true")
        throw new UnprocessableEntityException({ message: "Fix invalid rows or confirm with skipInvalid=true", invalid: result.invalid });
      await this.lockIdentifiers(tx, u.businessId);
      let created = 0;
      for (const { data: d } of result.valid) {
        await this.assertIdentifiers(tx, u.businessId, d.sku, d.barcode);
        const category = d.category ? await tx.category.upsert({ where: { businessId_name: { businessId: u.businessId, name: d.category } }, update: {}, create: { businessId: u.businessId, name: d.category } }) : null;
        const product = await tx.product.create({ data: { businessId: u.businessId, categoryId: category?.id, name: d.name, sku: d.sku, barcode: d.barcode, brand: d.brand, unit: d.unit, buyingPrice: d.buyingPrice, sellingPrice: d.sellingPrice, minStock: d.minStock } });
        if (d.openingStock > 0) await this.stock.move(tx, { businessId: u.businessId, userId: u.sub, productId: product.id, type: "purchase_in", change: d.openingStock, unitCost: d.buyingPrice, reason: "CSV opening stock" });
        created++;
      }
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.csv_import", entity: "products", entityId: importKey, meta: { requestHash, created, skipped: result.invalid.length } } });
      return { created, skipped: result.invalid.length, replayed: false };
    }, { timeout: 120000 });
  }
  @Delete(":id") @Roles("OWNER", "MANAGER") async remove(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const p = await this.db.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!p) throw new NotFoundException("Product not found");
    const hasHistory = (await this.db.stockMovement.count({ where: { productId: id } })) > 0 || (await this.db.saleItem.count({ where: { productId: id } })) > 0;
    return this.db.$transaction(async (tx) => {
      const result = hasHistory ? "archived" : "deleted";
      await tx.product.update({ where: { id }, data: hasHistory ? { active: false } : { active: false, deletedAt: new Date() } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: `product.${result}`, entity: "product", entityId: id, meta: { name: p.name } } });
      return { id, result };
    });
  }
}
class VariantDto {
  @IsString() @IsNotEmpty() name: string;
  @IsObject() attributes: Record<string, string>;
  @IsOptional() @IsString() sku?: string;
  @IsOptional() @IsString() barcode?: string;
  @IsIn(UNITS) unit: string;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) buyingPrice: number;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) sellingPrice: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) wholesalePrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) minStock?: number;
}
class VariantStockDto {
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @IsPositive() quantity: number;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) unitCost: number;
  @IsOptional() @IsString() reason?: string;
}
class VariantPatchDto {
  @IsOptional() @IsString() @IsNotEmpty() name?: string;
  @IsOptional() @IsObject() attributes?: Record<string, string>;
  @IsOptional() @IsString() sku?: string;
  @IsOptional() @IsString() barcode?: string;
  @IsOptional() @IsIn(UNITS) unit?: string;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) buyingPrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) sellingPrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) wholesalePrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) minStock?: number;
  @IsOptional() @IsBoolean() active?: boolean;
}
class ConversionDto {
  @IsOptional() @IsUUID() productId?: string;
  @IsString() @IsNotEmpty() fromUnit: string;
  @IsString() @IsNotEmpty() toUnit: string;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 6 }) @IsPositive() multiplier: number;
}
class BundleItemDto {
  @IsUUID() productId: string;
  @Type(() => Number) @IsNumber({ maxDecimalPlaces: 3 }) @IsPositive() quantity: number;
}
class BundleDto {
  @IsArray() @ArrayMinSize(1) @ValidateNested({ each: true }) @Type(() => BundleItemDto) items: BundleItemDto[];
}
class ImageDto {
  @IsUrl({ require_protocol: true }) url: string;
  @IsOptional() @IsString() altText?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) sortOrder?: number;
}
class MainImageDto {
  @IsOptional() @IsUrl({ require_protocol: true }) imageUrl?: string | null;
}
class TagsDto {
  @IsArray() @ArrayMinSize(0) tags: string[];
}

@Controller()
@UseGuards(AuthGuard)
class ProductPowerController {
  constructor(private db: PrismaService, @Inject(STORAGE_PROVIDER) private storage: StorageProvider) {}

  private async product(u: any, id: string) {
    const row = await this.db.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!row) throw new NotFoundException("Product not found");
    return row;
  }

  @Get("products/:id/variants")
  async variants(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    await this.product(u, id);
    return this.db.productVariant.findMany({ where: { businessId: u.businessId, productId: id, deletedAt: null }, orderBy: { name: "asc" } });
  }

  @Post("products/:id/variants") @Roles("OWNER", "MANAGER")
  async createVariant(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Body() d: VariantDto) {
    const parent = await this.db.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null }, include: { stock: true, variants: { where: { deletedAt: null } } } });
    if (!parent) throw new NotFoundException("Product not found");
    if (parent.variants.length === 0 && Number(parent.stock?.quantity ?? 0) < 0) throw new BadRequestException("Adjust negative stock before adding variants");
    const codes = [d.sku, d.barcode].filter(Boolean) as string[];
    if (codes.length) {
      const [productCode, variantCode] = await Promise.all([
        this.db.product.findFirst({ where: { businessId: u.businessId, OR: [{ sku: { in: codes } }, { barcode: { in: codes } }] }, select: { id: true } }),
        this.db.productVariant.findFirst({ where: { businessId: u.businessId, OR: [{ sku: { in: codes } }, { barcode: { in: codes } }] }, select: { id: true } }),
      ]);
      if (productCode || variantCode) throw new ConflictException("SKU or barcode is already in use");
    }
    try {
      return await this.db.$transaction(async (tx) => {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":product-variants:" + id}))`;
        const lockedParent = await tx.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null }, include: { stock: true, variants: { where: { deletedAt: null } } } });
        if (!lockedParent) throw new NotFoundException("Product not found");
        if (lockedParent.variants.length === 0 && Number(lockedParent.stock?.quantity ?? 0) < 0)
          throw new BadRequestException("Adjust negative stock before adding variants");
        if (lockedParent.variants.length === 0 && Number(lockedParent.stock?.quantity ?? 0) > 0) {
          const openingQuantity = lockedParent.stock!.quantity;
          const standard = await tx.productVariant.create({ data: {
            businessId: u.businessId, productId: id, name: "Standard", attributes: { option: "Standard" },
            sku: lockedParent.sku, barcode: lockedParent.barcode, unit: lockedParent.unit, buyingPrice: lockedParent.buyingPrice,
            sellingPrice: lockedParent.sellingPrice, wholesalePrice: lockedParent.wholesalePrice, minStock: lockedParent.minStock,
            quantity: openingQuantity,
          } });
          await tx.stockLevel.update({ where: { productId: id }, data: { quantity: 0 } });
          await tx.stockMovement.create({ data: { businessId: u.businessId, productId: id, userId: u.sub, type: "adjustment", quantityChange: -Number(openingQuantity), reason: "Moved opening stock into Standard variant" } });
          await tx.variantStockMovement.create({ data: { businessId: u.businessId, variantId: standard.id, userId: u.sub, quantityChange: openingQuantity, unitCost: parent.buyingPrice, reason: "Opening stock moved from product" } });
        }
        const created = await tx.productVariant.create({ data: { ...d, businessId: u.businessId, productId: id, attributes: d.attributes } });
        await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.variant_created", entity: "product_variant", entityId: created.id, meta: { productId: id, name: d.name } } });
        return created;
      });
    } catch (e: any) {
      if (e.code === "P2002") throw new ConflictException("SKU or barcode is already in use");
      throw e;
    }
  }

  @Get("product-variants/:id")
  async variant(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    const row = await this.db.productVariant.findFirst({ where: { id, businessId: u.businessId, deletedAt: null }, include: { product: { select: { id: true, name: true, categoryId: true } } } });
    if (!row) throw new NotFoundException("Product variant not found");
    return row;
  }

  @Patch("product-variants/:id") @Roles("OWNER", "MANAGER")
  async updateVariant(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Body() d: VariantPatchDto) {
    const current = await this.db.productVariant.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!current) throw new NotFoundException("Product variant not found");
    if (d.active === false && Number(current.quantity) > 0) throw new BadRequestException("Receive or sell the remaining variant stock before deactivating it");
    const codes = [d.sku, d.barcode].filter(Boolean) as string[];
    if (codes.length) {
      const [productCode, variantCode] = await Promise.all([
        this.db.product.findFirst({ where: { businessId: u.businessId, OR: [{ sku: { in: codes } }, { barcode: { in: codes } }] }, select: { id: true } }),
        this.db.productVariant.findFirst({ where: { businessId: u.businessId, id: { not: id }, OR: [{ sku: { in: codes } }, { barcode: { in: codes } }] }, select: { id: true } }),
      ]);
      if (productCode || variantCode) throw new ConflictException("SKU or barcode is already in use");
    }
    return this.db.$transaction(async (tx) => {
      const updated = await tx.productVariant.update({ where: { id }, data: d });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.variant_updated", entity: "product_variant", entityId: id, meta: { changedFields: Object.keys(d) } } });
      return updated;
    });
  }

  @Delete("product-variants/:id") @Roles("OWNER", "MANAGER")
  async archiveVariant(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    const current = await this.db.productVariant.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!current) throw new NotFoundException("Product variant not found");
    if (Number(current.quantity) > 0) throw new BadRequestException("Receive or sell the remaining variant stock before archiving it");
    await this.db.$transaction(async (tx) => {
      await tx.productVariant.update({ where: { id }, data: { active: false, deletedAt: new Date() } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.variant_archived", entity: "product_variant", entityId: id } });
    });
    return { id, result: "archived" };
  }

  @Post("product-variants/:id/stock") @Roles("OWNER", "MANAGER", "STOREKEEPER")
  async receiveVariantStock(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Body() d: VariantStockDto, @Headers("idempotency-key") key?: string) {
    if (key && (key.length > 128 || !/^[\w.-]+$/.test(key))) throw new BadRequestException("Invalid Idempotency-Key");
    return this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":variant:" + id}))`;
      if (key) {
        const prior = await tx.variantStockMovement.findFirst({ where: { businessId: u.businessId, idempotencyKey: key } });
        if (prior) {
          if (prior.variantId !== id || Number(prior.quantityChange) !== d.quantity || Number(prior.unitCost ?? 0) !== d.unitCost || (prior.reason ?? "") !== (d.reason ?? "Stock received")) throw new ConflictException("Idempotency-Key was already used for a different stock receipt");
          return { movement: prior, replayed: true };
        }
      }
      const variant = await tx.productVariant.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
      if (!variant) throw new NotFoundException("Product variant not found");
      const updated = await tx.productVariant.update({ where: { id }, data: { quantity: { increment: d.quantity }, buyingPrice: d.unitCost } });
      const movement = await tx.variantStockMovement.create({ data: { businessId: u.businessId, variantId: id, userId: u.sub, quantityChange: d.quantity, unitCost: d.unitCost, reason: d.reason ?? "Stock received", idempotencyKey: key } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "variant.stock_received", entity: "product_variant", entityId: id, meta: { quantity: d.quantity, unitCost: d.unitCost } } });
      return { variant: updated, movement, replayed: false };
    });
  }

  @Get("product-variants/:id/movements")
  async variantMovements(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    if (!(await this.db.productVariant.findFirst({ where: { id, businessId: u.businessId } }))) throw new NotFoundException("Product variant not found");
    return this.db.variantStockMovement.findMany({ where: { businessId: u.businessId, variantId: id }, orderBy: { createdAt: "desc" }, take: 100 });
  }

  @Get("products/:id/price-history")
  async priceHistory(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    await this.product(u, id);
    return this.db.productPriceHistory.findMany({ where: { businessId: u.businessId, productId: id }, orderBy: { createdAt: "desc" }, take: 100 });
  }

  @Get("products/:id/movements")
  async productMovements(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    await this.product(u, id);
    return this.db.stockMovement.findMany({ where: { businessId: u.businessId, productId: id }, orderBy: { createdAt: "desc" }, take: 100 });
  }

  @Get("products/:id/bundle")
  async getBundle(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    await this.product(u, id);
    const bundle = await this.db.productBundle.findFirst({ where: { businessId: u.businessId, productId: id } });
    if (!bundle) return { items: [] };
    const items = await this.db.bundleItem.findMany({ where: { businessId: u.businessId, bundleProductId: id }, include: { component: { select: { id: true, name: true, sku: true, unit: true } } } });
    return { ...bundle, items };
  }

  @Put("products/:id/bundle") @Roles("OWNER", "MANAGER")
  async setBundle(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Body() d: BundleDto) {
    const parent = await this.db.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null }, include: { stock: true, variants: { where: { deletedAt: null } } } });
    if (!parent) throw new NotFoundException("Product not found");
    if (parent.variants.length || Number(parent.stock?.quantity ?? 0) !== 0) throw new BadRequestException("Move existing stock and remove variants before making this a bundle");
    if (d.items.some((item) => item.productId === id)) throw new BadRequestException("A bundle cannot contain itself");
    if (new Set(d.items.map((item) => item.productId)).size !== d.items.length) throw new BadRequestException("Each bundle product can only be added once");
    const ids = [...new Set(d.items.map((x) => x.productId))];
    const valid = await this.db.product.count({ where: { businessId: u.businessId, id: { in: ids }, deletedAt: null, active: true } });
    if (valid !== ids.length) throw new BadRequestException("One or more bundle products are unavailable");
    if (await this.db.productBundle.count({ where: { businessId: u.businessId, productId: { in: ids } } })) throw new BadRequestException("Bundles cannot contain other bundles");
    return this.db.$transaction(async (tx) => {
      const bundle = await tx.productBundle.upsert({ where: { productId: id }, create: { businessId: u.businessId, productId: id }, update: {} });
      await tx.bundleItem.deleteMany({ where: { businessId: u.businessId, bundleProductId: id } });
      await tx.bundleItem.createMany({ data: d.items.map((item) => ({ businessId: u.businessId, bundleProductId: id, componentId: item.productId, quantity: item.quantity })) });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.bundle_updated", entity: "product", entityId: id, meta: { itemCount: d.items.length } } });
      return { ...bundle, items: d.items };
    });
  }

  @Get("unit-conversions")
  conversions(@Me() u: any, @Query("productId") productId?: string) {
    return this.db.unitConversion.findMany({ where: { businessId: u.businessId, ...(productId ? { OR: [{ productId }, { productId: null }] } : {}) }, orderBy: [{ fromUnit: "asc" }, { toUnit: "asc" }] });
  }

  @Post("unit-conversions") @Roles("OWNER", "MANAGER")
  async createConversion(@Me() u: any, @Body() d: ConversionDto) {
    if (d.fromUnit.trim().toLowerCase() === d.toUnit.trim().toLowerCase()) throw new BadRequestException("Choose two different units");
    if (d.productId) await this.product(u, d.productId);
    const knownUnits = new Set(UNITS);
    const fromUnit = d.fromUnit.trim().toLowerCase(), toUnit = d.toUnit.trim().toLowerCase();
    if (!knownUnits.has(fromUnit) || !knownUnits.has(toUnit)) throw new BadRequestException(`Units must be one of: ${UNITS.join(", ")}`);
    const dimension = (unit: string) => ["kg", "gram"].includes(unit) ? "weight" : ["litre", "millilitre"].includes(unit) ? "volume" : "count";
    if (dimension(fromUnit) !== dimension(toUnit)) throw new BadRequestException("These units cannot be converted into each other");
    try {
      return await this.db.$transaction(async (tx) => {
        const scope = d.productId ?? "business";
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.businessId + ":unit-conversion:" + scope}))`;
        if (await tx.unitConversion.findFirst({ where: { businessId: u.businessId, productId: d.productId ?? null, OR: [{ fromUnit, toUnit }, { fromUnit: toUnit, toUnit: fromUnit }] } }))
          throw new ConflictException("That unit conversion or its reverse already exists");
        const conversion = await tx.unitConversion.create({ data: { businessId: u.businessId, productId: d.productId, fromUnit, toUnit, multiplier: d.multiplier } });
        await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.unit_conversion_created", entity: "unit_conversion", entityId: conversion.id, meta: { productId: d.productId ?? null, fromUnit, toUnit, multiplier: d.multiplier } } });
        return conversion;
      });
    } catch (e: any) { if (e.code === "P2002") throw new ConflictException("That unit conversion already exists"); throw e; }
  }

  @Get("products/:id/images")
  async images(@Me() u: any, @Param("id", ParseUUIDPipe) id: string) {
    await this.product(u, id);
    return this.db.productImage.findMany({ where: { businessId: u.businessId, productId: id }, orderBy: { sortOrder: "asc" } });
  }

  @Post("products/:id/images") @Roles("OWNER", "MANAGER") @Throttle({ default: { limit: 10, ttl: 60000 } })
  async addImage(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Body() d: ImageDto) {
    if (!d.url.startsWith("https://")) throw new BadRequestException("Use a secure HTTPS image URL");
    await this.product(u, id);
    return this.db.$transaction(async (tx) => {
      const image = await tx.productImage.create({ data: { businessId: u.businessId, productId: id, ...d } });
      if (!(await tx.product.findUnique({ where: { id }, select: { imageUrl: true } }))?.imageUrl) await tx.product.update({ where: { id }, data: { imageUrl: d.url } });
      return image;
    });
  }

  @Post("products/:id/images/upload") @Roles("OWNER", "MANAGER") @Throttle({ default: { limit: 5, ttl: 60000 } })
  @UseInterceptors(FileInterceptor("file", {
    limits: { fileSize: 5 * 1024 * 1024 },
    fileFilter: (_req, file, done) => {
      if (!["image/jpeg", "image/png", "image/webp"].includes(file.mimetype)) return done(new BadRequestException("Upload a JPEG, PNG, or WebP image"), false);
      done(null, true);
    },
  }))
  async uploadImage(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @UploadedFile() file?: any) {
    if (!file?.buffer?.length) throw new BadRequestException("Choose an image to upload");
    const signature = file.mimetype === "image/jpeg" ? file.buffer.subarray(0, 3).toString("hex") === "ffd8ff"
      : file.mimetype === "image/png" ? file.buffer.subarray(0, 8).toString("hex") === "89504e470d0a1a0a"
      : file.buffer.subarray(0, 4).toString("ascii") === "RIFF" && file.buffer.subarray(8, 12).toString("ascii") === "WEBP";
    if (!signature) throw new BadRequestException("The uploaded file is not a valid image");
    await this.product(u, id);
    const uploaded = await this.storage.upload(file);
    try {
      return await this.db.$transaction(async (tx) => {
        const image = await tx.productImage.create({ data: { businessId: u.businessId, productId: id, url: uploaded.url, altText: file.originalname.slice(0, 200) } });
        if (!(await tx.product.findUnique({ where: { id }, select: { imageUrl: true } }))?.imageUrl) await tx.product.update({ where: { id }, data: { imageUrl: uploaded.url } });
        return image;
      });
    } catch (error) { await this.storage.delete(uploaded.key).catch(() => undefined); throw error; }
  }

  @Delete("products/:id/images/:imageId") @Roles("OWNER", "MANAGER")
  async removeImage(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Param("imageId", ParseUUIDPipe) imageId: string) {
    await this.product(u, id);
    const image = await this.db.productImage.findFirst({ where: { id: imageId, productId: id, businessId: u.businessId } });
    if (!image) throw new NotFoundException("Product image not found");
    await this.db.$transaction(async (tx) => {
      await tx.productImage.delete({ where: { id: imageId } });
      const next = await tx.productImage.findFirst({ where: { productId: id, businessId: u.businessId }, orderBy: { sortOrder: "asc" } });
      const product = await tx.product.findUnique({ where: { id }, select: { imageUrl: true } });
      if (product?.imageUrl === image.url) await tx.product.update({ where: { id }, data: { imageUrl: next?.url ?? null } });
    });
    return { deleted: true };
  }

  @Patch("products/:id/main-image") @Roles("OWNER", "MANAGER")
  async setMainImage(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Body() d: MainImageDto) {
    await this.product(u, id);
    if (d.imageUrl !== undefined && d.imageUrl !== null && !d.imageUrl.startsWith("https://")) {
      throw new BadRequestException("Use a secure HTTPS image URL");
    }
    return await this.db.$transaction(async (tx) => {
      const updated = await tx.product.update({ where: { id }, data: { imageUrl: d.imageUrl ?? null } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "product.main_image_updated", entity: "product", entityId: id, meta: { imageUrl: d.imageUrl } } });
      return updated;
    });
  }

  @Get("product-tags")
  tags(@Me() u: any) { return this.db.productTag.findMany({ where: { businessId: u.businessId }, orderBy: { name: "asc" } }); }

  @Put("products/:id/tags") @Roles("OWNER", "MANAGER")
  async setTags(@Me() u: any, @Param("id", ParseUUIDPipe) id: string, @Body() d: TagsDto) {
    await this.product(u, id);
    const names = [...new Set(d.tags.map((tag) => tag.trim()).filter(Boolean))];
    if (names.length > 20 || names.some((name) => name.length > 40)) throw new BadRequestException("Use up to 20 tags, with names under 40 characters");
    await this.db.$transaction(async (tx) => {
      const tagIds: string[] = [];
      for (const name of names) tagIds.push((await tx.productTag.upsert({ where: { businessId_name: { businessId: u.businessId, name } }, create: { businessId: u.businessId, name }, update: {} })).id);
      await tx.productTagAssignment.deleteMany({ where: { productId: id } });
      if (tagIds.length) await tx.productTagAssignment.createMany({ data: tagIds.map((tagId) => ({ businessId: u.businessId, productId: id, tagId })) });
    });
    return this.db.productTag.findMany({ where: { businessId: u.businessId, products: { some: { productId: id } } } });
  }
}

@Module({ imports: [StockModule, StorageModule], controllers: [CategoriesController, ProductPowerController, ProductsController], providers: [AuthGuard] })
export class CatalogModule {}
