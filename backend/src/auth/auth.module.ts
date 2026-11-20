import {
  Module,
  Injectable,
  Controller,
  Post,
  Get,
  Body,
  UnauthorizedException,
  ConflictException,
  BadRequestException,
  UseGuards,
} from "@nestjs/common";
import { Throttle } from "@nestjs/throttler";
import { JwtService } from "@nestjs/jwt";
import { IsEmail, IsString, MinLength, IsOptional, Matches, MaxLength, IsBoolean } from "class-validator";
import * as bcrypt from "bcrypt";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me } from "../common/auth";
import { KENYAN_MOBILE_PATTERN, normalizeKenyanPhone } from "../common/phone";
import { enqueuePushEvent } from "../notifications/push_outbox";
function ttlSeconds(value: string | undefined, fallback: number): number {
  const match = /^(\d+)(s|m|h|d)$/.exec(value ?? "");
  if (!match) return fallback;
  return Number(match[1]) * ({ s: 1, m: 60, h: 3600, d: 86400 }[match[2]]);
}
class RegisterDto {
  @IsString() @MinLength(2) @MaxLength(100) businessName: string;
  @IsString() @MinLength(2) @MaxLength(100) fullName: string;
  @IsString() @Matches(KENYAN_MOBILE_PATTERN, { message: "Enter a valid Kenyan mobile number" }) phone: string;
  @IsEmail() email: string;
  @IsString() @MinLength(8) @MaxLength(128) password: string;
  @IsString() @MinLength(2) @MaxLength(80) businessType: string;
  @IsOptional() @IsString() @MaxLength(120) location?: string;
  @IsBoolean() acceptedTerms: boolean;
  @IsString() @MaxLength(20) termsVersion: string;
}
class LoginDto {
  @IsString() identifier: string;
  @IsString() password: string;
}
@Injectable()
class AuthService {
  constructor(
    private db: PrismaService,
    private jwt: JwtService,
  ) {}
  private async tokens(u: any) {
    const p = { sub: u.id, businessId: u.businessId, role: u.role };
    const accessToken = this.jwt.sign(p, {
      secret: process.env.JWT_ACCESS_SECRET,
      expiresIn: ttlSeconds(process.env.ACCESS_TTL, 900),
    });
    const refreshToken = this.jwt.sign(p, {
      secret: process.env.JWT_REFRESH_SECRET,
      expiresIn: ttlSeconds(process.env.REFRESH_TTL, 2592000),
    });
    await this.db.user.update({
      where: { id: u.id },
      data: { refreshHash: await bcrypt.hash(refreshToken, 8) },
    });
    return {
      accessToken,
      refreshToken,
      user: {
        id: u.id,
        fullName: u.fullName,
        role: u.role,
        businessId: u.businessId,
      },
    };
  }
  async register(d: RegisterDto) {
    if (!d.acceptedTerms || d.termsVersion !== "1.0") {
      throw new BadRequestException("Accept the current terms and privacy notice to create an account");
    }
    const email = d.email.trim().toLowerCase();
    const phone = normalizeKenyanPhone(d.phone);
    try {
      const u = await this.db.$transaction(async (tx) => {
        const b = await tx.business.create({
          data: {
            name: d.businessName.trim(),
            type: d.businessType.trim(),
            location: d.location?.trim(),
            phone,
          },
        });
        await tx.category.createMany({
          data: ["Groceries", "Drinks", "Household", "Personal Care", "Hardware", "Stationery"].map((name) => ({
            businessId: b.id,
            name,
          })),
        });
        const user = await tx.user.create({
          data: {
            businessId: b.id,
            fullName: d.fullName.trim(),
            email,
            phone,
            role: "OWNER",
            passwordHash: await bcrypt.hash(d.password, 10),
            termsAcceptedAt: new Date(),
            termsVersion: d.termsVersion,
          },
        });
        await tx.auditLog.create({ data: { businessId: b.id, userId: user.id, action: "business.registered", entity: "business", entityId: b.id, meta: { ownerId: user.id } } });
        return user;
      });
      return this.tokens(u);
    } catch (e: any) {
      if (e.code === "P2002") throw new ConflictException("Email or phone already registered");
      throw e;
    }
  }
  async login(d: LoginDto) {
    const identifier = d.identifier.trim();
    const u = await this.db.user.findFirst({
      where: {
        deletedAt: null,
        OR: [{ email: identifier.toLowerCase() }, { phone: KENYAN_MOBILE_PATTERN.test(identifier) ? normalizeKenyanPhone(identifier) : identifier }],
      },
    });
    if (!u || !(await bcrypt.compare(d.password, u.passwordHash)))
      throw new UnauthorizedException("Wrong phone/email or password");
    await this.db.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${u.id + ":first-login"}))`;
      const prior = await tx.auditLog.findFirst({
        where: { businessId: u.businessId, userId: u.id, action: "staff.first_login" },
        select: { id: true },
      });
      if (prior) return;
      const audit = await tx.auditLog.create({
        data: {
          businessId: u.businessId,
          userId: u.id,
          action: "staff.first_login",
          entity: "user",
          entityId: u.id,
          meta: { role: u.role },
        },
      });
      if (u.role !== "OWNER") {
        await enqueuePushEvent(tx, {
          businessId: u.businessId,
          eventKey: `security:${audit.id}`,
          kind: "security_alert",
          title: "New staff login",
          body: `${u.fullName} signed in for the first time.`,
          data: { staffId: u.id, path: "/staff" },
        });
      }
    });
    return this.tokens(u);
  }
  async refresh(token: string) {
    try {
      const p = this.jwt.verify(token, {
        secret: process.env.JWT_REFRESH_SECRET,
      });
      const u = await this.db.user.findUnique({ where: { id: p.sub } });
      if (!u || u.deletedAt || u.businessId !== p.businessId || !u.refreshHash || !(await bcrypt.compare(token, u.refreshHash)))
        throw 0;
      return this.tokens(u);
    } catch {
      throw new UnauthorizedException("Session expired, log in again");
    }
  }
  logout(id: string) {
    return this.db.user.update({ where: { id }, data: { refreshHash: null }, select: { id: true } });
  }
}
@Controller("auth")
class AuthController {
  constructor(
    private s: AuthService,
    private db: PrismaService,
  ) {}
  @Throttle({ default: { limit: 3, ttl: 1000 } }) @Post("register") register(@Body() d: RegisterDto) {
    return this.s.register(d);
  }
  @Throttle({ default: { limit: 5, ttl: 60000 } }) @Post("login") login(@Body() d: LoginDto) {
    return this.s.login(d);
  }
  @Throttle({ default: { limit: 30, ttl: 60000 } }) @Post("refresh") refresh(@Body("refreshToken") t: string) {
    return this.s.refresh(t);
  }
  @UseGuards(AuthGuard) @Post("logout") logout(@Me() u) {
    return this.s.logout(u.sub);
  }
  @UseGuards(AuthGuard) @Get("me") me(@Me() u) {
    return this.db.user.findUnique({
      where: { id: u.sub },
      select: {
        id: true,
        fullName: true,
        role: true,
        email: true,
        phone: true,
        businessId: true,
      },
    });
  }
}
@Module({
  controllers: [AuthController],
  providers: [AuthService, AuthGuard],
  exports: [AuthGuard],
})
export class AuthModule {}
