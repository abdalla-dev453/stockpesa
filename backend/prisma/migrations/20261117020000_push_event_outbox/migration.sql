CREATE TABLE "PushEvent" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "eventKey" TEXT NOT NULL,
  "kind" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "data" JSONB NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "lastError" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PushEvent_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "PushEvent_eventKey_key" ON "PushEvent"("eventKey");
CREATE INDEX "PushEvent_status_createdAt_idx" ON "PushEvent"("status", "createdAt");
CREATE INDEX "PushEvent_businessId_idx" ON "PushEvent"("businessId");

ALTER TABLE "Alert" ALTER COLUMN "productId" DROP NOT NULL;
ALTER TABLE "Alert"
  ADD COLUMN "userId" UUID,
  ADD COLUMN "title" TEXT,
  ADD COLUMN "body" TEXT,
  ADD COLUMN "data" JSONB,
  ADD COLUMN "critical" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "dedupeKey" TEXT;
CREATE UNIQUE INDEX "Alert_dedupeKey_key" ON "Alert"("dedupeKey");
CREATE INDEX "Alert_userId_idx" ON "Alert"("userId");
