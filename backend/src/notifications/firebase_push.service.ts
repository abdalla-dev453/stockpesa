import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { createSign } from "node:crypto";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma.service";
import { enqueuePushEvent } from "./push_outbox";

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id?: string;
};
type PushEvent = {
  id: string;
  businessId: string;
  kind: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  attempts: number;
};

@Injectable()
export class FirebasePushService implements OnModuleInit, OnModuleDestroy {
  private timer?: ReturnType<typeof setInterval>;
  private draining = false;
  private ticking = false;
  private cachedToken?: { value: string; expiresAt: number };

  constructor(private db: PrismaService) {}

  onModuleInit() {
    this.timer = setInterval(() => void this.tick(), 15_000);
    this.timer.unref?.();
    void this.tick();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  private account(): ServiceAccount | null {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!raw) return null;
    try {
      const value = JSON.parse(raw) as ServiceAccount;
      return value.client_email && value.private_key ? value : null;
    } catch {
      return null;
    }
  }

  private projectId(account: ServiceAccount) {
    return process.env.FIREBASE_PROJECT_ID || account.project_id || "";
  }

  private async tick() {
    if (this.ticking) return;
    this.ticking = true;
    try {
      await this.queueDailySummaries();
      await this.drain();
    } catch (error) {
      process.stderr.write(`Notification scheduler failed: ${String(error).slice(0, 300)}\n`);
    } finally {
      this.ticking = false;
    }
  }

  private async queueDailySummaries() {
    const now = new Date();
    // Send once each day at 20:00 East Africa Time (17:00 UTC).
    if (now.getUTCHours() !== 17) return;
    const localNow = new Date(now.getTime() + 3 * 60 * 60 * 1000);
    const day = localNow.toISOString().slice(0, 10);
    const start = new Date(`${day}T00:00:00+03:00`);
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    const businesses = await this.db.$queryRaw<Array<{
      id: string;
      sales: Prisma.Decimal;
      profit: Prisma.Decimal;
      lowStock: bigint;
      debt: Prisma.Decimal;
    }>>(Prisma.sql`
      WITH daily_sales AS (
        SELECT s."businessId", COALESCE(SUM(s."total"), 0)::numeric AS sales
        FROM "Sale" s
        WHERE s."saleDate" >= ${start} AND s."saleDate" < ${end}
          AND s."status" NOT IN ('void', 'refunded')
        GROUP BY s."businessId"
      ), daily_profit AS (
        SELECT s."businessId", COALESCE(SUM(si."lineTotal" - si."quantity" * si."unitCost"), 0)::numeric AS profit
        FROM "Sale" s JOIN "SaleItem" si ON si."saleId" = s."id"
        WHERE s."saleDate" >= ${start} AND s."saleDate" < ${end}
          AND s."status" NOT IN ('void', 'refunded')
        GROUP BY s."businessId"
      ), stock_health AS (
        SELECT p."businessId", COUNT(*) FILTER (
          WHERE COALESCE(sl."quantity", 0) <= p."minStock"
        ) AS low_stock
        FROM "Product" p LEFT JOIN "StockLevel" sl ON sl."productId" = p."id"
        WHERE p."deletedAt" IS NULL AND p."active" = true GROUP BY p."businessId"
      ), customer_debt AS (
        SELECT c."businessId", COALESCE(SUM(c."balance"), 0)::numeric AS debt
        FROM "Customer" c WHERE c."deletedAt" IS NULL AND c."balance" > 0
        GROUP BY c."businessId"
      )
      SELECT b."id", COALESCE(ds.sales, 0)::numeric AS sales,
        COALESCE(dp.profit, 0)::numeric AS profit, COALESCE(sh.low_stock, 0) AS "lowStock",
        COALESCE(cd.debt, 0)::numeric AS debt
      FROM "Business" b LEFT JOIN daily_sales ds ON ds."businessId" = b."id"
      LEFT JOIN daily_profit dp ON dp."businessId" = b."id"
      LEFT JOIN stock_health sh ON sh."businessId" = b."id"
      LEFT JOIN customer_debt cd ON cd."businessId" = b."id"
    `);
    for (const business of businesses) {
      await this.db.$transaction((tx) => enqueuePushEvent(tx, {
        businessId: business.id,
        eventKey: `daily-summary:${business.id}:${day}`,
        kind: "daily_summary",
        title: "Daily business summary",
        body: `${day}: KES ${Number(business.sales).toFixed(2)} sales; estimated profit KES ${Number(business.profit).toFixed(2)}; ${Number(business.lowStock)} low-stock products; customer debt KES ${Number(business.debt).toFixed(2)}.`,
        data: { path: "/reports", date: day },
      }));
    }
  }

