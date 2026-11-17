import {
  Body,
  Controller,
  Get,
  Module,
  Patch,
  Post,
  Delete,
  UseGuards,
} from "@nestjs/common";
import { Type } from "class-transformer";
import { IsBoolean, IsIn, IsNotEmpty, IsNumber, IsOptional, IsString, MaxLength, Min } from "class-validator";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me } from "../common/auth";
import { FirebasePushService } from "./firebase_push.service";

class PreferencePatchDto {
  @IsOptional() @IsBoolean() lowStock?: boolean;
  @IsOptional() @IsBoolean() outOfStock?: boolean;
  @IsOptional() @IsBoolean() dailySummary?: boolean;
  @IsOptional() @IsBoolean() creditSale?: boolean;
  @IsOptional() @IsBoolean() customerPayment?: boolean;
  @IsOptional() @IsBoolean() debtThresholdEnabled?: boolean;
  @IsOptional() @Type(() => Number) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) debtThreshold?: number;
  @IsOptional() @IsBoolean() securityAlerts?: boolean;
  @IsOptional() @IsBoolean() newSale?: boolean;
  @IsOptional() @IsBoolean() marketing?: boolean;
}

class DeviceDto {
  @IsString() @IsNotEmpty() @MaxLength(4096) token: string;
  @IsIn(["android", "ios", "web"]) platform: string;
}

class DeviceTokenDto {
  @IsString() @IsNotEmpty() @MaxLength(4096) token: string;
}

@Controller("notifications")
@UseGuards(AuthGuard)
class NotificationsController {
  constructor(private db: PrismaService) {}

  @Get("preferences") async getPreferences(@Me() user: any) {
    await this.db.$executeRaw(Prisma.sql`
      INSERT INTO "NotificationPreference" ("id", "businessId", "userId", "updatedAt")
      VALUES (gen_random_uuid(), ${user.businessId}::uuid, ${user.sub}::uuid, NOW())
      ON CONFLICT ("businessId", "userId") DO NOTHING
    `);
    const [row] = await this.db.$queryRaw<Array<Record<string, unknown>>>(Prisma.sql`
      SELECT * FROM "NotificationPreference" WHERE "businessId" = ${user.businessId}::uuid AND "userId" = ${user.sub}::uuid
    `);
    return row;
  }

  @Patch("preferences") async updatePreferences(
    @Me() user: any,
    @Body() patch: PreferencePatchDto,
  ) {
    await this.getPreferences(user);
    const updates = Object.entries(patch);
    for (const [field, value] of updates) {
      // `field` is restricted by the validated DTO to this allowlist.
      await this.db.$executeRaw(Prisma.sql`
        UPDATE "NotificationPreference" SET ${Prisma.raw(`"${field}"`)} = ${value}, "updatedAt" = NOW()
        WHERE "businessId" = ${user.businessId}::uuid AND "userId" = ${user.sub}::uuid
      `);
    }
    return this.getPreferences(user);
  }

  @Post("devices") async registerDevice(@Me() user: any, @Body() body: DeviceDto) {
    const rows = await this.db.$queryRaw<Array<{ id: string; platform: string; active: boolean }>>(Prisma.sql`
      INSERT INTO "DeviceToken" ("id", "businessId", "userId", "token", "platform", "active", "createdAt", "updatedAt")
      VALUES (gen_random_uuid(), ${user.businessId}::uuid, ${user.sub}::uuid, ${body.token}, ${body.platform}, true, NOW(), NOW())
      ON CONFLICT ("token") DO UPDATE SET "businessId" = EXCLUDED."businessId", "userId" = EXCLUDED."userId",
        "platform" = EXCLUDED."platform", "active" = true, "updatedAt" = NOW()
      RETURNING "id", "platform", "active"
    `);
    return rows[0];
  }

  @Delete("devices") async unregisterDevice(@Me() user: any, @Body() body: DeviceTokenDto) {
    const count = await this.db.$executeRaw(Prisma.sql`
      UPDATE "DeviceToken" SET "active" = false, "updatedAt" = NOW()
      WHERE "token" = ${body.token} AND "businessId" = ${user.businessId}::uuid AND "userId" = ${user.sub}::uuid
    `);
    return { removed: count > 0 };
  }
}

@Module({ controllers: [NotificationsController], providers: [AuthGuard, FirebasePushService] })
export class NotificationsModule {}
