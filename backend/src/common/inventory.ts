import { createParamDecorator, ExecutionContext } from "@nestjs/common";
import { Type } from "class-transformer";
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
} from "class-validator";
/** user = { sub, businessId, role, ip, ua } */
export const Ctx = createParamDecorator((_d, c: ExecutionContext) => {
  const r = c.switchToHttp().getRequest();
  return { ...r.user, ip: r.ip, ua: r.headers["user-agent"] };
});
export const clean = (v: any) =>
  v === undefined ? undefined : JSON.parse(JSON.stringify(v));
export const audit = (
  tx: any,
  u: any,
  action: string,
  entityType: string,
  entityId?: string,
  oldValues?: any,
  newValues?: any,
) =>
  tx.auditLog.create({
    data: {
      businessId: u.businessId,
      userId: u.sub,
      action,
      entityType,
      entityId,
      oldValues: clean(oldValues),
      newValues: clean(newValues),
      ipAddress: u.ip,
      userAgent: u.ua,
    },
  });
export class ListQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page = 1;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 20;
  @IsOptional() @IsString() search?: string;
  @IsOptional() @IsUUID() categoryId?: string;
  @IsOptional()
  @IsIn(["ALL", "IN_STOCK", "LOW_STOCK", "OUT_OF_STOCK"])
  stockStatus = "ALL";
  @IsOptional()
  @IsIn(["name", "createdAt", "stockQuantity", "sellingPrice"])
  sortBy = "name";
  @IsOptional() @IsIn(["ASC", "DESC"]) sortOrder = "ASC";
}
