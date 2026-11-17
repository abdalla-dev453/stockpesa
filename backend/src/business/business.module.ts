import {
  BadRequestException, ConflictException, Controller, Delete, Get, NotFoundException,
  Param, ParseUUIDPipe, Patch, Post, Body, UseGuards, Module,
} from "@nestjs/common";
import { IsEmail, IsIn, IsOptional, IsString, MinLength, MaxLength, Matches, ValidateIf } from "class-validator";
import * as bcrypt from "bcrypt";
import { PrismaService } from "../prisma.service";
import { AuthGuard, Me, Roles } from "../common/auth";
import { enqueuePushEvent } from "../notifications/push_outbox";
import { KENYAN_MOBILE_PATTERN, normalizeKenyanPhone } from "../common/phone";

class BusinessPatch {
  @IsOptional() @IsString() name?: string;
  @IsOptional() @IsString() type?: string;
  @IsOptional() @IsString() @ValidateIf((_o, value) => value !== "") @Matches(KENYAN_MOBILE_PATTERN, { message: "Enter a valid Kenyan mobile number" }) phone?: string;
  @IsOptional() @IsString() location?: string;
  @IsOptional() @IsString() currency?: string;
  @IsOptional() @IsString() receiptFooter?: string;
}
class StaffCreate {
  @IsString() @MinLength(2) @MaxLength(100) fullName: string;
  @IsEmail() email: string;
  @IsString() @Matches(KENYAN_MOBILE_PATTERN, { message: "Enter a valid Kenyan mobile number" }) phone: string;
  @IsString() @MinLength(8) @MaxLength(128) password: string;
  @IsIn(["MANAGER", "CASHIER", "STOREKEEPER"]) role: string;
}
class StaffPatch {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(100) fullName?: string;
  @IsOptional() @IsEmail() email?: string;
  @IsOptional() @IsString() @Matches(KENYAN_MOBILE_PATTERN, { message: "Enter a valid Kenyan mobile number" }) phone?: string;
  @IsOptional() @IsIn(["MANAGER", "CASHIER", "STOREKEEPER"]) role?: string;
  @IsOptional() @MinLength(8) password?: string;
}

@Controller("business/profile") @UseGuards(AuthGuard)
class BusinessController {
  constructor(private db: PrismaService) {}
  @Get() get(@Me() u) {
    return this.db.business.findUnique({ where: { id: u.businessId } });
  }
  @Patch() @Roles("OWNER", "MANAGER") async update(@Me() u, @Body() d: BusinessPatch) {
    if (d.currency && !/^[A-Z]{3}$/.test(d.currency))
      throw new BadRequestException("Currency must be a three-letter ISO code");
    return this.db.$transaction(async (tx) => {
      const before = await tx.business.findUnique({ where: { id: u.businessId } });
      const data = { ...d, ...(d.phone !== undefined ? { phone: d.phone.trim() ? normalizeKenyanPhone(d.phone) : null } : {}) };
      const updated = await tx.business.update({ where: { id: u.businessId }, data });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "business.profile.updated", entity: "business", entityId: u.businessId, meta: { changedFields: Object.keys(d), before: Object.fromEntries(Object.keys(d).map((key) => [key, before?.[key]])), after: data as any } } });
      return updated;
    });
  }
}

@Controller("users") @UseGuards(AuthGuard)
class UsersController {
  constructor(private db: PrismaService) {}
  @Get() @Roles("OWNER", "MANAGER") list(@Me() u) {
    return this.db.user.findMany({ where: { businessId: u.businessId, deletedAt: null }, select: { id: true, fullName: true, email: true, phone: true, role: true, createdAt: true }, orderBy: { fullName: "asc" } });
  }
  @Post() @Roles("OWNER") async create(@Me() u, @Body() d: StaffCreate) {
    try {
      const hash = await bcrypt.hash(d.password, 10);
      return await this.db.$transaction(async (tx) => {
        const user = await tx.user.create({ data: { businessId: u.businessId, fullName: d.fullName.trim(), email: d.email.trim().toLowerCase(), phone: normalizeKenyanPhone(d.phone), role: d.role as any, passwordHash: hash }, select: { id: true, fullName: true, email: true, phone: true, role: true } });
        const audit = await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "staff.created", entity: "user", entityId: user.id, meta: { role: user.role, email: user.email } } });
        await enqueuePushEvent(tx, {
          businessId: u.businessId,
          eventKey: `security:${audit.id}`,
          kind: "security_alert",
          title: "New staff account",
          body: `${user.fullName} was added as ${user.role.toLowerCase()}.`,
          data: { staffId: user.id, path: "/staff" },
        });
        return user;
      });
    } catch (e: any) {
      if (e.code === "P2002") throw new ConflictException("Email or phone already belongs to a staff member");
      throw e;
    }
  }
  @Patch(":id") @Roles("OWNER") async update(@Me() u, @Param("id", ParseUUIDPipe) id: string, @Body() d: StaffPatch) {
    const old = await this.db.user.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!old) throw new NotFoundException("Staff member not found");
    if (old.role === "OWNER" && d.role) throw new BadRequestException("Owner role cannot be changed here");
    const data: any = { ...d };
    const passwordChanged = Boolean(data.password);
    if (data.email) data.email = data.email.trim().toLowerCase();
    if (data.phone) data.phone = normalizeKenyanPhone(data.phone);
    if (data.fullName) data.fullName = data.fullName.trim();
    if (data.password) { data.passwordHash = await bcrypt.hash(data.password, 10); data.refreshHash = null; delete data.password; }
    if (data.role && data.role !== old.role) data.refreshHash = null;
    try { return await this.db.$transaction(async (tx) => {
      const user = await tx.user.update({ where: { id }, data, select: { id: true, fullName: true, email: true, phone: true, role: true } });
      const audit = await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "staff.updated", entity: "user", entityId: id, meta: { previousRole: old.role, role: user.role, changedFields: Object.keys(d).filter((key) => key !== "password") } } });
      if (old.role !== user.role || passwordChanged) {
        await enqueuePushEvent(tx, {
          businessId: u.businessId,
          eventKey: `security:${audit.id}`,
          kind: "security_alert",
          title: old.role !== user.role ? "Staff role changed" : "Staff password changed",
          body: old.role !== user.role
            ? `${user.fullName}'s role changed from ${old.role.toLowerCase()} to ${user.role.toLowerCase()}.`
            : `The password for ${user.fullName} was changed.`,
          data: { staffId: user.id, path: "/staff" },
        });
      }
      return user;
    }); }
    catch (e: any) { if (e.code === "P2002") throw new ConflictException("Email or phone already belongs to a staff member"); throw e; }
  }
  @Delete(":id") @Roles("OWNER") async remove(@Me() u, @Param("id", ParseUUIDPipe) id: string) {
    if (id === u.sub) throw new BadRequestException("You cannot deactivate your own account");
    const target = await this.db.user.findFirst({ where: { id, businessId: u.businessId, deletedAt: null } });
    if (!target) throw new NotFoundException("Staff member not found");
    if (target.role === "OWNER") throw new BadRequestException("Another owner cannot be deactivated here");
    await this.db.$transaction(async (tx) => {
      await tx.user.update({ where: { id }, data: { deletedAt: new Date(), refreshHash: null } });
      await tx.auditLog.create({ data: { businessId: u.businessId, userId: u.sub, action: "staff.deactivated", entity: "user", entityId: id, meta: { role: target.role } } });
    });
    return { id, deactivated: true };
  }
}
@Module({ controllers: [BusinessController, UsersController], providers: [AuthGuard] })
export class BusinessModule {}
