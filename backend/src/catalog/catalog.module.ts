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
} from "class-validator";
import { PrismaService } from "../prisma.service";
import { Prisma } from "@prisma/client";
import { createHash } from "node:crypto";
import { AuthGuard, Me, Roles } from "../common/auth";
import { StockModule, StockService } from "../stock/stock.module";

const UNITS = ["piece", "kg", "litre", "packet", "carton", "bale", "other"];
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
}
class ListQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page = 1;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 20;
  @IsOptional() @IsString() search?: string;
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
      const matches = await this.db.$queryRaw<Array<{ id: string }>>(Prisma.sql`
        SELECT p."id" FROM "Product" p
        LEFT JOIN "StockLevel" s ON s."productId" = p."id"
        WHERE p."businessId" = ${u.businessId}::uuid
          AND p."deletedAt" IS NULL AND p."active" = true
          AND ${categoryCondition} AND ${searchCondition}
          AND ${stockCondition}
      `);
      statusIds = matches.map((row) => row.id);
    }
    const where: any = {
      businessId: u.businessId, deletedAt: null, active: true,
      ...(statusIds ? { id: { in: statusIds } } : {}),
      ...(q.categoryId ? { categoryId: q.categoryId } : {}),
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
      this.db.product.findMany({ where, include: { category: true, stock: true }, orderBy, skip: (page - 1) * limit, take: limit }),
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
    const p = await this.db.product.findFirst({
      where: { businessId: u.businessId, deletedAt: null, active: true, ...(barcode ? { barcode } : { sku }) },
      include: { category: true, stock: true },
    });
    if (!p) throw new NotFoundException("Product not found");
    return { ...p, quantity: Number(p.stock?.quantity ?? 0) };
  }
  @Get(":id") async get(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    const p = await this.db.product.findFirst({ where: { id, businessId: u.businessId, deletedAt: null }, include: { category: true, stock: true } });
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
    if (d.categoryId && !(await this.db.category.findFirst({ where: { id: d.categoryId, businessId: u.businessId } })))
      throw new NotFoundException("Category not found");
    try { return await this.db.$transaction(async (tx) => {
      await this.lockIdentifiers(tx, u.businessId);
      await this.assertIdentifiers(tx, u.businessId, d.sku ?? p.sku, d.barcode ?? p.barcode, id);
      const updated = await tx.product.update({ where: { id }, data: d });
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
@Module({ imports: [StockModule], controllers: [CategoriesController, ProductsController], providers: [AuthGuard] })
export class CatalogModule {}
