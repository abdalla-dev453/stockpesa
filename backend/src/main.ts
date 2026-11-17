import "dotenv/config";
import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { ValidationPipe, Logger } from "@nestjs/common";
import { SwaggerModule, DocumentBuilder } from "@nestjs/swagger";
import * as express from "express";
import { AppModule } from "./app.module";
async function bootstrap() {
  const production = process.env.NODE_ENV === "production";
  if (!['disabled', 'mock'].includes(process.env.MPESA_MODE ?? 'mock')) {
    throw new Error("MPESA_MODE must be either 'disabled' or 'mock' for the current V1 provider support");
  }
  if (production && process.env.MPESA_MODE !== "disabled") {
    throw new Error("Production must set MPESA_MODE=disabled until a live payment provider is configured");
  }
  const corsOrigins = (process.env.CORS_ORIGINS ?? "")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean);
  if (production && (!corsOrigins.length || corsOrigins.includes("*"))) {
    throw new Error("Production requires explicit CORS_ORIGINS; wildcard CORS is disabled");
  }
  if (production && corsOrigins.some((origin) => /example\.com|localhost|127\.0\.0\.1/i.test(origin))) {
    throw new Error("Production CORS_ORIGINS still contains a development/example origin");
  }
  for (const key of ["JWT_ACCESS_SECRET", "JWT_REFRESH_SECRET", "MPESA_CALLBACK_SECRET"]) {
    if (production && (!process.env[key] || process.env[key]!.length < 32 || /change-me|replace-with|generate_|placeholder|example/i.test(process.env[key]!))) {
      throw new Error(`${key} must be set to a unique secret of at least 32 characters in production`);
    }
  }
  if (production && process.env.JWT_ACCESS_SECRET === process.env.JWT_REFRESH_SECRET) {
    throw new Error("JWT access and refresh secrets must be different");
  }
  const port = Number(process.env.PORT ?? 3000);
  const adjustmentThreshold = Number(process.env.ADJUSTMENT_NOTE_THRESHOLD ?? 10);
  const proxyHops = Number(process.env.TRUST_PROXY_HOPS ?? 0);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("PORT must be a valid TCP port");
  if (!Number.isFinite(adjustmentThreshold) || adjustmentThreshold < 0) throw new Error("ADJUSTMENT_NOTE_THRESHOLD must be zero or greater");
  if (!Number.isInteger(proxyHops) || proxyHops < 0 || proxyHops > 10) throw new Error("TRUST_PROXY_HOPS must be an integer from 0 to 10");

  const app = await NestFactory.create(AppModule, { bodyParser: false });
  const server = app.getHttpAdapter().getInstance();
  // Keep V1 paths working while exposing the canonical versioned V2 contract.
  server.use((req, _res, next) => {
    if (req.url === "/api/v1" || req.url.startsWith("/api/v1/")) req.url = req.url.slice(7) || "/";
    next();
  });
  server.disable("x-powered-by");
  server.use(express.json({ limit: "256kb" }));
  server.use(express.urlencoded({ limit: "256kb", extended: true }));
  if (Number.isInteger(proxyHops) && proxyHops > 0) server.set("trust proxy", proxyHops);
  const allowedOrigins = corsOrigins.length
    ? corsOrigins
    : ["http://localhost:3000", "http://localhost:5173", "http://127.0.0.1:3000", "http://127.0.0.1:5173"];
  app.enableCors({
    origin: (origin, callback) => {
      if (!origin) return callback(null, true);
      if (allowedOrigins.includes(origin)) return callback(null, true);
      // In local development, permit any localhost / 127.0.0.1 port (e.g. random Flutter Chrome dev server ports)
      if (!production && /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
        return callback(null, true);
      }
      return callback(null, false);
    },
    credentials: true,
    maxAge: 600,
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "Idempotency-Key", "X-Mpesa-Signature"],
  });

  // API-safe Helmet-equivalent headers; Swagger is an API document, not an HTML app.
  app.use((req, res, next) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("X-Frame-Options", "DENY");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
    res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
    if (!req.path.startsWith("/docs")) {
      res.setHeader("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
    }
    if (production) res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
    next();
  });

  // Small per-process guard for credential and provider callback endpoints.
  // Production deployments should also apply a shared gateway rate limit.
  const buckets = new Map<string, { start: number; count: number }>();
  const limits: Record<string, { count: number; window: number }> = {
    "POST /auth/login": { count: 10, window: 15 * 60_000 },
    "POST /auth/register": { count: 5, window: 60 * 60_000 },
    "POST /auth/refresh": { count: 30, window: 60_000 },
    "POST /payments/mpesa/callback": { count: 120, window: 60_000 },
  };
  app.use((req, res, next) => {
    const limit = limits[`${req.method} ${req.path}`];
    if (!limit) return next();
    const now = Date.now();
    const key = `${req.ip}:${req.method}:${req.path}`;
    let bucket = buckets.get(key);
    if (!bucket || now - bucket.start >= limit.window) {
      bucket = { start: now, count: 0 };
      buckets.set(key, bucket);
    }
    bucket.count++;
    res.setHeader("RateLimit-Limit", limit.count);
    res.setHeader("RateLimit-Remaining", Math.max(0, limit.count - bucket.count));
    if (bucket.count > limit.count) {
      res.setHeader("Retry-After", Math.max(1, Math.ceil((bucket.start + limit.window - now) / 1000)));
      return res.status(429).json({ statusCode: 429, message: "Too many attempts. Please try again later." });
    }
    if (buckets.size > 10_000) {
      for (const [bucketKey, value] of buckets) if (now - value.start >= limit.window) buckets.delete(bucketKey);
    }
    next();
  });

  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }),
  );
  app.use((req, _res, next) => {
    Logger.log(`${req.method} ${req.path}`, "HTTP");
    next();
  });
  if (!production || process.env.ENABLE_SWAGGER === "true") {
    const doc = SwaggerModule.createDocument(
      app,
      new DocumentBuilder().setTitle("StockPesa API").setDescription("Canonical API base: /api/v1. Unversioned V1 paths remain available during migration.").addServer("/api/v1").addBearerAuth().build(),
    );
    SwaggerModule.setup("docs", app, doc);
  }
  await app.listen(port, "0.0.0.0");
}
bootstrap();
