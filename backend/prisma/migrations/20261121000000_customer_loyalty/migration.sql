-- Add loyalty points to customers and a ledger of manual adjustments.
ALTER TABLE "Customer" ADD COLUMN "loyaltyPoints" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE "LoyaltyAdjustment" (
    "id" UUID NOT NULL,
    "businessId" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "points" INTEGER NOT NULL,
    "reason" TEXT,
    "idempotencyKey" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,


CREATE UNIQUE INDEX "LoyaltyAdjustment_businessId_idempotencyKey_key" ON "LoyaltyAdjustment"("businessId", "idempotencyKey");
CREATE INDEX "LoyaltyAdjustment_businessId_customerId_createdAt_idx" ON "LoyaltyAdjustment"("businessId", "customerId", "createdAt");

ALTER TABLE "LoyaltyAdjustment" ADD CONSTRAINT "LoyaltyAdjustment_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
