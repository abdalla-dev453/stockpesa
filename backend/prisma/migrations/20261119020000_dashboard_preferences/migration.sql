CREATE TABLE "DashboardPreference" (
    "id" UUID NOT NULL,
    "businessId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "role" "Role" NOT NULL,
    "layout" JSONB NOT NULL,
    "favorites" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "DashboardPreference_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "DashboardPreference_userId_role_key" ON "DashboardPreference"("userId", "role");
CREATE INDEX "DashboardPreference_businessId_idx" ON "DashboardPreference"("businessId");
ALTER TABLE "DashboardPreference" ADD CONSTRAINT "DashboardPreference_businessId_fkey"
  FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "DashboardPreference" ADD CONSTRAINT "DashboardPreference_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
