import { Prisma } from "@prisma/client";

export async function enqueuePushEvent(
  tx: any,
  event: {
    businessId: string;
    eventKey: string;
    kind: string;
    title: string;
    body: string;
    data: Record<string, unknown>;
    inApp?: boolean;
  },
) {
  await tx.$executeRaw(Prisma.sql`
    INSERT INTO "PushEvent" ("id", "businessId", "eventKey", "kind", "title", "body", "data", "status", "attempts", "createdAt", "updatedAt")
    VALUES (gen_random_uuid(), ${event.businessId}::uuid, ${event.eventKey}, ${event.kind}, ${event.title}, ${event.body},
      ${JSON.stringify(event.data)}::jsonb, 'PENDING', 0, NOW(), NOW())
    ON CONFLICT ("eventKey") DO NOTHING
  `);
  if (event.inApp === false) return;
  const roles = event.kind === "low_stock" || event.kind === "out_of_stock"
    ? ["OWNER", "MANAGER", "STOREKEEPER"]
    : ["OWNER", "MANAGER"];
  const preferenceField = ({
    low_stock: '"lowStock"',
    out_of_stock: '"outOfStock"',
    credit_sale: '"creditSale"',
    customer_payment: '"customerPayment"',
    debt_threshold: '"debtThresholdEnabled"',
    security_alert: '"securityAlerts"',
    new_sale: '"newSale"',
    daily_summary: '"dailySummary"',
  } as Record<string, string>)[event.kind] ?? '"securityAlerts"';
  const users = await tx.$queryRaw(Prisma.sql`
    SELECT u."id" FROM "User" u
    LEFT JOIN "NotificationPreference" p ON p."businessId" = u."businessId" AND p."userId" = u."id"
    WHERE u."businessId" = ${event.businessId}::uuid AND u."deletedAt" IS NULL
      AND u."role" IN (${Prisma.join(roles)}) AND COALESCE(p.${Prisma.raw(preferenceField)}, true) = true
      AND (${event.kind} <> 'debt_threshold' OR (
        COALESCE(p."debtThresholdEnabled", true) = true
        AND ${Number(event.data.newBalance ?? 0)} >= COALESCE(p."debtThreshold", 10000)
        AND ${Number(event.data.oldBalance ?? 0)} < COALESCE(p."debtThreshold", 10000)
      ))
  `) as Array<{ id: string }>;
  for (const user of users) {
    await tx.$executeRaw(Prisma.sql`
      INSERT INTO "Alert" ("id", "businessId", "userId", "kind", "title", "body", "data", "critical", "dedupeKey", "read", "createdAt")
      VALUES (gen_random_uuid(), ${event.businessId}::uuid, ${user.id}::uuid, ${event.kind}, ${event.title}, ${event.body},
        ${JSON.stringify(event.data)}::jsonb, ${event.kind === "out_of_stock" || event.kind === "security_alert"},
        ${`${event.eventKey}:user:${user.id}`}, false, NOW())
      ON CONFLICT ("dedupeKey") DO NOTHING
    `);
  }
}
