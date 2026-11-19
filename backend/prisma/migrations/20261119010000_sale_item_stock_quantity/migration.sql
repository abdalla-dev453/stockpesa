ALTER TABLE "SaleItem" ADD COLUMN "stockQuantity" DECIMAL(14,3);
UPDATE "SaleItem" SET "stockQuantity" = "quantity";
ALTER TABLE "SaleItem" ALTER COLUMN "stockQuantity" SET NOT NULL;
