CREATE TABLE "NotificationPreference" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "lowStock" BOOLEAN NOT NULL DEFAULT true,
  "outOfStock" BOOLEAN NOT NULL DEFAULT true,
  "dailySummary" BOOLEAN NOT NULL DEFAULT true,
  "creditSale" BOOLEAN NOT NULL DEFAULT true,
  "customerPayment" BOOLEAN NOT NULL DEFAULT true,
  "debtThresholdEnabled" BOOLEAN NOT NULL DEFAULT true,
  "debtThreshold" DECIMAL(14,2) NOT NULL DEFAULT 10000,
  "securityAlerts" BOOLEAN NOT NULL DEFAULT true,
  "newSale" BOOLEAN NOT NULL DEFAULT false,
  "marketing" BOOLEAN NOT NULL DEFAULT false,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "NotificationPreference_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "NotificationPreference_businessId_userId_key"
  ON "NotificationPreference"("businessId", "userId");
CREATE INDEX "NotificationPreference_businessId_idx"
  ON "NotificationPreference"("businessId");

CREATE TABLE "DeviceToken" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "userId" UUID NOT NULL,
  "token" TEXT NOT NULL,
  "platform" TEXT NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "DeviceToken_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "DeviceToken_token_key" ON "DeviceToken"("token");
CREATE INDEX "DeviceToken_businessId_userId_active_idx"
  ON "DeviceToken"("businessId", "userId", "active");