  private async accessToken(account: ServiceAccount): Promise<string> {
    if (this.cachedToken && this.cachedToken.expiresAt > Date.now() + 60_000) {
      return this.cachedToken.value;
    }
    const now = Math.floor(Date.now() / 1000);
    const encode = (input: unknown) => Buffer.from(JSON.stringify(input)).toString("base64url");
    const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })}`;
    const signer = createSign("RSA-SHA256");
    signer.update(unsigned);
    const assertion = `${unsigned}.${signer.sign(account.private_key, "base64url")}`;
    const response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });
    const payload = (await response.json()) as { access_token?: string; expires_in?: number; error?: string };
    if (!response.ok || !payload.access_token) {
      throw new Error(`Firebase OAuth failed (${response.status}): ${payload.error ?? "access token unavailable"}`);
    }
    this.cachedToken = {
      value: payload.access_token,
      expiresAt: Date.now() + (payload.expires_in ?? 3600) * 1000,
    };
    return payload.access_token;
  }

  private async send(projectId: string, account: ServiceAccount, token: string, event: PushEvent) {
    const access = await this.accessToken(account);
    const data = Object.fromEntries(
      Object.entries({ ...event.data, eventId: event.id }).map(([key, value]) => [key, String(value)]),
    );
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${access}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: event.title, body: event.body },
            data,
            android: {
              priority: event.kind === "out_of_stock" ? "HIGH" : "NORMAL",
              collapseKey: event.id,
              notification: { tag: event.id },
            },
            apns: { headers: { "apns-collapse-id": event.id } },
          },
        }),
      },
    );
    if (response.ok) return;
    const errorBody = await response.text();
    throw new Error(`FCM ${response.status}: ${errorBody.slice(0, 400)}`);
  }

  private async drain() {
    if (this.draining) return;
    const account = this.account();
    const projectId = account && this.projectId(account);
    if (!account || !projectId) return;
    this.draining = true;
    try {
      const events = await this.db.$transaction(async (tx) => {
        const rows = await tx.$queryRaw<PushEvent[]>(Prisma.sql`
          SELECT "id", "businessId", "kind", "title", "body", "data", "attempts"
          FROM "PushEvent"
          WHERE ("status" = 'PENDING' AND "attempts" < 5 AND (
              "attempts" = 0 OR "updatedAt" < NOW() - (INTERVAL '1 minute' * POWER(2, "attempts" - 1))
            )) OR ("status" = 'PROCESSING' AND "updatedAt" < NOW() - INTERVAL '5 minutes')
          ORDER BY "createdAt" ASC LIMIT 20 FOR UPDATE SKIP LOCKED
        `);
        for (const row of rows) {
          await tx.$executeRaw(Prisma.sql`
            UPDATE "PushEvent" SET "status" = 'PROCESSING', "updatedAt" = NOW()
            WHERE "id" = ${row.id}::uuid
          `);
        }
        return rows;
      });
      for (const event of events) await this.deliver(event, account, projectId);
    } catch (error) {
      // The next poll retries transient database/dispatcher failures.
      process.stderr.write(`Push dispatcher failed: ${String(error).slice(0, 300)}\n`);
    } finally {
      this.draining = false;
    }
  }

  private async deliver(event: PushEvent, account: ServiceAccount, projectId: string) {
    const preferenceField = ({
      out_of_stock: '"outOfStock"',
      low_stock: '"lowStock"',
      credit_sale: '"creditSale"',
      customer_payment: '"customerPayment"',
      debt_threshold: '"debtThresholdEnabled"',
      security_alert: '"securityAlerts"',
      new_sale: '"newSale"',
      daily_summary: '"dailySummary"',
    } as Record<string, string>)[event.kind] ?? '"securityAlerts"';
    const allowedRoles = event.kind === "low_stock" || event.kind === "out_of_stock"
      ? Prisma.sql`('OWNER', 'MANAGER', 'STOREKEEPER')`
      : Prisma.sql`('OWNER', 'MANAGER')`;
    const tokens = await this.db.$queryRaw<Array<{ id: string; token: string }>>(Prisma.sql`
      SELECT d."id", d."token"
      FROM "DeviceToken" d JOIN "User" u ON u."id" = d."userId" AND u."businessId" = d."businessId"
      LEFT JOIN "NotificationPreference" p ON p."businessId" = d."businessId" AND p."userId" = d."userId"
      WHERE d."businessId" = ${event.businessId}::uuid AND d."active" = true AND u."deletedAt" IS NULL
        AND u."role" IN ${allowedRoles}
        AND (COALESCE(${String(event.data?.staffId ?? "")}, '') = '' OR u."id"::text <> ${String(event.data?.staffId ?? "")})
        AND COALESCE(p.${Prisma.raw(preferenceField)}, true) = true
        AND (
          ${event.kind} <> 'debt_threshold' OR (
            COALESCE(p."debtThresholdEnabled", true) = true
            AND ${Number(event.data?.newBalance ?? 0)} >= COALESCE(p."debtThreshold", 10000)
            AND ${Number(event.data?.oldBalance ?? 0)} < COALESCE(p."debtThreshold", 10000)
          )
        )
    `);
    if (!tokens.length) {
      await this.updateEvent(event.id, "SKIPPED", event.attempts, "No opted-in device tokens");
      return;
    }
    let sent = 0;
    const failures: string[] = [];
    for (const device of tokens) {
      try {
        await this.send(projectId, account, device.token, event);
        sent++;
      } catch (error) {
        const message = String(error);
        if (/UNREGISTERED|registration-token-not-registered/i.test(message)) {
          await this.db.$executeRaw(Prisma.sql`
            UPDATE "DeviceToken" SET "active" = false, "updatedAt" = NOW() WHERE "id" = ${device.id}::uuid
          `);
        } else {
          failures.push(message.slice(0, 300));
        }
      }
    }
    if (sent === tokens.length) {
      await this.updateEvent(event.id, "SENT", event.attempts + 1, null);
    } else if (sent > 0) {
      await this.updateEvent(event.id, "PARTIAL", event.attempts + 1, failures.join("; ").slice(0, 500) || "Some device tokens were invalid");
    } else {
      const attempts = event.attempts + 1;
      await this.updateEvent(
        event.id,
        attempts >= 5 ? "FAILED" : "PENDING",
        attempts,
        failures.join("; ").slice(0, 500) || "All registered tokens were invalid",
      );
    }
  }

  private updateEvent(id: string, status: string, attempts: number, error: string | null) {
    return this.db.$executeRaw(Prisma.sql`
      UPDATE "PushEvent" SET "status" = ${status}, "attempts" = ${attempts}, "lastError" = ${error}, "updatedAt" = NOW()
      WHERE "id" = ${id}::uuid
    `);
  }
}
