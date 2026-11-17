CREATE TYPE "ProductStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'DISCONTINUED', 'OUT_OF_SEASON');

ALTER TABLE "Product"
  ADD COLUMN "promotionalPrice" DECIMAL(14,2),
  ADD COLUMN "promotionStartsAt" TIMESTAMP(3),
  ADD COLUMN "promotionEndsAt" TIMESTAMP(3),
  ADD COLUMN "status" "ProductStatus" NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN "expiryTracking" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "batchTracking" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE "ProductVariant" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "attributes" JSONB NOT NULL,
  "sku" TEXT,
  "barcode" TEXT,
  "unit" TEXT NOT NULL,
  "buyingPrice" DECIMAL(14,2) NOT NULL,
  "sellingPrice" DECIMAL(14,2) NOT NULL,
  "wholesalePrice" DECIMAL(14,2),
  "promotionalPrice" DECIMAL(14,2),
  "promotionStartsAt" TIMESTAMP(3),
  "promotionEndsAt" TIMESTAMP(3),
  "minStock" DECIMAL(14,3) NOT NULL DEFAULT 0,
  "quantity" DECIMAL(14,3) NOT NULL DEFAULT 0,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "deletedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ProductVariant_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ProductVariant_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "ProductVariant_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "ProductVariant_nonnegative_prices" CHECK ("buyingPrice" >= 0 AND "sellingPrice" >= 0 AND ("wholesalePrice" IS NULL OR "wholesalePrice" >= 0) AND ("promotionalPrice" IS NULL OR "promotionalPrice" >= 0)),
  CONSTRAINT "ProductVariant_positive_min_stock" CHECK ("minStock" >= 0 AND "quantity" >= 0)
);
CREATE UNIQUE INDEX "ProductVariant_businessId_sku_key" ON "ProductVariant"("businessId", "sku");
CREATE UNIQUE INDEX "ProductVariant_businessId_barcode_key" ON "ProductVariant"("businessId", "barcode");
CREATE INDEX "ProductVariant_businessId_productId_idx" ON "ProductVariant"("businessId", "productId");

CREATE TABLE "VariantStockMovement" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "variantId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "quantityChange" DECIMAL(14,3) NOT NULL,
  "unitCost" DECIMAL(14,2),
  "reason" TEXT,
  "reference" TEXT,
  "idempotencyKey" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "VariantStockMovement_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "VariantStockMovement_variantId_fkey" FOREIGN KEY ("variantId") REFERENCES "ProductVariant"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "VariantStockMovement_businessId_idempotencyKey_key" ON "VariantStockMovement"("businessId", "idempotencyKey");
CREATE INDEX "VariantStockMovement_businessId_variantId_createdAt_idx" ON "VariantStockMovement"("businessId", "variantId", "createdAt");

CREATE TABLE "ProductBundle" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ProductBundle_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ProductBundle_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "ProductBundle_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "ProductBundle_productId_key" ON "ProductBundle"("productId");
CREATE INDEX "ProductBundle_businessId_idx" ON "ProductBundle"("businessId");

CREATE TABLE "BundleItem" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "bundleProductId" UUID NOT NULL,
  "componentId" UUID NOT NULL,
  "quantity" DECIMAL(14,3) NOT NULL,
  CONSTRAINT "BundleItem_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "BundleItem_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "BundleItem_bundleProductId_fkey" FOREIGN KEY ("bundleProductId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "BundleItem_componentId_fkey" FOREIGN KEY ("componentId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "BundleItem_positive_quantity" CHECK ("quantity" > 0)
);
CREATE UNIQUE INDEX "BundleItem_bundleProductId_componentId_key" ON "BundleItem"("bundleProductId", "componentId");
CREATE INDEX "BundleItem_businessId_componentId_idx" ON "BundleItem"("businessId", "componentId");

CREATE TABLE "UnitConversion" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "productId" UUID,
  "fromUnit" TEXT NOT NULL,
  "toUnit" TEXT NOT NULL,
  "multiplier" DECIMAL(14,6) NOT NULL,
  CONSTRAINT "UnitConversion_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "UnitConversion_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "UnitConversion_positive_multiplier" CHECK ("multiplier" > 0),
  CONSTRAINT "UnitConversion_distinct_units" CHECK ("fromUnit" <> "toUnit")
);
CREATE UNIQUE INDEX "UnitConversion_businessId_productId_fromUnit_toUnit_key" ON "UnitConversion"("businessId", "productId", "fromUnit", "toUnit");
CREATE INDEX "UnitConversion_businessId_idx" ON "UnitConversion"("businessId");

CREATE TABLE "ProductImage" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "url" TEXT NOT NULL,
  "altText" TEXT,
  "sortOrder" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ProductImage_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ProductImage_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "ProductImage_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX "ProductImage_businessId_productId_sortOrder_idx" ON "ProductImage"("businessId", "productId", "sortOrder");

CREATE TABLE "ProductTag" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "name" TEXT NOT NULL,
  "color" TEXT,
  CONSTRAINT "ProductTag_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ProductTag_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "ProductTag_businessId_name_key" ON "ProductTag"("businessId", "name");

CREATE TABLE "ProductTagAssignment" (
  "productId" UUID NOT NULL,
  "tagId" UUID NOT NULL,
  CONSTRAINT "ProductTagAssignment_pkey" PRIMARY KEY ("productId", "tagId"),
  CONSTRAINT "ProductTagAssignment_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "ProductTagAssignment_tagId_fkey" FOREIGN KEY ("tagId") REFERENCES "ProductTag"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE "ProductPriceHistory" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "buyingPrice" DECIMAL(14,2) NOT NULL,
  "sellingPrice" DECIMAL(14,2) NOT NULL,
  "wholesalePrice" DECIMAL(14,2),
  "reason" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ProductPriceHistory_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ProductPriceHistory_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "ProductPriceHistory_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX "ProductPriceHistory_businessId_productId_createdAt_idx" ON "ProductPriceHistory"("businessId", "productId", "createdAt");

ALTER TABLE "SaleItem" ADD COLUMN "variantId" UUID;
ALTER TABLE "SaleItem" ADD CONSTRAINT "SaleItem_variantId_fkey" FOREIGN KEY ("variantId") REFERENCES "ProductVariant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
CREATE INDEX "SaleItem_variantId_idx" ON "SaleItem"("variantId");

ALTER TABLE "ProductPriceHistory"
  ADD COLUMN "oldBuyingPrice" DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN "oldSellingPrice" DECIMAL(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN "oldWholesalePrice" DECIMAL(14,2);

ALTER TABLE "ProductTagAssignment" ADD COLUMN "businessId" UUID;
UPDATE "ProductTagAssignment" a SET "businessId" = t."businessId" FROM "ProductTag" t WHERE t."id" = a."tagId";
ALTER TABLE "ProductTagAssignment" ALTER COLUMN "businessId" SET NOT NULL;
ALTER TABLE "ProductTagAssignment" ADD CONSTRAINT "ProductTagAssignment_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
CREATE INDEX "ProductTagAssignment_businessId_idx" ON "ProductTagAssignment"("businessId");
ALTER TABLE "UnitConversion" ADD CONSTRAINT "UnitConversion_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
